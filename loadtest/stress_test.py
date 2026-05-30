#!/usr/bin/env python3
"""
DermaTrack staged load / stress test.

Simulates the patient journey against the Supabase backend at increasing
concurrency (default 5 -> 10 -> 20 -> 30 virtual users, >=2 min per stage):

  login            POST /auth/v1/token            (once per VU per stage)
  dashboard        GET  /rest/v1/scans (recent)
  severity_view    GET  /rest/v1/scans (latest, full row incl. severity)
  history          GET  /rest/v1/scans (full list)
  upload           POST /storage/v1/object/...    (submit a facial image)
  report           GET  scans + patient_histories + treatment_plans
                        (the data a consultation report is built from)

The Roboflow/Hugging Face analysis is measured SEPARATELY at low volume
(see --analysis) so the staged load doesn't blow third-party quota.

All credentials come from environment variables (nothing is hard-coded), so
this file is safe to commit. Stdlib only -- no pip install needed.

Env vars:
  LT_BASE_URL            Supabase project URL for the staged load (no trailing /)
  LT_ANON                anon key for LT_BASE_URL
  LT_SERVICE             service_role key for LT_BASE_URL (provision + cleanup)
  LT_ANALYSIS_BASE       (optional) project URL that has the analyze-scan fn
  LT_ANALYSIS_ANON       anon key for LT_ANALYSIS_BASE
  LT_ANALYSIS_EMAIL      account on the analysis project (e.g. demo.patient@...)
  LT_ANALYSIS_PASSWORD   its password

Flags:
  --stages 5,10,20,30    VU counts per stage
  --duration 125         seconds per stage (>=120 for the thesis spec)
  --users 30             how many load-test users to provision
  --analysis 15          number of real analyze-scan calls (0 = skip)
  --no-cleanup           keep the provisioned users + uploaded objects
  --outdir loadtest/results
"""

import argparse
import csv
import json
import os
import ssl
import sys
import threading
import time
import uuid
import base64
import random
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

# A valid 1x1 JPEG (used as-is for analysis so Roboflow can decode it;
# padded with random bytes for the storage-upload op to mimic a real photo).
_JPEG_1x1 = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U"
    "HRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA"
    "/8QAFAABAAAAAAAAAAAAAAAAAAAAAv/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAUAQEA"
    "AAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8A"
    "fwH/2Q=="
)
UPLOAD_PAYLOAD = _JPEG_1x1 + os.urandom(40000)   # ~40 KB "photo"
ANALYSIS_PAYLOAD = _JPEG_1x1                      # must stay a valid JPEG

_ctx = ssl.create_default_context()
_lock = threading.Lock()
RESULTS = []          # list of (stage_label, vus, op, ms, ok, status)
UPLOADED_PATHS = []   # storage paths to clean up on LT_BASE_URL


def http(method, url, headers=None, body=None, timeout=60):
    """Return (status, bytes, elapsed_ms, err). Never raises."""
    h = dict(headers or {})
    data = body
    if isinstance(body, (dict, list)):
        data = json.dumps(body).encode()
        h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_ctx) as r:
            payload = r.read()
            return r.status, payload, (time.perf_counter() - t0) * 1000, None
    except urllib.error.HTTPError as e:
        return e.code, e.read(), (time.perf_counter() - t0) * 1000, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001
        return 0, b"", (time.perf_counter() - t0) * 1000, str(e)


def record(stage, vus, op, ms, ok, status):
    with _lock:
        RESULTS.append((stage, vus, op, ms, ok, status))


# ---------------------------------------------------------------- provisioning
def provision(base, service, n, scans_each):
    admin = {"apikey": service, "Authorization": f"Bearer {service}",
             "Content-Type": "application/json"}
    users = []
    print(f"[provision] creating {n} load-test users ...", flush=True)
    for i in range(n):
        email = f"loadtest{i}@dermatrack.demo"
        b = {"email": email, "password": "LoadTest#2026", "email_confirm": True,
             "user_metadata": {"username": f"loadtest{i}", "display_name": f"Load Test {i}"}}
        st, payload, _, err = http("POST", f"{base}/auth/v1/admin/users", admin, b)
        uid = None
        if st in (200, 201):
            uid = json.loads(payload)["id"]
        else:
            # already exists -> look up
            st2, p2, _, _ = http("GET", f"{base}/auth/v1/admin/users?per_page=200", admin)
            if st2 == 200:
                for u in json.loads(p2).get("users", []):
                    if u.get("email") == email:
                        uid = u["id"]
                        break
        if not uid:
            print(f"  ! could not create/find {email}: {st} {err}", flush=True)
            continue
        users.append({"email": email, "password": "LoadTest#2026", "id": uid})
        # seed a few scan rows so dashboard/history/report reads return data
        rows = []
        for k in range(scans_each):
            taken = (datetime.now(timezone.utc) - timedelta(days=k)).isoformat()
            rows.append({"user_id": uid, "image_path": f"{uid}/seed_{k}.jpg",
                         "taken_at": taken, "cook_grade": (k % 6) + 1,
                         "severity_label": ["Mild", "Moderate", "Severe"][k % 3],
                         "inflammatory_count": k, "non_inflammatory_count": k,
                         "post_acne_count": k % 3, "region": "full_face"})
        http("POST", f"{base}/rest/v1/scans",
             {**admin, "Prefer": "return=minimal"}, rows)
    print(f"[provision] {len(users)} users ready (each ~{scans_each} scans)", flush=True)
    return users


# ---------------------------------------------------------------- journey ops
def login(base, anon, user):
    h = {"apikey": anon, "Content-Type": "application/json"}
    st, payload, ms, err = http(
        "POST", f"{base}/auth/v1/token?grant_type=password", h,
        {"email": user["email"], "password": user["password"]})
    ok = st == 200
    token = json.loads(payload)["access_token"] if ok else None
    return token, ms, ok, (err or str(st))


def journey_once(base, anon, user, token, stage, vus):
    uid = user["id"]
    auth = {"apikey": anon, "Authorization": f"Bearer {token}"}

    def do(op, method, path, expected=200, body=None, headers=None, timeout=60):
        st, _, ms, err = http(method, f"{base}{path}", headers or auth, body, timeout)
        record(stage, vus, op, ms, st == expected, err or str(st))

    do("dashboard", "GET",
       "/rest/v1/scans?select=id,taken_at,cook_grade,severity_label&order=taken_at.desc&limit=6")
    do("severity_view", "GET",
       "/rest/v1/scans?select=*&order=taken_at.desc&limit=1")
    do("history", "GET", "/rest/v1/scans?select=*&order=taken_at.desc")

    # upload (submit facial image) into the user's own folder
    path = f"{uid}/lt_{uuid.uuid4().hex}.jpg"
    uh = {"apikey": anon, "Authorization": f"Bearer {token}",
          "Content-Type": "image/jpeg", "x-upsert": "true"}
    st, _, ms, err = http("POST", f"{base}/storage/v1/object/scan-images/{path}",
                          uh, UPLOAD_PAYLOAD)
    ok = st in (200, 201)
    record(stage, vus, "upload", ms, ok, err or str(st))
    if ok:
        with _lock:
            UPLOADED_PATHS.append(path)

    # report bundle: scans + history + plan (what a consultation report reads)
    t0 = time.perf_counter()
    ok_all = True
    last = ""
    for p in (f"/rest/v1/scans?select=*&order=taken_at.desc",
              f"/rest/v1/patient_histories?user_id=eq.{uid}&select=*",
              f"/rest/v1/treatment_plans?user_id=eq.{uid}&select=*"):
        st, _, _, err = http("GET", f"{base}{p}", auth)
        if st != 200:
            ok_all = False
            last = err or str(st)
    record(stage, vus, "report", (time.perf_counter() - t0) * 1000, ok_all, last or "200")


def worker(base, anon, user, stage, vus, deadline):
    token, ms, ok, status = login(base, anon, user)
    record(stage, vus, "login", ms, ok, status)
    if not ok:
        return
    while time.monotonic() < deadline:
        journey_once(base, anon, user, token, stage, vus)
        time.sleep(0.3)  # light think-time


def run_stage(base, anon, users, vus, duration):
    label = f"{vus}VU"
    print(f"[stage {label}] starting for {duration}s ...", flush=True)
    deadline = time.monotonic() + duration
    threads = []
    for i in range(vus):
        u = users[i % len(users)]
        t = threading.Thread(target=worker, args=(base, anon, u, label, vus, deadline))
        t.start()
        threads.append(t)
    for t in threads:
        t.join()
    n = sum(1 for r in RESULTS if r[0] == label)
    print(f"[stage {label}] done ({n} requests recorded)", flush=True)


# ---------------------------------------------------------------- analysis bench
def analysis_benchmark(abase, aanon, email, password, n):
    print(f"[analysis] benchmarking {n} real analyze-scan calls on {abase} ...", flush=True)
    h = {"apikey": aanon, "Content-Type": "application/json"}
    st, payload, _, err = http(
        "POST", f"{abase}/auth/v1/token?grant_type=password", h,
        {"email": email, "password": password})
    if st != 200:
        print(f"  ! analysis login failed: {st} {err}", flush=True)
        return []
    body = json.loads(payload)
    token, uid = body["access_token"], body["user"]["id"]
    auth = {"apikey": aanon, "Authorization": f"Bearer {token}"}
    samples = []
    bench_paths = []
    for i in range(n):
        scan_id = str(uuid.uuid4())
        path = f"{uid}/bench_{scan_id}.jpg"
        uh = {**auth, "Content-Type": "image/jpeg", "x-upsert": "true"}
        http("POST", f"{abase}/storage/v1/object/scan-images/{path}", uh, ANALYSIS_PAYLOAD)
        bench_paths.append(path)
        st, payload, ms, err = http(
            "POST", f"{abase}/functions/v1/analyze-scan", auth,
            {"scan_id": scan_id, "image_path": path, "region": "full_face"},
            timeout=120)
        det = clf = None
        if st == 200:
            try:
                meta = (json.loads(payload).get("scan", {}) or {}).get("source_metadata", {}) or {}
                det = meta.get("detection_latency_ms")
                clf = meta.get("classifier_latency_ms")
            except Exception:  # noqa: BLE001
                pass
        samples.append({"i": i, "ms": round(ms, 1), "status": st, "ok": st == 200,
                        "detection_ms": det, "classifier_ms": clf, "err": err})
        print(f"  call {i+1}/{n}: {round(ms)}ms status={st} det={det} clf={clf}", flush=True)
    # cleanup bench scans + objects (own data, via the patient token)
    http("DELETE", f"{abase}/rest/v1/scans?user_id=eq.{uid}&image_path=like.*bench_*", auth)
    http("DELETE", f"{abase}/storage/v1/object/scan-images",
         {**auth, "Content-Type": "application/json"}, {"prefixes": bench_paths})
    return samples


# ---------------------------------------------------------------- cleanup
def cleanup(base, service, users):
    admin = {"apikey": service, "Authorization": f"Bearer {service}",
             "Content-Type": "application/json"}
    print(f"[cleanup] removing {len(UPLOADED_PATHS)} uploaded objects ...", flush=True)
    for i in range(0, len(UPLOADED_PATHS), 100):
        batch = UPLOADED_PATHS[i:i + 100]
        http("DELETE", f"{base}/storage/v1/object/scan-images", admin, {"prefixes": batch})
    print(f"[cleanup] deleting {len(users)} load-test users (cascades scans) ...", flush=True)
    for u in users:
        http("DELETE", f"{base}/auth/v1/admin/users/{u['id']}", admin)
    print("[cleanup] done", flush=True)


# ---------------------------------------------------------------- metrics
def pctl(vals, p):
    if not vals:
        return 0.0
    s = sorted(vals)
    k = max(0, min(len(s) - 1, int(round((p / 100) * (len(s) - 1)))))
    return s[k]


def aggregate(stages, duration):
    """Return list of per-(stage,op) and per-stage-overall metric dicts."""
    out = []
    ops = ["login", "dashboard", "severity_view", "history", "upload", "report"]
    for vus in stages:
        label = f"{vus}VU"
        groups = {op: [] for op in ops}
        overall = []
        for (lbl, _v, op, ms, ok, _st) in RESULTS:
            if lbl != label:
                continue
            groups.setdefault(op, []).append((ms, ok))
            overall.append((ms, ok))
        for op in ops + (["OVERALL"] if True else []):
            data = overall if op == "OVERALL" else groups.get(op, [])
            if not data:
                continue
            lat = [m for m, _ in data]
            total = len(data)
            success = sum(1 for _, ok in data if ok)
            failed = total - success
            out.append({
                "stage": label, "vus": vus, "operation": op,
                "total_requests": total, "successful": success, "failed": failed,
                "error_rate_pct": round(100 * failed / total, 2) if total else 0,
                "avg_ms": round(sum(lat) / len(lat), 1),
                "p95_ms": round(pctl(lat, 95), 1),
                "max_ms": round(max(lat), 1),
                "throughput_rps": round(total / duration, 2),
            })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stages", default="5,10,20,30")
    ap.add_argument("--duration", type=int, default=125)
    ap.add_argument("--users", type=int, default=30)
    ap.add_argument("--scans-each", type=int, default=5)
    ap.add_argument("--analysis", type=int, default=15)
    ap.add_argument("--no-cleanup", action="store_true")
    ap.add_argument("--outdir", default=os.path.join(os.path.dirname(__file__), "results"))
    args = ap.parse_args()

    base = os.environ["LT_BASE_URL"].rstrip("/")
    anon = os.environ["LT_ANON"]
    service = os.environ["LT_SERVICE"]
    stages = [int(x) for x in args.stages.split(",")]
    os.makedirs(args.outdir, exist_ok=True)

    started = datetime.now(timezone.utc).isoformat()
    print(f"=== DermaTrack load test @ {started} ===", flush=True)
    print(f"target={base} stages={stages} duration={args.duration}s", flush=True)

    users = provision(base, service, max(args.users, max(stages)), args.scans_each)
    if not users:
        print("FATAL: no users provisioned", file=sys.stderr)
        sys.exit(1)

    for vus in stages:
        run_stage(base, anon, users, vus, args.duration)
        time.sleep(5)  # brief settle between stages

    analysis = []
    if args.analysis > 0 and os.environ.get("LT_ANALYSIS_BASE"):
        analysis = analysis_benchmark(
            os.environ["LT_ANALYSIS_BASE"].rstrip("/"),
            os.environ["LT_ANALYSIS_ANON"],
            os.environ["LT_ANALYSIS_EMAIL"],
            os.environ["LT_ANALYSIS_PASSWORD"], args.analysis)

    metrics = aggregate(stages, args.duration)

    # ---- export ----
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_path = os.path.join(args.outdir, f"loadtest_{stamp}.csv")
    json_path = os.path.join(args.outdir, f"loadtest_{stamp}.json")
    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(metrics[0].keys()))
        w.writeheader()
        w.writerows(metrics)
    ana_ok = [s["ms"] for s in analysis if s["ok"]]
    ana_summary = {
        "calls": len(analysis), "successful": len(ana_ok),
        "avg_ms": round(sum(ana_ok) / len(ana_ok), 1) if ana_ok else None,
        "p95_ms": round(pctl(ana_ok, 95), 1) if ana_ok else None,
        "max_ms": round(max(ana_ok), 1) if ana_ok else None,
        "min_ms": round(min(ana_ok), 1) if ana_ok else None,
        "samples": analysis,
    }
    with open(json_path, "w") as f:
        json.dump({"started": started, "target": base, "stages": stages,
                   "duration_s": args.duration, "metrics": metrics,
                   "analysis_benchmark": ana_summary}, f, indent=2)

    # ---- summary table ----
    print("\n================ SUMMARY (per stage, OVERALL) ================", flush=True)
    hdr = f"{'Stage':>6} {'Total':>7} {'OK':>6} {'Fail':>5} {'Err%':>6} {'Avg ms':>8} {'p95 ms':>8} {'Max ms':>9} {'req/s':>7}"
    print(hdr)
    print("-" * len(hdr))
    for m in metrics:
        if m["operation"] != "OVERALL":
            continue
        print(f"{m['stage']:>6} {m['total_requests']:>7} {m['successful']:>6} "
              f"{m['failed']:>5} {m['error_rate_pct']:>6} {m['avg_ms']:>8} "
              f"{m['p95_ms']:>8} {m['max_ms']:>9} {m['throughput_rps']:>7}")

    print("\n--- per-operation p95 (ms) by stage (spot the bottleneck) ---", flush=True)
    ops = ["login", "dashboard", "severity_view", "history", "upload", "report"]
    print(f"{'op':>14} " + " ".join(f"{f'{v}VU':>8}" for v in stages))
    for op in ops:
        row = []
        for vus in stages:
            m = next((x for x in metrics if x["stage"] == f"{vus}VU" and x["operation"] == op), None)
            row.append(f"{m['p95_ms']:>8}" if m else f"{'-':>8}")
        print(f"{op:>14} " + " ".join(row))

    if analysis:
        print(f"\n--- Roboflow/HF analysis benchmark ({ana_summary['successful']}/{ana_summary['calls']} ok) ---")
        print(f"  avg={ana_summary['avg_ms']}ms  p95={ana_summary['p95_ms']}ms  "
              f"min={ana_summary['min_ms']}ms  max={ana_summary['max_ms']}ms")

    if not args.no_cleanup:
        cleanup(base, service, users)

    print(f"\nCSV : {csv_path}")
    print(f"JSON: {json_path}")
    print("=== done ===", flush=True)


if __name__ == "__main__":
    main()
