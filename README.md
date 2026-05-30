# DermaTrack — Acne edition

A mobile companion for **longitudinal acne severity monitoring**. Patients
take guided face scans; an AI pipeline grades severity on the Cook 0–8 scale
and tracks lesion counts over time; their dermatologist reviews progress and
leaves guidance — all in one app.

This repo (`newtonsuu/dermatrack-acne`) is an independent working copy used to
develop **acne-focused changes and the dermatologist (doctor) side** of the
system. It was branched from the original DermaTrack project.

> **Heads-up:** this app needs the Flutter + Android toolchain and private
> Supabase credentials to build and run. See [Setup](#setup) — and the
> detailed [`SETUP_GUIDE_FOR_CO_AUTHOR.md`](SETUP_GUIDE_FOR_CO_AUTHOR.md) for a
> full from-scratch walkthrough (~2–3 hours, ~20 GB).

---

## Repository layout

```
.
├── app/          Flutter client (Android / iOS / web)
│   └── lib/
│       ├── models/        Scan, PatientHistory, TreatmentPlan, …
│       ├── screens/       patient screens + screens/doctor/ (dermatologist side)
│       ├── services/      AuthService, ScanService, DoctorService, DoctorReportService, …
│       └── widgets/        LesionOverlay, SeverityTrendChart, SkinSummaryCard, …
├── spike/        Python spike that exercises the acne-detection API (code only)
└── supabase/
    ├── functions/analyze-scan/   Edge function: detection + classifier → Cook grade
    └── migrations/               SQL schema (0001 … 0006), apply in order
```

## How it works (high level)

- **Auth & routing** — everyone signs in through the same login screen.
  [`main.dart`](app/lib/main.dart) routes the session: the **demo dermatologist
  account** (matched by email in `is_demo_doctor()`) lands on the **doctor
  view**; **every other account** gets the **patient experience**.
- **Scan → grade** — a scan image is sent to the `analyze-scan` Supabase edge
  function, which runs a Roboflow detection model (+ a HuggingFace classifier),
  derives a Cook 0–8 grade and lesion-bucket counts, and stores the result.
- **Access control** — Postgres **Row-Level Security** is the real gate
  throughout. A patient only sees their own data; the doctor only sees patients
  who toggled **“Share with my dermatologist.”**

## Dermatologist (doctor) side

The doctor account opens to a read-only-plus-annotation workflow:

- **Patient list** — consenting patients with last-scan summary, **search**,
  **sort** (Recent / Severity / Name), and a **“Needs review”** filter
  (patients whose latest scan has no doctor note yet).
- **Patient detail** — medical-history snapshot, skin summary, 30-day severity
  trend, and the full scan history.
- **Treatment plan** — a per-patient, doctor-authored plan (regimen + follow-up)
  the patient can read. Backed by `treatment_plans`
  ([migration 0006](supabase/migrations/0006_treatment_plans.sql)).
- **Scan comparison** — pick two scans (e.g. baseline vs latest) and see the
  Cook-grade and lesion-count deltas side by side.
- **PDF report export** — generate a shareable patient report (identity, plan,
  scan stats, recent-scans table, latest image, history) via `DoctorReportService`.
- **Per-scan doctor notes** — clinical note on any individual scan, visible to
  the patient.

> The doctor account is **demo-grade**: `is_demo_doctor()` trusts a hardcoded
> email. Replace it with a real role/claim before any non-thesis deployment.

---

## Setup

Full step-by-step (fresh Windows machine) lives in
[`SETUP_GUIDE_FOR_CO_AUTHOR.md`](SETUP_GUIDE_FOR_CO_AUTHOR.md). Short version:

1. **Install the toolchain** — Git, JDK 17, the **Flutter SDK** (add
   `…\flutter\bin` to PATH), and **Android Studio** (for the Android SDK +
   platform-tools). Then accept licenses:
   ```
   flutter doctor --android-licenses
   flutter doctor          # should be all green
   ```
2. **Get dependencies:**
   ```
   cd app
   flutter pub get
   ```
3. **Provide Supabase credentials** (private — never commit them). You pass
   them to every run/build via `--dart-define`:
   - `SUPABASE_URL`  — e.g. `https://xxxx.supabase.co`
   - `SUPABASE_ANON_KEY` — the long `eyJ…` anon key (safe to embed in the app;
     RLS enforces access)
4. **Apply database migrations** (Supabase CLI) so the schema — including the
   new `treatment_plans` table — exists:
   ```
   supabase db push      # or run supabase/migrations/*.sql in order
   ```

## Run

```powershell
cd app

# On a connected Android phone / emulator:
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=eyJ...your-anon-key...

# Quick UI preview in a browser (camera / notifications are mobile-only and
# degrade gracefully on web):
flutter run -d chrome `
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Build a release APK (for phone testing)

```powershell
cd app
flutter build apk --release --split-per-abi `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

Output (install the `arm64-v8a` one on essentially any modern phone):

```
app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

> By default this is **debug-signed**, which is fine for sideloaded testing.
> For a Play Store / properly signed build you need the release **keystore**
> and a signing config in `app/android/app/build.gradle.kts`.

## Tips

- A long first Gradle build (~1 GB of tooling) is normal; later builds are fast.
- “App not installed — package conflicts”: uninstall the old DermaTrack first
  (different signing key).
- More troubleshooting in [`SETUP_GUIDE_FOR_CO_AUTHOR.md`](SETUP_GUIDE_FOR_CO_AUTHOR.md#common-issues-and-fixes).
