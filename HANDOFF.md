# HANDOFF.md

> Last updated: 2026-06-03. Project root: `C:\Users\jericho.james.guanga\projects\dermatrack-acne`
> GitHub: `newtonsuu/dermatrack-acne` (origin). Owner/author: AJ (Mapúa IT thesis).

## Goal
**DermaTrack** — a Flutter + Supabase mobile app for **longitudinal acne severity monitoring and self-care tracking** (explicitly *non-diagnostic*; it is decision-support, not a medical device). It is a thesis project.

The app has two sides:
- **Patient side** — daily guided scan (camera), AI severity analysis, history/progression, calendar, reminders, prescriptions view, chat with doctor.
- **Dermatologist (doctor) side** — patient search/list, scan comparison/progression, treatment plans, PDF report export, prescriptions (with image attachments), chat.

Backend is a **fresh Supabase project**: `mqnoexkihwfmebalfobo` (`https://mqnoexkihwfmebalfobo.supabase.co`). Scan analysis runs through a Supabase **Edge Function** (`analyze-scan`) that calls **Roboflow** (`acne-detection-zukbx/4`) + a **Hugging Face Gradio Space** (`imfarzanansari/skintelligent-acne`), graded on the **Cook 0–8** severity scale.

The current thesis sub-tasks (most recent first): functional testing (FT-01..FT-20), stress testing, penetration testing, and remediating findings — all with **strict no-fabrication discipline** and **credential safety** (no secrets committed).

## Current Progress
Completed this session and earlier:
- ✅ Repo created (`newtonsuu/dermatrack-acne`), code reviewed.
- ✅ **Dermatologist side** built: patient list/search/filter, scan compare/progression, treatment plans, PDF report export.
- ✅ **Patient features**: local notifications (noon reminder + 9pm/21:00 deadline countdown), prescriptions screen, patient↔doctor chat.
- ✅ **Doctor features**: prescriptions with image attachments, chat.
- ✅ Migrated backend to fresh Supabase project `mqnoexkihwfmebalfobo`; ran `supabase/full_schema.sql`; created demo accounts + seeded sample data.
- ✅ Working two-model scan analysis via `analyze-scan` edge function (Roboflow + HF), with timeouts/AbortController so it can't hang.
- ✅ Fixed: startup "stuck on DT logo", slow loads, Mapúa email registration rejection, scan 404/500/hang.
- ✅ CI/CD: GitHub Actions builds split-per-ABI release APKs on `v*` tags → GitHub Release.
- ✅ **Stress test** (staged 5/10/20/30 VUs) — script + results committed.
- ✅ **Penetration / security assessment** — script + results committed.
- ✅ **Functional test** (FT-01..FT-20) — harness + results committed.
- ✅ **FT-11 fix (most recent code change)**: added non-diagnostic disclaimer banner to the patient scan **result screen**. Committed (`da092bb`), tagged **v0.2.4**.

**IN PROGRESS right now:** APK build for **v0.2.4** — GitHub Actions run **26885695433** was `in_progress` at last check (~6m36s elapsed; typical build ≈ 7–8 min). The latest *published* release is still **v0.2.3**.

## Files Reviewed
- `app/pubspec.yaml` — version `0.2.4+6`. Deps: supabase_flutter, image_picker, camera, google_mlkit_face_detection, flutter_local_notifications + timezone, pdf + printing, fl_chart, shared_preferences, uuid. Dev: flutter_launcher_icons, flutter_native_splash (teal `#1F8A8A`, "DT" logo).
- `app/lib/screens/login_screen.dart` — email regex fix present: `r'^[\w.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$'` (line 146); routes to register/forgot-password.
- `app/lib/screens/register_screen.dart` — same regex fix (line 165); username ≥3 chars; password strength checklist; maps `AuthField` server errors per field.
- `app/lib/screens/scan_detail_screen.dart` — large; contains `_SeverityBadge` and the new `_DisclaimerBanner` (FT-11). Disclaimer text confirmed present.
- `app/lib/pubspec.yaml` version history comments (0.2.0 = doctor mode + branded icon/splash).

### Project structure (key dirs)
```
ROOT: .github/ app/ loadtest/ qa/ security/ spike/ supabase/
      README.md  SETUP_GUIDE_FOR_CO_AUTHOR.md  .gitignore  HANDOFF.md
app/lib/screens/        calendar, camera, change_password, chat, dashboard,
                        edit_profile, forgot_password, gallery, home_shell,
                        login, prescriptions, profile, register,
                        scan_detail, settings, welcome
app/lib/screens/doctor/ doctor_patient_detail, doctor_patient_list,
                        doctor_prescriptions, doctor_scan_compare,
                        doctor_scan_detail, doctor_shell
app/lib/screens/patient_history/  , app/lib/screens/scan_session/
app/lib/services/       auth, chat, doctor, doctor_report, face_detection,
                        patient_history, prescription, profile,
                        region_alignment_evaluator, scan_reminder, scan
supabase/migrations/    0001_init … 0009_messages
supabase/full_schema.sql, supabase/functions/analyze-scan/index.ts
loadtest/ (stress_test.py + results/)   qa/ (functional_test.py + results/)
security/ (pentest.py + results/)
```

## Files Modified (this session, summarized)
- `app/lib/screens/scan_detail_screen.dart` — **added `_DisclaimerBanner`** (info icon + monitoring-only text) inserted after `_SeverityBadge` on the result screen. Text: *"For monitoring support only — not a medical diagnosis. DermaTrack helps you track changes over time; consult a licensed dermatologist for diagnosis and treatment."* (FT-11 fix.)
- `app/lib/screens/login_screen.dart` + `register_screen.dart` — email regex → `r'^[\w.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$'` (accepts `mymail.mapua.edu.ph`).
- `app/lib/services/auth_service.dart` — `kDoctorDemoEmails` set; `_isValidEmail` regex fix; `_mapAuthException` maps "user already registered" → "An account with this email already exists."
- `app/lib/main.dart` — moved `ScanReminderService.instance.initialize()` to AFTER `runApp()` (fire-and-forget `.catchError`); bounded `ThemeController.init().timeout(3s)` and `Supabase.initialize(...).timeout(10s)` (fixes stuck-on-splash).
- `app/lib/services/scan_service.dart` — 45s timeout on `analyze-scan` invoke; parallelized signed URLs via `Future.wait`.
- `app/lib/services/doctor_service.dart` — demo-email support; treatment-plan load/upsert; parallelized `loadPatients` + signed URLs.
- `app/lib/services/scan_reminder_service.dart` — noon (12:00) + evening deadline (21:00) local notifications; `uiLocalNotificationDateInterpretation` fix.
- New feature files: `app/lib/models/{prescription,message,treatment_plan}.dart`; `app/lib/services/{prescription_service,chat_service,doctor_report_service}.dart`; `app/lib/screens/{chat_screen,prescriptions_screen}.dart`; `app/lib/screens/doctor/{doctor_prescriptions_screen,doctor_scan_compare_screen}.dart`.
- `supabase/migrations/0006_treatment_plans.sql`, `0007_doctor_demo_emails.sql`, `0008_prescriptions.sql`, `0009_messages.sql`; `supabase/full_schema.sql` (UTF-8 no-BOM, `ALTER TABLE profiles ADD COLUMN IF NOT EXISTS` for pre-existing profiles, realtime publication guard).
- `supabase/functions/analyze-scan/index.ts` — 20s `AbortController` around HF Gradio fetch + SSE loop.
- `app/android/app/build.gradle.kts` — core library desugaring enabled (`desugar_jdk_libs:2.1.4`).
- `.github/workflows/release-apk.yml` — split-per-ABI release APK build on `v*` tags → GitHub Release.
- `app/dart-define.json` — **gitignored**; holds `SUPABASE_URL` + anon key.
- `loadtest/stress_test.py`, `security/pentest.py`, `qa/functional_test.py` — all read creds from env (commit-safe).

## Commands Run (recent / important)
- `git log --oneline` / `git tag` — confirm history; latest commit `da092bb` (FT-11 disclaimer), tag `v0.2.4`.
  - Result: ✅ HEAD = `da092bb`, tag `v0.2.4` pushed.
- `gh run list` — check APK build status.
  - Result: ⏳ run **26885695433** (v0.2.4) `in_progress`; v0.2.3/2.2/2.1/2.0 all `success`.
- `gh release list` — Result: latest published release is **v0.2.3** (v0.2.4 publishes when build finishes).
- Flutter web preview served on **http://localhost:8099** (HTTP 200) — running in background for visual/screenshot verification of the disclaimer.
- (Earlier) Supabase CLI edge-function deploy + secrets (`ROBOFLOW_API_KEY`); ran `full_schema.sql` in SQL editor; seeded demo data.

## Errors Encountered
- **Stuck on DT splash** → main.dart initialized notifications before `runApp` and awaited unbounded init. **Fixed** (moved after runApp, added timeouts). Status: ✅ resolved (v0.2.2).
- **Mapúa email rejected at registration** → email-confirmation on + single-label regex. **Fixed** (confirmation off + regex in 3 files). Status: ✅ resolved (v0.2.3).
- **Scan 404** → edge function not deployed. **Fixed** (deployed). **Scan 500** → missing `ROBOFLOW_API_KEY`. **Fixed** (secret set). **8-min hang/502** → HF Space cold-start/no timeout. **Fixed** (AbortController). Status: ✅ resolved.
- **FT-08 502 in functional test** → test used a **1×1 JPEG** (rejected by Roboflow) against a sleeping HF Space — a **test-data defect, not a system bug**. **Fixed** by switching test to a 640×640 sample image (`FT_IMAGE`). FT-12/13/15 were cascade artifacts of this. Status: ✅ resolved.
- **FT-11 "Failed"** → no non-diagnostic disclaimer on result screen. **Fixed** (this session, disclaimer banner). Status: ✅ resolved in code; ⏳ verify on built APK / web.
- **full_schema.sql `column "username" does not exist`** → pre-existing template profiles table. **Fixed** with `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`. Status: ✅ resolved.
- **PowerShell quirks** — here-string commit messages mangled (used `git commit -F .git/COMMIT_MSG.tmp`); jq ternary/Cyrillic-char typos in pasted keys. Status: ✅ worked around.
- **Open security finding (not yet remediated): profile enumeration** via RLS on `profiles`. An RLS-tightening patch was proposed but **not applied** (user has not requested it). Status: ⚠️ open / optional.

## Working Decisions (treat as final unless contradicted)
- Active Supabase project = **`mqnoexkihwfmebalfobo`** ONLY. (A barangay app project with `role`/`barangay_id` was pasted by mistake earlier — **do NOT use it.**)
- App is **non-diagnostic / monitoring support** — all analysis output must be framed that way (FT-11 disclaimer enforces this).
- Login model: single shared login; **doctor accounts are identified by `kDoctorDemoEmails`** (e.g. `doctor@dermatrack.demo`, `dr.demo@dermatrack.demo`) which route to the doctor shell; everyone else is a patient.
- Secrets policy: **never commit credentials.** Test scripts read from env; `app/dart-define.json` is gitignored; screenshots/logs must blur emails/keys/tokens.
- Severity scale = **Cook 0–8**. Two-model pipeline (Roboflow + HF) via `analyze-scan`.
- Notifications are **local** (flutter_local_notifications) — noon reminder + 21:00 deadline. NOT FCM push.
- Releases are cut by **pushing a `vX.Y.Z` git tag**; CI builds split-per-ABI APKs and publishes the GitHub Release. Bump `pubspec.yaml` `version:` (e.g. `0.2.4+6`) before tagging.
- No-fabrication rule for all thesis testing: report only real, observed results; clearly label test-data artifacts vs. real system defects.

## Things to Avoid
- ❌ Don't delete `.git` / run destructive `Remove-Item` on the repo (user declined before — keep history, repoint origin if needed).
- ❌ Don't paste multi-line commit messages via PowerShell double-quoted here-strings — they get mangled. Use a temp file + `git commit -F`.
- ❌ Don't await unbounded async in `main.dart` before `runApp()` — caused the splash hang.
- ❌ Don't use the wrong Supabase project (`tgtcjmxt` / the barangay project). Only `mqnoexkihwfmebalfobo`.
- ❌ Don't use 1×1 / placeholder images for scan tests — Roboflow rejects them; use a real ≥640×640 sample.
- ❌ Don't commit anon/service keys, access tokens, or real user emails. Blur in any evidence.
- ❌ Don't claim a release link works before the GitHub Actions build shows `success`.

## Next Steps (numbered plan)
1. **Confirm the v0.2.4 APK build finished** — `gh run list --limit 3` (look for run `26885695433` = `completed/success`) and `gh release view v0.2.4`. Only then share the link:
   `https://github.com/newtonsuu/dermatrack-acne/releases/download/v0.2.4/app-arm64-v8a-release.apk`
   (also `app-armeabi-v7a-release.apk` / `app-x86_64-release.apk`).
2. **Verify FT-11 fix** — on web (http://localhost:8099) or the v0.2.4 APK: log in as patient, open any scan → confirm the disclaimer banner shows under the severity badge. Capture a screenshot for Chapter 4 evidence (blur any private info).
3. **Update functional-test results** — FT-11 now **Passed**. Tally: 11 Passed / 7 Passed-with-Notes / 1 Not-Executed (FT-05 camera, device-only) / 0 Failed. Refresh any thesis table + the final statement to match.
4. **(Optional, ask first)** Add the same disclaimer to the **doctor** scan detail screen (`doctor_scan_detail_screen.dart`) and/or the session-complete screen for consistency.
5. **(Optional, ask first)** Remediate the open **profile-enumeration** RLS finding from the pentest.
6. **(If requested)** Help capture remaining UI screenshots for the "Passed with Notes" functional cases.

## Validation Checklist
- [ ] `gh run list` shows run 26885695433 (v0.2.4) = `completed / success`.
- [ ] `gh release view v0.2.4` lists the 3 ABI APK assets.
- [ ] Direct APK download URL returns the file (HTTP 200), installs on an Android phone.
- [ ] On the running app: patient scan result screen shows the **non-diagnostic disclaimer** (FT-11).
- [ ] Registration succeeds with a `@mymail.mapua.edu.ph` email (no "valid email" rejection).
- [ ] Registering an existing email shows "An account with this email already exists."
- [ ] A fresh scan completes without 404/500/hang (analysis returns a Cook 0–8 severity).
- [ ] App launches past the DT splash within a few seconds (no hang).
- [ ] No secrets present in any committed file (`git grep` for anon/service keys returns nothing).

## Prompt for Next Session
> Read `HANDOFF.md` in the project root (`C:\Users\jericho.james.guanga\projects\dermatrack-acne`) and continue from **Next Steps**. First, run `gh run list --limit 3` and `gh release view v0.2.4` to confirm the v0.2.4 APK build (run 26885695433) finished successfully; if so, give me the arm64 release download link. Then help me verify the FT-11 non-diagnostic disclaimer on the patient scan result screen and update my functional-test tally (FT-11 now passes → 11 passed / 7 with notes / 1 not-executed / 0 failed). Follow the Working Decisions and Things to Avoid sections strictly — especially: only use Supabase project `mqnoexkihwfmebalfobo`, never commit secrets, and don't fabricate any test results.
