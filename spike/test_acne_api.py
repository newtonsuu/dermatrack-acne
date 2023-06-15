"""
DermaTrack — Roboflow Universe acne-detection spike.

Why this exists:
  The original plan was to use Eapen's SkinHelpDesk Acne Grading API on
  RapidAPI. As of 2026-05-14 that endpoint is gone from the marketplace.
  Roboflow Universe hosts several community-trained YOLO models that
  do similar work — free hosted inference, no training required.

What this script does:
  1. Reads selfies from ./sample_images/.
  2. For each photo, calls every configured Roboflow model.
  3. Saves the raw JSON response per (model, image) to ./responses/.
  4. Writes a comparison CSV showing total detections, per-class counts,
     max confidence, and latency for each combination.

Use the comparison to pick which model performs best on your team's own
photos. That model becomes the one you wire into the Flutter app.

How to use:
  1. Sign up at https://roboflow.com (free plan is fine for spiking).
     Grab your "Private API Key" from https://app.roboflow.com/settings/api.
  2. Set the API key as an environment variable:
       PowerShell:   $env:ROBOFLOW_API_KEY = "your-key-here"
       bash / zsh:   export ROBOFLOW_API_KEY="your-key-here"
  3. Drop 3-5 selfies into ./sample_images/. Mix lighting + angles.
  4. Install deps:  pip install requests
  5. Run:  python test_acne_api.py
  6. Inspect ./responses/<model_name>/<image>.json — that's your real data.
     Open ./responses/_comparison.csv to compare models side-by-side.

What to look for:
  - Which model fires plausible detection counts on YOUR faces?
  - Class labels — single class ("acne") vs multi-class (papule/pustule/
    comedone/etc.)? Multi-class is what you want for the inflammatory vs
    non-inflammatory split your dermatologist asked for.
  - Latency. Most should be <2s on a free tier.
  - Confidence distribution. If everything is >0.9, the model may be
    over-confident; if <0.3, lower the confidence threshold or pick a
    different model.
"""

from __future__ import annotations

import base64
import csv
import json
import os
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any

import requests


# ============================================================
#  Configuration
# ============================================================
SCRIPT_DIR = Path(__file__).resolve().parent
IMAGES_DIR = SCRIPT_DIR / "sample_images"
RESPONSES_DIR = SCRIPT_DIR / "responses"

# Candidate Roboflow models to spike against.
# Add or remove by editing this list. To find more, search
# https://universe.roboflow.com/search?q=class:acne and open the model page;
# the "endpoint" below is the part after https://detect.roboflow.com/.
# The "page" URL is included so you can click through to verify the model
# is still public and the version is current.
MODELS: list[dict[str, str]] = [
    # ===== Object detection (per-lesion bounding boxes + classes) =====
    # The proven multi-class winner from the previous spike run. v4 verified
    # active on the Roboflow Universe page.
    {
        "name": "acne-detection-6class",
        "type": "detection",
        "endpoint": "acne-detection-zukbx/4",
        "page": "https://universe.roboflow.com/acne-detection-lhbzl/acne-detection-zukbx",
        "notes": "Roboflow 3.0 Object Detection. 4433 images. 6 classes: "
                 "blackhead, dark_spot, nodule, papule, pustule, whitehead. "
                 "mAP@50=65.4, Precision=68.3, Recall=64.7.",
    },
    # AcneSCU model, version /6 verified active (Nov 2025 training).
    # Small dataset (217 images, all Han Chinese patients per source paper).
    # mAP=41.2, Precision=49.3, Recall=49.0. The in-browser test showed
    # the model emitting class "lesion" rather than the granular per-type
    # classes the dataset description advertises — we'll see if it actually
    # outputs papule/pustule/scar/etc. or just collapses to "lesion".
    {
        "name": "acnescu-detector",
        "type": "detection",
        "endpoint": "acnedetection-exshg/6",
        "page": "https://universe.roboflow.com/acnescu-0mqwx/acnedetection-exshg",
        "notes": "Roboflow 3.0 Object Detection. 217 images, multi-version "
                 "(v6 latest). mAP=41.2, P=49.3, R=49.0. Dataset advertises "
                 "10 clinically-rich classes (incl. scars) but in-browser "
                 "test shows class 'lesion' — actual emitted classes TBD.",
    },
    # NOTE: acne-vulgaris-detection/acne04-detection was evaluated and dropped.
    # Its v1 (only version) reports Recall=0.0% — the model never fires on
    # real images. mAP=20.3, Precision=33.3. Useless for our purposes despite
    # the dataset (ACNE04) being a strong citation. Not worth burning calls on.
    # ===== Classification (whole-image dominant lesion type) =====
    # Useful only as a secondary signal AFTER detection finds something —
    # it has no "no acne" output so it false-positives on clean skin.
    {
        "name": "acne-gnrti-classifier",
        "type": "classification",
        "endpoint": "acne-gnrti/1",
        "page": "https://universe.roboflow.com/eczema-dataset/acne-gnrti",
        "notes": "ViT Classification. 3627 images. 6 classes: blackheads, "
                 "cysts, nodules, papules, pustules, whiteheads. "
                 "Val accuracy 84.9%. WARNING: no 'no acne' class — always "
                 "outputs a positive label, even on clean skin.",
    },
    # ===== Single-class baseline =====
    # Kept as a sanity check / fallback total-lesion-counter. No class info
    # but high recall on training-distribution faces.
    {
        "name": "acne-gan_baseline",
        "provider": "roboflow",
        "type": "detection",
        "endpoint": "acne-gan/1",
        "page": "https://universe.roboflow.com/ance-yolo/acne-gan",
        "notes": "YOLOv8, 2055 images. Single class 'ance' — kept as baseline.",
    },
    # ===== Hugging Face — LOCAL inference (not hosted API) =====
    # naamalia23/acne-severity-classification was dropped: repo only contains
    # a README, no weights uploaded. Can't run locally either.
    #
    # Both models below run via transformers.pipeline() locally — first call
    # to each downloads weights (cached under ~/.cache/huggingface/).
    # Requires `pip install transformers torch pillow`.
    #
    # The standout: 6-level severity including "Clear Skin" — only HF
    # candidate with an explicit no-acne output (unlike acne-gnrti which
    # always picks a positive class). 968 monthly downloads, 11 spaces using
    # it, ViT architecture.
    {
        "name": "hf-skintelligent-local",
        "provider": "huggingface-local",
        "type": "classification",
        "endpoint": "imfarzanansari/skintelligent-acne",
        "page": "https://huggingface.co/imfarzanansari/skintelligent-acne",
        "notes": "ViT, 85.8M params. 6 classes: Level -1 (Clear Skin), 0 "
                 "(Occasional Spots), 1 (Mild), 2 (Moderate), 3 (Severe), "
                 "4 (Very Severe). First run downloads ~343 MB.",
    },
    # Comparison point — same task (severity classification) but smaller
    # model, narrower 4-level output without a clear-skin class.
    {
        "name": "hf-dermatologic-local",
        "provider": "huggingface-local",
        "type": "classification",
        "endpoint": "afscomercial/dermatologic",
        "page": "https://huggingface.co/afscomercial/dermatologic",
        "notes": "ResNet-50. 4 severity classes (level0..3) — no clear-skin "
                 "class. First run downloads ~94 MB.",
    },
]

# All existing Roboflow entries default to provider='roboflow' if not set.
for _m in MODELS:
    _m.setdefault("provider", "roboflow")

# Inference parameters. confidence is the minimum confidence to count a
# detection; overlap is the NMS IoU threshold. Tune if you're getting too
# many or too few detections per photo.
CONFIDENCE = 25   # %, 0-100 — lowered from 40 to catch fainter detections
OVERLAP = 30      # %, 0-100

REQUEST_TIMEOUT = 60

# Map known per-lesion class names to inflammatory / non-inflammatory.
# Extend this as you discover what classes each model actually emits.
# Includes singular/plural variants and the AcneSCU-specific names because
# different Roboflow models label the same lesion type differently
# (e.g. zukbx returns "papules", AcneSCU returns "papule", others "papule").
# Post-acne lesions (scars, dark spots, melasma) and incidental findings
# (nevus = mole) land in the unclassified bucket on purpose — they're not
# active acne and shouldn't roll up into the inflammatory severity score.
NON_INFLAMMATORY = {
    "comedone", "comedones",
    "closed_comedo", "open_comedo",   # AcneSCU
    "whitehead", "whiteheads",
    "blackhead", "blackheads",
}
INFLAMMATORY = {
    "papule", "papules",
    "pustule", "pustules",
    "nodule", "nodules",
    "cyst", "cysts",
    "papulopustular", "nodulocystic",
}
# Explicitly post-acne / non-active findings. Not used for any bucket; just
# documented here so future-you remembers why they're "unclassified".
POST_ACNE_OR_INCIDENTAL = {
    "dark_spot", "dark_spots",
    "atrophic_scar", "hypertrophic_scar",   # AcneSCU
    "melasma", "nevus", "other",            # AcneSCU
}


# ============================================================
#  Helpers
# ============================================================
def encode_image_base64(image_path: Path) -> str:
    """Read an image and return base64 as a plain ASCII string (no prefix)."""
    raw = image_path.read_bytes()
    return base64.b64encode(raw).decode("ascii")


def call_roboflow(
    endpoint: str,
    image_b64: str,
    api_key: str,
    model_type: str = "detection",
) -> tuple[int, float, dict | str]:
    """
    POST to Roboflow's hosted inference endpoint.

    Returns (http_status, elapsed_seconds, parsed_json_or_text).

    Roboflow has two separate inference hosts:
      - detect.roboflow.com   for object detection (returns bounding boxes)
      - classify.roboflow.com for classification (returns dominant class)

    Confidence/overlap params apply to detection only; classification ignores
    them silently if present, so we include them either way.

    Per Roboflow docs, the body is the raw base64 (no data-url prefix)
    sent as application/x-www-form-urlencoded.
    """
    host = "classify.roboflow.com" if model_type == "classification" else "detect.roboflow.com"
    url = (
        f"https://{host}/{endpoint}"
        f"?api_key={api_key}"
        f"&confidence={CONFIDENCE}"
        f"&overlap={OVERLAP}"
    )
    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    start = time.perf_counter()
    response = requests.post(
        url,
        data=image_b64,
        headers=headers,
        timeout=REQUEST_TIMEOUT,
    )
    elapsed = time.perf_counter() - start

    try:
        return response.status_code, elapsed, response.json()
    except ValueError:
        return response.status_code, elapsed, response.text


# Module-level cache for locally-loaded HF pipelines so we don't reload
# the model for every image. Keys are HF model IDs.
_LOCAL_HF_PIPELINES: dict[str, Any] = {}


def call_huggingface_local(
    model_id: str,
    image_path: Path,
) -> tuple[int, float, dict | str]:
    """
    Run HF inference LOCALLY using the transformers library.

    First call to a given model_id downloads weights (cached under
    ~/.cache/huggingface) and instantiates a pipeline. Subsequent calls
    re-use the cached pipeline from memory.

    Returns (synthetic_status, elapsed_seconds, normalized_payload).
    Status is 200 on success, 0 on load failure, 500 on inference failure.

    transformers + torch are heavy deps (~2 GB). They're lazy-imported
    so users who don't run any 'huggingface-local' models don't need
    them installed.
    """
    start = time.perf_counter()
    try:
        pipe = _LOCAL_HF_PIPELINES.get(model_id)
        if pipe is None:
            # Import inside the function so the script still runs for users
            # who haven't installed transformers/torch.
            try:
                from transformers import pipeline as _hf_pipeline
            except ImportError as e:
                return 0, time.perf_counter() - start, {
                    "error": (
                        "transformers/torch not installed. Run: "
                        "pip install transformers torch pillow"
                    ),
                    "exception": str(e),
                }
            pipe = _hf_pipeline("image-classification", model=model_id)
            _LOCAL_HF_PIPELINES[model_id] = pipe
    except Exception as e:
        return 0, time.perf_counter() - start, {
            "error": f"Failed to load model {model_id}",
            "exception": str(e),
        }

    try:
        raw = pipe(str(image_path))
    except Exception as e:
        return 500, time.perf_counter() - start, {
            "error": f"Inference failed on {image_path.name}",
            "exception": str(e),
        }

    elapsed = time.perf_counter() - start

    # transformers image-classification pipeline returns a list of dicts
    # like [{"label": "level1", "score": 0.94}, ...] sorted by score desc.
    # Filter by CONFIDENCE threshold and normalize to Roboflow shape.
    threshold = CONFIDENCE / 100.0
    predictions = []
    if isinstance(raw, list):
        for entry in raw:
            if not isinstance(entry, dict):
                continue
            score = float(entry.get("score", 0) or 0)
            if score < threshold:
                continue
            predictions.append({
                "class": str(entry.get("label", "")),
                "confidence": score,
            })

    return 200, elapsed, {"predictions": predictions, "_raw": raw}


def call_huggingface(
    model_id: str,
    image_bytes: bytes,
    hf_token: str,
) -> tuple[int, float, dict | str]:
    """
    POST raw image bytes to the Hugging Face Inference API.

    Endpoint: https://api-inference.huggingface.co/models/{model_id}
    Auth:     Authorization: Bearer <hf_token>
    Body:     raw image bytes (Content-Type matches the image format)

    HF returns one of three shapes:
      - On success (classification): [{"label": "...", "score": 0.94}, ...]
      - On success (detection):      [{"label": ..., "score": ..., "box": {...}}, ...]
      - On cold start:               {"error": "...", "estimated_time": N}
      - On other error:              {"error": "..."}

    Returns (http_status, elapsed_seconds, parsed_json_or_text).
    Caller normalizes the shape into Roboflow-compatible form.
    """
    url = f"https://api-inference.huggingface.co/models/{model_id}"
    headers = {
        "Authorization": f"Bearer {hf_token}",
        "Content-Type": "image/jpeg",
    }

    start = time.perf_counter()
    response = requests.post(
        url,
        data=image_bytes,
        headers=headers,
        timeout=REQUEST_TIMEOUT,
    )
    elapsed = time.perf_counter() - start

    try:
        return response.status_code, elapsed, response.json()
    except ValueError:
        return response.status_code, elapsed, response.text


def normalize_hf_response(payload: list | dict | Any) -> dict:
    """
    Convert an HF Inference API response into Roboflow-compatible shape so
    summarize_predictions() can handle both providers uniformly.

    Filters out classes below the global CONFIDENCE threshold (which is in
    percent, so divide by 100 to compare against HF's 0-1 score).
    """
    if isinstance(payload, dict):
        # Either an error dict or a single-prediction response — pass through.
        if "error" in payload:
            return {"predictions": [], "_hf_error": payload.get("error")}
        # Unknown dict shape — wrap defensively.
        return {"predictions": []}

    if not isinstance(payload, list):
        return {"predictions": []}

    threshold = CONFIDENCE / 100.0
    predictions = []
    for entry in payload:
        if not isinstance(entry, dict):
            continue
        score = float(entry.get("score", 0) or 0)
        if score < threshold:
            continue
        predictions.append({
            "class": str(entry.get("label", "")),
            "confidence": score,
            # If the model is a detector, box info lives under "box".
            **(entry.get("box") or {}),
        })
    return {"predictions": predictions}


def call_model(
    model: dict,
    image_path: Path,
    image_b64: str,
    image_bytes: bytes,
    roboflow_key: str | None,
    hf_token: str | None,
) -> tuple[int, float, dict | str]:
    """
    Dispatch to the right caller based on the model's provider, and normalize
    the response shape so downstream code is provider-agnostic.
    """
    provider = model.get("provider", "roboflow")

    if provider == "roboflow":
        if not roboflow_key:
            return 0, 0.0, {"error": "ROBOFLOW_API_KEY missing"}
        return call_roboflow(
            model["endpoint"],
            image_b64,
            roboflow_key,
            model_type=model.get("type", "detection"),
        )

    if provider == "huggingface":
        if not hf_token:
            return 0, 0.0, {"error": "HF_TOKEN missing"}
        status, elapsed, payload = call_huggingface(
            model["endpoint"],
            image_bytes,
            hf_token,
        )
        # Only normalize on a 200; otherwise pass the raw payload through so
        # the error text appears in the CSV.
        if status == 200:
            payload = normalize_hf_response(payload)
        return status, elapsed, payload

    if provider == "huggingface-local":
        # No token needed — this runs entirely on the local machine via
        # the transformers library. First call downloads weights.
        return call_huggingface_local(model["endpoint"], image_path)

    return 0, 0.0, {"error": f"Unknown provider: {provider}"}


def summarize_predictions(payload: dict | Any) -> dict[str, Any]:
    """
    Pull useful aggregate stats out of a Roboflow detection response.

    Roboflow returns:
      {
        "predictions": [
          {"x": ..., "y": ..., "width": ..., "height": ...,
           "confidence": 0.85, "class": "papule", "class_id": 0},
          ...
        ],
        "image": {"width": 1080, "height": 1080},
        "time": 0.42
      }
    """
    if not isinstance(payload, dict):
        return {
            "total_detections": "",
            "classes_seen": "",
            "class_counts": "",
            "max_confidence": "",
            "non_inflammatory_count": "",
            "inflammatory_count": "",
            "unclassified_count": "",
        }

    predictions = payload.get("predictions", []) or []
    class_counter: Counter[str] = Counter()
    max_conf = 0.0
    for p in predictions:
        cls = str(p.get("class", "")).lower()
        class_counter[cls] += 1
        conf = float(p.get("confidence", 0) or 0)
        if conf > max_conf:
            max_conf = conf

    non_inflam = sum(c for cls, c in class_counter.items() if cls in NON_INFLAMMATORY)
    inflam = sum(c for cls, c in class_counter.items() if cls in INFLAMMATORY)
    unclassified = sum(
        c for cls, c in class_counter.items()
        if cls not in NON_INFLAMMATORY and cls not in INFLAMMATORY
    )

    return {
        "total_detections": len(predictions),
        "classes_seen": ", ".join(sorted(class_counter.keys())),
        "class_counts": "; ".join(f"{k}={v}" for k, v in sorted(class_counter.items())),
        "max_confidence": round(max_conf, 3),
        "non_inflammatory_count": non_inflam,
        "inflammatory_count": inflam,
        "unclassified_count": unclassified,
    }


# ============================================================
#  Main
# ============================================================
def main() -> int:
    # Roboflow key only required if any Roboflow models are configured.
    # HF token only required if any Hugging Face models are configured.
    needs_roboflow = any(m.get("provider", "roboflow") == "roboflow" for m in MODELS)
    needs_hf = any(m.get("provider") == "huggingface" for m in MODELS)

    api_key = os.environ.get("ROBOFLOW_API_KEY")
    hf_token = os.environ.get("HF_TOKEN")

    if needs_roboflow and not api_key:
        print(
            "ERROR: ROBOFLOW_API_KEY env var is not set.\n"
            "  Get a key from https://app.roboflow.com/settings/api\n"
            "  PowerShell:   $env:ROBOFLOW_API_KEY = 'your-key-here'\n"
            "  bash / zsh:   export ROBOFLOW_API_KEY='your-key-here'",
            file=sys.stderr,
        )
        return 2

    if needs_hf and not hf_token:
        print(
            "ERROR: HF_TOKEN env var is not set.\n"
            "  Get a token from https://huggingface.co/settings/tokens\n"
            "  (a 'Read' role token is enough)\n"
            "  PowerShell:   $env:HF_TOKEN = 'hf_xxxxxxxxxxxx'\n"
            "  bash / zsh:   export HF_TOKEN='hf_xxxxxxxxxxxx'",
            file=sys.stderr,
        )
        return 2

    IMAGES_DIR.mkdir(exist_ok=True)
    RESPONSES_DIR.mkdir(exist_ok=True)

    # Discover images. Warn explicitly about files that look like they should
    # be images but were skipped because they lack a recognized extension.
    allowed_exts = (".jpg", ".jpeg", ".png")
    images: list[Path] = []
    skipped: list[Path] = []
    for p in IMAGES_DIR.iterdir():
        if p.is_dir() or p.name.startswith("."):
            continue
        if p.suffix.lower() in allowed_exts:
            images.append(p)
        else:
            skipped.append(p)
    images.sort()

    if skipped:
        print("Warning: these files were skipped (no recognized image extension):")
        for p in skipped:
            print(f"  - {p.name}  (rename with .jpg / .jpeg / .png to include)")
        print()

    if not images:
        print(
            f"No test images found in {IMAGES_DIR}/.\n"
            f"Drop 3-5 selfies in that folder and re-run.",
            file=sys.stderr,
        )
        return 1

    print(f"Running {len(images)} images x {len(MODELS)} models "
          f"(confidence={CONFIDENCE}%, overlap={OVERLAP}%)\n")

    rows: list[dict[str, Any]] = []

    for img_idx, image_path in enumerate(images, start=1):
        try:
            image_bytes = image_path.read_bytes()           # raw for HF
            image_b64 = base64.b64encode(image_bytes).decode("ascii")  # for Roboflow
        except Exception as e:
            print(f"[{img_idx}/{len(images)}] {image_path.name}: read failed — {e}")
            continue

        for model in MODELS:
            label = f"{image_path.name} -> {model['name']}"
            print(f"[{img_idx}/{len(images)}] {label} ... ", end="", flush=True)

            try:
                status, elapsed, payload = call_model(
                    model,
                    image_path,
                    image_b64,
                    image_bytes,
                    roboflow_key=api_key,
                    hf_token=hf_token,
                )
            except requests.RequestException as e:
                print(f"network error: {e}")
                rows.append({
                    "image": image_path.name,
                    "model": model["name"],
                    "status": "network_error",
                    "elapsed_s": "",
                    **summarize_predictions(None),
                    "error": str(e),
                })
                continue

            # Save the raw response under responses/<model>/<image>.json
            model_dir = RESPONSES_DIR / model["name"]
            model_dir.mkdir(exist_ok=True)
            response_path = model_dir / f"{image_path.stem}.json"
            response_path.write_text(
                json.dumps(payload, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )

            summary = summarize_predictions(payload)

            if status == 200 and isinstance(payload, dict):
                print(
                    f"OK in {elapsed:.2f}s  "
                    f"detections={summary['total_detections']}  "
                    f"classes=[{summary['classes_seen']}]  "
                    f"max_conf={summary['max_confidence']}"
                )
                rows.append({
                    "image": image_path.name,
                    "model": model["name"],
                    "status": status,
                    "elapsed_s": round(elapsed, 2),
                    **summary,
                    "error": "",
                })
            else:
                preview = (
                    json.dumps(payload, ensure_ascii=False)[:200]
                    if not isinstance(payload, str) else payload[:200]
                )
                print(f"FAIL status={status} in {elapsed:.2f}s — {preview}")
                rows.append({
                    "image": image_path.name,
                    "model": model["name"],
                    "status": status,
                    "elapsed_s": round(elapsed, 2),
                    **summary,
                    "error": preview,
                })

    # Comparison CSV — one row per (image, model).
    summary_path = RESPONSES_DIR / "_comparison.csv"
    with summary_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "image", "model", "status", "elapsed_s",
            "total_detections", "classes_seen", "class_counts", "max_confidence",
            "non_inflammatory_count", "inflammatory_count", "unclassified_count",
            "error",
        ])
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nDone. {len(images) * len(MODELS)} requests.")
    print(f"Per-(model,image) JSON saved to {RESPONSES_DIR}/<model>/")
    print(f"Side-by-side comparison: {summary_path}")
    print(
        "\nTip: open the CSV in Excel / Numbers and sort by elapsed_s, "
        "total_detections, and max_confidence to see which model is the "
        "best fit for your photos."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
