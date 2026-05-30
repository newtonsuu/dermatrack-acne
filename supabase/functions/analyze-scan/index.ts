// DermaTrack — analyze-scan Edge Function
// ============================================
// Receives a freshly-uploaded scan image path, runs detection against the
// Roboflow `acne-detection-zukbx/4` model, derives a Cook-style severity
// grade and per-bucket lesion counts, and inserts a row into public.scans.
// Returns the inserted row so the Flutter client can navigate straight to
// the scan-detail screen without a second round-trip.
//
// Phase 2 (this file): Roboflow + HF skintelligent classifier in parallel.
// Roboflow gives per-lesion detections (for the overlay) and a count-based
// Cook grade; HF gives a holistic severity classification. The two votes
// are combined via `combineCookGrades` — HF wins on 2+ bucket disagreement,
// Roboflow's grade is kept otherwise. HF failure soft-degrades to
// Roboflow-only without breaking the scan.
//
// Deploy:
//   supabase functions deploy analyze-scan
// Set secrets (one-time):
//   supabase secrets set ROBOFLOW_API_KEY=<key>
//   supabase secrets set HF_SPACE_URL=https://apjakilan-dermatrack-skintelligent.hf.space
// Invoke (Flutter side, via supabase_flutter):
//   final res = await Supabase.instance.client.functions.invoke(
//     'analyze-scan',
//     body: {'scan_id': '<uuid>', 'image_path': '<userId>/<scanId>.jpg'},
//   );
// ============================================

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ----- Config -----
const ROBOFLOW_PROJECT = "acne-detection-zukbx";
const ROBOFLOW_VERSION = "4";

// Valid region values. Mirrors the CHECK constraint on public.scans.region
// (migration 0004_scan_regions.sql) and the ScanRegion enum on the Flutter
// side (models/scan.dart). Defensive copy lives here so a typo in the
// client can't slip a bad value into the database — we'd surface a 400
// before the insert attempts.
const VALID_REGIONS = new Set([
  "forehead",
  "left_cheek",
  "right_cheek",
  "chin",
  "full_face",
]);

// When the client passes a face bounding box, we widen it by this ratio in
// each dimension before filtering Roboflow detections. ML Kit's bbox is
// tight to eyes/nose/mouth/chin and excludes the forehead above the
// hairline and the area around the ears — both legitimately home to acne.
// 15% padding keeps those captured without re-admitting most background.
const FACE_BBOX_PADDING_RATIO = 0.15;
// Confidence threshold for Roboflow detections. Override at runtime by
// setting the `ROBOFLOW_CONFIDENCE` secret (decimal 0-1 or percentage 1-100;
// both are accepted). 0.4 is the default — reasonable balance between
// false positives (random skin texture flagged as a lesion) and false
// negatives (missed small comedones). Lower the value to boost recall on
// dense-acne images; raise it to suppress noisy detections on clean skin.
const ROBOFLOW_CONFIDENCE_THRESHOLD: number = (() => {
  const raw = Deno.env.get("ROBOFLOW_CONFIDENCE");
  if (!raw) return 0.4;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return 0.4;
  // Accept "25" (percent) or "0.25" (decimal) interchangeably.
  const decimal = n > 1 ? n / 100 : n;
  // Clamp to (0, 1] to keep Roboflow from rejecting nonsense values.
  return Math.min(Math.max(decimal, 0.01), 1);
})();
// How long the signed URL we hand to Roboflow + the HF Space stays valid.
// Roboflow fetches in 1-2 s, but HF can be cold (30-60 s to wake up) and
// then Gradio's queue may not pull our URL for another few seconds, so we
// need a generous TTL. Still short enough that a leaked URL isn't a long-
// lived problem.
const SIGNED_URL_TTL_SECONDS = 300;

// ----- CORS -----
// Required so the Flutter web build (eventual thesis survey deployment) can
// invoke this function from a browser. Mobile platforms ignore CORS but
// these headers don't hurt them.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ----- Helpers -----

// Build a JSON response with CORS headers baked in. Saves repeating the
// boilerplate at every return site.
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Shape of the optional face bounding box the client forwards from its
// ML Kit preflight. Coordinates are in the same pixel space as the
// uploaded image — same space Roboflow returns its predictions in — so
// no scaling math is needed before comparing them.
interface FaceBbox {
  x: number;
  y: number;
  w: number;
  h: number;
  image_w?: number;
  image_h?: number;
}

// Returns true if [predCenterX, predCenterY] (Roboflow center coords) lies
// inside [bbox] after padding it by FACE_BBOX_PADDING_RATIO. We pad the
// box rather than the predictions so a small bbox on a tight-cropped
// selfie still admits forehead/jawline detections without re-admitting
// the entire background.
function isInsidePaddedBbox(
  predCenterX: number,
  predCenterY: number,
  bbox: FaceBbox,
): boolean {
  const padX = bbox.w * FACE_BBOX_PADDING_RATIO;
  const padY = bbox.h * FACE_BBOX_PADDING_RATIO;
  const minX = bbox.x - padX;
  const maxX = bbox.x + bbox.w + padX;
  const minY = bbox.y - padY;
  const maxY = bbox.y + bbox.h + padY;
  return (
    predCenterX >= minX &&
    predCenterX <= maxX &&
    predCenterY >= minY &&
    predCenterY <= maxY
  );
}

// Map a Roboflow class name to one of our three buckets. The schema's
// `inflammatory_count`, `non_inflammatory_count`, `post_acne_count` columns
// come from these counts. We strip a trailing 's' so plurals and singulars
// both work — zukbx/4 returns plurals ("papules") but other models might
// emit singulars, and our future taxonomy expansions might mix.
function bucketForClass(
  rawClass: string,
): "inflammatory" | "non_inflammatory" | "post_acne" | "unknown" {
  const c = rawClass.toLowerCase().trim().replace(/s$/, "");
  if (["papule", "pustule", "nodule", "cyst"].includes(c)) {
    return "inflammatory";
  }
  if (["comedone", "whitehead", "blackhead"].includes(c)) {
    return "non_inflammatory";
  }
  if (["dark_spot", "dark-spot", "darkspot"].includes(c)) {
    return "post_acne";
  }
  return "unknown";
}

// Derive a Cook-scale grade (0-8) from lesion counts.
//
// Cook's scale, simplified:
//   0 = none
//   2 = a few non-inflammatory comedones
//   4 = mild inflammatory (some papules/pustules)
//   6 = moderate (numerous inflammatory)
//   8 = severe (numerous inflammatory + nodules/cysts)
//
// This is a heuristic, intentionally on the conservative side. Once the HF
// skintelligent classifier is wired in (phase 2), we'll cross-reference its
// severity output and prefer it when it disagrees by more than one bucket.
function deriveCookGrade(inflammatory: number, nonInflammatory: number): number {
  if (inflammatory === 0 && nonInflammatory === 0) return 0;
  if (inflammatory >= 16) return 8;
  if (inflammatory >= 8) return 6;
  if (inflammatory >= 3) return 4;
  if (inflammatory + nonInflammatory >= 3) return 2;
  return 1;
}

// Map Cook grade to the human-readable label stored in `severity_label`.
// The five-label scheme matches schema.md and gives the scan-detail UI
// enough resolution to render distinct copy.
function severityLabelFromCook(cook: number): string {
  if (cook < 0) return "Clear";
  if (cook === 0) return "Clear";
  if (cook <= 2) return "Mild";
  if (cook <= 4) return "Moderate";
  if (cook <= 6) return "Severe";
  return "Very Severe";
}

// Map a skintelligent-acne HF label to a Cook grade.
//
// The model's 6 classes are labelled with an integer "level" from -1 to 4
// (level -1 = Clear, level 4 = Very Severe). We pull the numeric token out
// of the label string with a regex so this works whether the model card
// emits "level -1", "Level -1", "LEVEL_-1", etc. — only the digit matters.
//
// Mapping rationale:
//   level -1 → 0  (Clear)        — confirmed from app.py comment
//   level 0  → 1  (Almost Clear) — inferred from FDA IGA convention
//   level 1  → 2  (Mild)
//   level 2  → 4  (Moderate)
//   level 3  → 6  (Severe)
//   level 4  → 8  (Very Severe)  — confirmed from app.py comment
//
// The middle four are an educated guess; if a clearly-moderate face comes
// back as level 0 or level 3, the mapping is shifted and we re-calibrate.
function cookFromHFLabel(label: string): number | null {
  const m = label.match(/-?\d+/);
  if (!m) return null;
  const level = parseInt(m[0], 10);
  switch (level) {
    case -1: return 0;
    case 0: return 1;
    case 1: return 2;
    case 2: return 4;
    case 3: return 6;
    case 4: return 8;
    default: return null;
  }
}

// Compress a Cook grade (0-8) into a severity-label bucket index (0-4)
// so we can measure HF↔Roboflow disagreement in the units the user
// actually sees on screen.
//   0: Clear   (Cook 0)
//   1: Mild    (Cook 1-2)
//   2: Moderate(Cook 3-4)
//   3: Severe  (Cook 5-6)
//   4: VerySev (Cook 7-8)
function bucketIndex(cook: number): number {
  if (cook <= 0) return 0;
  if (cook <= 2) return 1;
  if (cook <= 4) return 2;
  if (cook <= 6) return 3;
  return 4;
}

// Combine the Roboflow-derived Cook grade with the HF-derived one.
//
// Policy:
//   • HF call failed → use Roboflow alone (graceful degrade).
//   • Bucket agreement → keep Roboflow (its count is more interpretable).
//   • 1-bucket disagreement → keep Roboflow (small disagreements happen at
//     the boundaries; trusting the count-based grade keeps the UI signal
//     consistent with the visible lesion overlay).
//   • 2+ bucket disagreement → prefer HF. The classifier sees the face
//     holistically; on a dense-acne photo Roboflow may detect only 8
//     lesions when the face is plainly Severe — HF catches that.
//
// `rationale` is recorded in source_metadata so the scan-detail UI can
// surface *why* a given grade was chosen.
function combineCookGrades(
  roboflowCook: number,
  hfCook: number | null,
): {
  cookGrade: number;
  rationale:
    | "roboflow_only"
    | "agreement"
    | "minor_disagreement_kept"
    | "hf_override";
} {
  if (hfCook === null) {
    return { cookGrade: roboflowCook, rationale: "roboflow_only" };
  }
  const rb = bucketIndex(roboflowCook);
  const hf = bucketIndex(hfCook);
  const diff = Math.abs(rb - hf);
  if (diff === 0) {
    return { cookGrade: roboflowCook, rationale: "agreement" };
  }
  if (diff === 1) {
    return { cookGrade: roboflowCook, rationale: "minor_disagreement_kept" };
  }
  return { cookGrade: hfCook, rationale: "hf_override" };
}

// ----- Roboflow call -----

// Shape of an individual prediction from Roboflow's hosted inference API.
// `x`, `y` are the *center* of the bbox (Roboflow convention) — we convert
// to top-left when assembling our `lesions` JSONB so the Flutter overlay
// painter has the easier coordinate system to work with.
interface RoboflowPrediction {
  x: number;
  y: number;
  width: number;
  height: number;
  class: string;
  confidence: number;
}

interface RoboflowResponse {
  predictions: RoboflowPrediction[];
  image: { width: number; height: number };
  time?: number;
}

async function callRoboflow(
  imageUrl: string,
  apiKey: string,
): Promise<{ response: RoboflowResponse; latencyMs: number }> {
  const url = new URL(
    `https://detect.roboflow.com/${ROBOFLOW_PROJECT}/${ROBOFLOW_VERSION}`,
  );
  url.searchParams.set("api_key", apiKey);
  // `image` param accepts a publicly-fetchable URL; Roboflow's server
  // downloads it server-side. Saves us from base64-encoding here.
  url.searchParams.set("image", imageUrl);
  url.searchParams.set("confidence", String(ROBOFLOW_CONFIDENCE_THRESHOLD * 100));

  const t0 = Date.now();
  const r = await fetch(url.toString(), { method: "POST" });
  const latencyMs = Date.now() - t0;

  if (!r.ok) {
    const errBody = await r.text();
    throw new Error(`Roboflow ${r.status}: ${errBody}`);
  }
  const response = (await r.json()) as RoboflowResponse;
  return { response, latencyMs };
}

// ----- HF Space call -----

// Shape of the dict our Gradio Space's classify() function returns. Wrapped
// by Gradio at body.data[0] in the HTTP response, so we unwrap to this.
interface HFClassificationOutput {
  model: string;
  top_label: string;
  top_confidence: number;
  predictions: Array<{ label: string; score: number }>;
}

interface HFCallResult {
  output: HFClassificationOutput;
  raw: unknown;
  latencyMs: number;
}

// Call our self-hosted HF Space wrapping `imfarzanansari/skintelligent-acne`.
//
// Gradio's modern API uses a two-step async queue. The cURL example printed
// at <space>/?view=api shows the exact body shape — a NAMED parameter
// ("image", matching `def classify(image)` in app.py) whose value is a
// FileData dict, not an indexed `data: [...]` array. The `meta._type` tag is
// required for Pydantic validation to accept the dict as an ImageData.
//
//   Step 1: POST <space>/gradio_api/call/v2/predict
//           body: {"image": {"path": "<url-or-server-path>",
//                            "meta": {"_type": "gradio.FileData"}}}
//           response: {"event_id": "<uuid>"}
//
//   Step 2: GET <space>/gradio_api/call/predict/<event_id>     (NB: no v2)
//           accept: text/event-stream
//           response: a stream of SSE blocks, e.g.
//             event: heartbeat\n\n          (sent every few seconds, ignore)
//             event: complete\n             (final result; data line has JSON)
//             data: [<classify_return_dict>]\n\n
//             event: error\n                (failure; data is error message)
//             data: ...\n\n
//
// For the `path` field we pass our Supabase signed URL — the API docs say
// the parameter accepts "a local filepath or publicly available URL", and
// Gradio fetches the URL server-side. No upload/base64 needed.
//
// Cold starts on HF free tier can take 30-60 s — both steps will block
// until the Space is up. We run in parallel with Roboflow upstream so the
// cold start latency overlaps rather than stacks.
async function callHFClassifier(
  signedUrl: string,
  spaceUrl: string,
): Promise<HFCallResult> {
  const base = spaceUrl.replace(/\/$/, "");
  const t0 = Date.now();

  // Step 1: enqueue the prediction call. The body shape comes directly from
  // the cURL example on the Space's API docs page.
  const startRes = await fetch(`${base}/gradio_api/call/v2/predict`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      image: {
        path: signedUrl,
        meta: { _type: "gradio.FileData" },
      },
    }),
  });
  if (!startRes.ok) {
    const errBody = await startRes.text();
    throw new Error(
      `HF Space ${startRes.status} (call start): ${errBody.slice(0, 400)}`,
    );
  }
  const startBody = (await startRes.json()) as { event_id?: string };
  const eventId = startBody.event_id;
  if (!eventId) {
    throw new Error(
      `HF Space did not return event_id: ${
        JSON.stringify(startBody).slice(0, 200)
      }`,
    );
  }

  // 4. Step 2: open the SSE stream and read until completion or error.
  const pollRes = await fetch(`${base}/gradio_api/call/predict/${eventId}`, {
    headers: { "Accept": "text/event-stream" },
  });
  if (!pollRes.ok || !pollRes.body) {
    throw new Error(
      `HF Space ${pollRes.status} (poll): could not open event stream`,
    );
  }

  const reader = pollRes.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let resultArr: unknown[] | null = null;
  let sseErr: string | null = null;

  // SSE event blocks are separated by a blank line (\n\n). Within a block,
  // each line is either `event: <type>` or `data: <payload>`. We collect
  // events until we hit `complete` or `error`.
  outer: while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    let sepIdx = buffer.indexOf("\n\n");
    while (sepIdx !== -1) {
      const block = buffer.slice(0, sepIdx);
      buffer = buffer.slice(sepIdx + 2);

      const lines = block.split("\n");
      const eventType = lines
        .find((l) => l.startsWith("event:"))
        ?.slice(6)
        .trim();
      const dataLine = lines
        .find((l) => l.startsWith("data:"))
        ?.slice(5)
        .trim();

      if (eventType === "complete") {
        if (dataLine) {
          try {
            resultArr = JSON.parse(dataLine);
          } catch {
            throw new Error(
              `Failed to parse Gradio complete data: ${
                dataLine.slice(0, 200)
              }`,
            );
          }
        }
        break outer;
      } else if (eventType === "error") {
        sseErr = dataLine ?? "(no detail)";
        break outer;
      }
      // heartbeat / generating / other events: ignore.
      sepIdx = buffer.indexOf("\n\n");
    }
  }

  await reader.cancel().catch(() => {});
  const latencyMs = Date.now() - t0;

  if (sseErr) {
    throw new Error(`HF Space prediction error: ${sseErr}`);
  }
  if (!resultArr) {
    throw new Error("HF Space event stream ended without completing");
  }

  // 5. Gradio wraps the function's return value(s) in a list. For our
  //    single-output Interface, resultArr[0] is the classify() dict.
  const inner = Array.isArray(resultArr) ? resultArr[0] : resultArr;
  if (!inner || typeof inner !== "object") {
    throw new Error(
      `HF Space returned unexpected shape: ${
        JSON.stringify(resultArr).slice(0, 300)
      }`,
    );
  }
  if ("error" in (inner as Record<string, unknown>)) {
    throw new Error(`HF classify error: ${(inner as { error: string }).error}`);
  }
  const output = inner as HFClassificationOutput;
  if (
    typeof output.top_label !== "string" ||
    typeof output.top_confidence !== "number"
  ) {
    throw new Error(
      `HF Space output missing required fields: ${
        JSON.stringify(output).slice(0, 300)
      }`,
    );
  }

  return {
    output,
    raw: { event_id: eventId, result: resultArr },
    latencyMs,
  };
}

// ----- Main handler -----

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    // 1. Parse the body.
    //    Required: scan_id, image_path.
    //    Optional: region (defaults to 'full_face'), session_id (links a
    //    guided 5-step capture), face_bbox (used to filter background
    //    detections — see Chunk B in 0004_scan_regions.sql).
    let body: {
      scan_id?: string;
      image_path?: string;
      region?: string;
      session_id?: string;
      face_bbox?: FaceBbox;
    };
    try {
      body = await req.json();
    } catch {
      return json({ error: "Body must be JSON" }, 400);
    }
    const { scan_id, image_path } = body;
    if (!scan_id || !image_path) {
      return json({ error: "Missing scan_id or image_path" }, 400);
    }

    // Region defaults to full_face for back-compat with pre-0004 callers
    // (legacy single-scan flow). Validate the value here so a typo in the
    // client surfaces as a 400 rather than a Postgres CHECK violation.
    const region = body.region ?? "full_face";
    if (!VALID_REGIONS.has(region)) {
      return json(
        {
          error:
            `Invalid region '${region}'. Expected one of: ${
              [...VALID_REGIONS].join(", ")
            }.`,
        },
        400,
      );
    }

    // session_id is optional. If present, validate it's a UUID-looking
    // string so we don't push obviously-malformed data into the column.
    // The DB column type (uuid) would reject it too, but a 400 here is
    // friendlier than a 500.
    const sessionId = body.session_id ?? null;
    if (sessionId !== null) {
      const uuidRe =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRe.test(sessionId)) {
        return json({ error: "session_id must be a UUID" }, 400);
      }
    }

    // face_bbox is optional. When omitted, no spatial filtering happens
    // and Roboflow detections are taken at face value.
    const faceBbox = body.face_bbox ?? null;

    // 2. Build a Supabase client scoped to the caller's JWT.
    //    `verify_jwt = true` (the default for Edge Functions) already rejects
    //    unauthenticated calls before this code runs, but we still need the
    //    JWT-scoped client so the INSERT below respects RLS.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header" }, 401);
    }
    const supabase: SupabaseClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    // 3. Confirm the user and read their id. We need it to validate
    //    `image_path` and to write `user_id` on the inserted row.
    const { data: { user }, error: userErr } = await supabase.auth.getUser();
    if (userErr || !user) {
      return json({ error: "Unauthorized" }, 401);
    }

    // 4. Defense in depth: image_path must start with the caller's user_id.
    //    Storage RLS already enforces this on writes, but checking here
    //    avoids generating a signed URL for another user's object (which
    //    we *could* do as the JWT-scoped client but only for objects we
    //    own anyway — RLS would block it).
    const expectedPrefix = `${user.id}/`;
    if (!image_path.startsWith(expectedPrefix)) {
      return json({ error: "image_path must be in your user folder" }, 403);
    }

    // 5. Mint a short-lived signed URL Roboflow can fetch.
    const { data: signed, error: signedErr } = await supabase.storage
      .from("scan-images")
      .createSignedUrl(image_path, SIGNED_URL_TTL_SECONDS);

    if (signedErr || !signed?.signedUrl) {
      return json(
        { error: `Could not sign image URL: ${signedErr?.message ?? "unknown"}` },
        500,
      );
    }

    // 6. Call Roboflow + HF in parallel.
    //    Roboflow failure → hard error (we lose the lesion overlay data).
    //    HF failure → soft degrade (continue with Roboflow-only grading;
    //      classifier_* fields in source_metadata stay null).
    //    Parallel matters: HF cold start can be 30-60 s on free CPU tier,
    //    and running serially would stack that on top of Roboflow's ~5 s.
    const apiKey = Deno.env.get("ROBOFLOW_API_KEY");
    if (!apiKey) {
      return json({ error: "ROBOFLOW_API_KEY secret not set" }, 500);
    }
    const hfSpaceUrl = Deno.env.get("HF_SPACE_URL");

    // If HF_SPACE_URL isn't configured, synthesize a rejection so the
    // settled[1] check below treats it the same as a runtime failure.
    const [rfSettled, hfSettled] = await Promise.allSettled([
      callRoboflow(signed.signedUrl, apiKey),
      hfSpaceUrl
        ? callHFClassifier(signed.signedUrl, hfSpaceUrl)
        : Promise.reject(new Error("HF_SPACE_URL secret not configured")),
    ]);

    if (rfSettled.status === "rejected") {
      console.error("Roboflow call failed:", rfSettled.reason);
      return json(
        {
          error: `Detection service failed: ${(rfSettled.reason as Error).message}`,
        },
        502,
      );
    }
    const detection = rfSettled.value;

    // HF result is allowed to be null — soft degrade to Roboflow-only.
    let hfResult: HFCallResult | null = null;
    if (hfSettled.status === "fulfilled") {
      hfResult = hfSettled.value;
    } else {
      console.error(
        "HF classifier call failed (continuing with Roboflow only):",
        hfSettled.reason,
      );
    }

    // 7. Translate Roboflow's prediction list into our `lesions` JSONB shape.
    //    Center coords → top-left coords. Class → bucket. Drop "unknown"
    //    buckets from the counts but keep them in the array (so we can
    //    diagnose taxonomy gaps later).
    //
    //    Background-isolation step (Chunk B from 0004): if the client sent
    //    a face_bbox from its ML Kit preflight, drop any prediction whose
    //    center falls outside the (padded) face. Solves the "comedone
    //    detected on the background" issue surfaced in the 2026-05-25
    //    dermatologist consult.
    const imgSize = {
      w: detection.response.image.width,
      h: detection.response.image.height,
    };
    let predictionsFilteredOut = 0;
    const rawPredictions = detection.response.predictions;
    const inFacePredictions = faceBbox
      ? rawPredictions.filter((p) => {
          const inside = isInsidePaddedBbox(p.x, p.y, faceBbox);
          if (!inside) predictionsFilteredOut++;
          return inside;
        })
      : rawPredictions;

    const lesions = inFacePredictions.map((p) => ({
      class: p.class,
      bucket: bucketForClass(p.class),
      confidence: p.confidence,
      bbox: {
        x: p.x - p.width / 2,
        y: p.y - p.height / 2,
        w: p.width,
        h: p.height,
      },
      image_size: imgSize,
    }));

    let inflammatory = 0;
    let nonInflammatory = 0;
    let postAcne = 0;
    for (const l of lesions) {
      if (l.bucket === "inflammatory") inflammatory++;
      else if (l.bucket === "non_inflammatory") nonInflammatory++;
      else if (l.bucket === "post_acne") postAcne++;
    }

    // 8. Compute each model's Cook grade independently, then combine.
    //    Both votes are recorded in source_metadata so the scan-detail UI
    //    can show "Detection said X, Classifier said Y, final = Z because
    //    rationale". When HF failed, `hfCook` is null and the combiner
    //    falls through to roboflow_only.
    const roboflowCook = deriveCookGrade(inflammatory, nonInflammatory);
    const hfCook = hfResult
      ? cookFromHFLabel(hfResult.output.top_label)
      : null;
    const combined = combineCookGrades(roboflowCook, hfCook);
    const cookGrade = combined.cookGrade;
    const severityLabel = severityLabelFromCook(cookGrade);

    // 9. Provenance metadata. Kept verbose for debugging — if a user
    //    reports a weird result months later, we can re-derive everything
    //    from `raw_responses`.
    //
    //    face_bbox_filter fields record what the spatial filter actually
    //    did so we can audit it later: if a scan shows zero lesions but
    //    Roboflow originally returned six, the filter is the obvious
    //    suspect and these fields tell us exactly that.
    const sourceMetadata = {
      detection_model: `${ROBOFLOW_PROJECT}/${ROBOFLOW_VERSION}`,
      classifier_model: hfResult?.output.model ?? null,
      detection_latency_ms: detection.latencyMs,
      classifier_latency_ms: hfResult?.latencyMs ?? null,
      confidence_threshold: ROBOFLOW_CONFIDENCE_THRESHOLD,
      // Each model's independent vote, then how we combined them.
      detection_cook_grade: roboflowCook,
      classifier_cook_grade: hfCook,
      classifier_top_label: hfResult?.output.top_label ?? null,
      classifier_top_confidence: hfResult?.output.top_confidence ?? null,
      combiner_rationale: combined.rationale,
      // Background-isolation audit trail (Chunk B).
      face_bbox_filter: {
        applied: faceBbox !== null,
        padding_ratio: faceBbox !== null ? FACE_BBOX_PADDING_RATIO : null,
        predictions_total: rawPredictions.length,
        predictions_kept: lesions.length,
        predictions_filtered_out: predictionsFilteredOut,
      },
      raw_responses: {
        detection: detection.response,
        classification: hfResult?.raw ?? null,
      },
    };

    // 10. Insert the row. Using the JWT-scoped client means RLS enforces
    //     `user_id = auth.uid()` — we can't write a row under someone
    //     else's id even if we tried.
    //     region defaults to 'full_face' at the column level, but we send
    //     it explicitly anyway so the wire/DB values stay in lock-step.
    //     session_id is nullable; we send it whether or not the caller
    //     provided one (sessionId === null is a valid column value).
    const { data: inserted, error: insertErr } = await supabase
      .from("scans")
      .insert({
        id: scan_id,
        user_id: user.id,
        image_path,
        cook_grade: cookGrade,
        severity_label: severityLabel,
        inflammatory_count: inflammatory,
        non_inflammatory_count: nonInflammatory,
        post_acne_count: postAcne,
        lesions,
        source_metadata: sourceMetadata,
        region,
        session_id: sessionId,
      })
      .select()
      .single();

    if (insertErr) {
      console.error("Scan insert failed:", insertErr);
      return json(
        { error: `Could not save scan: ${insertErr.message}` },
        500,
      );
    }

    // 11. Return the inserted row. Flutter side parses this into a Scan
    //     and navigates to scan_detail_screen.
    return json({ scan: inserted }, 200);
  } catch (e) {
    console.error("analyze-scan unhandled error:", e);
    return json({ error: String(e) }, 500);
  }
});
