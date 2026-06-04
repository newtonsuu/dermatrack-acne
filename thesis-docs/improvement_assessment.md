# DermaTrack — Whole-App Assessment & Recommended Improvements

> Grounded in the current codebase + this session's live verification. Prioritized P0 (do before any real-world/pilot use) → P2 (scale / nice-to-have).

## Strengths (what's solid today)
- **RBAC + RLS verified live:** per-user isolation, IDOR-resistant, consent-gated doctor access, time-limited audited break-glass, role-based routing. Privilege-escalation hole found **and fixed**.
- **Clear product framing:** monitoring (not diagnosis), Cook→Mild/Moderate/Severe with guidance + disclaimer; per-region + overall summary.
- **Real features end-to-end:** scans (2-model edge function), notifications center, settings, prescriptions, chat with edit/unsend + admin moderation, admin console, reminders.
- **Engineering hygiene:** CI release pipeline, `flutter analyze` clean, 24 passing tests, web + APK builds, idempotent SQL migrations + consolidated `full_schema.sql`.

## P0 — Security & privacy (health data)
1. **Restrict `profiles` SELECT** (currently `USING (true)` → any user can enumerate all usernames/roles). Scope to own row + (doctor) consenting patients + (admin) all.
2. **Audit doctor read access**, not just admin/break-glass/privacy actions — completes the access trail for PHI.
3. **Release signing key** — the APK is debug-signed (`build.gradle.kts` TODO); add a proper keystore before distribution.
4. **PHI governance for ML egress** — scan images leave to Roboflow/Hugging Face; add a data-processing agreement and/or de-identification, and a privacy-policy clause. Consider field-level encryption for `patient_histories`.
5. **RLS regression tests in CI** (e.g., pgTAP or scripted probes like this session's) so a future change can't silently reopen the escalation hole.

## P1 — Testing & reliability
6. **Raise unit coverage (now ~5%)** — add service tests with a mocked Supabase client, golden tests for key screens, and widget tests for admin/break-glass/messaging.
7. **Automated integration/E2E** with the `integration_test` package for the device-only flows (camera, notifications, reminder) — currently only manually verifiable.
8. **Gate releases in CI** — run `flutter test` + `flutter analyze` in the workflow before building the APK (today it only builds).
9. **Crash reporting & logging** — add Sentry/Crashlytics + structured logs to catch field issues (e.g., the reminder crash would have surfaced sooner).

## P1 — Architecture & data model
10. **Per-doctor consent / assignment** — `shared_with_doctor` is a single boolean, so *every* doctor sees *all* consenting patients. For multiple dermatologists, add a doctor↔patient link table with per-doctor consent.
11. **Server-driven notifications (FCM + a `notifications` table)** — current notifications are client-synthesized and local-only, so doctor→patient alerts don't arrive when the app is closed.
12. **Clean up vestigial code** — `kDoctorDemoEmails` allowlist is now unused (role-based); remove to avoid confusion.
13. **Messaging polish** — unread counts / read receipts, and **pagination** (threads currently load in full).
14. **"Every 2 days" reminder** is approximate (no native repeat) — implement reschedule-on-fire or document the limitation.

## P2 — Product, UX & scale
15. **Admin content modules** (FAQ / educational content / notification templates / support tickets) are specced but **not implemented** — build with backing tables, or drop from scope.
16. **Accessibility & localization** — contrast/large-text pass (we fixed overflow via `Wrap`), screen-reader labels, and English/Filipino localization for the target users.
17. **Model evaluation for the thesis** — document Roboflow+HF accuracy/agreement metrics and an offline fallback; this strengthens Chapter 4.
18. **Data portability** — export currently outputs JSON only (no images); consider a full export incl. images, and a documented retention/deletion policy.
19. **State management at scale** — `ChangeNotifier` singletons are fine for a thesis; Riverpod/Bloc + DI would improve testability if the app grows.
20. **Ops** — enable Supabase PITR/backups; add a seed/reset script for reproducible demos; keep migrations and `full_schema.sql` in sync (consider regenerating rather than appending).

## Suggested sequencing
**Before defense/pilot:** P0 #1–3 (quick, high-impact) + #5. **Next iteration:** P1 testing (#6–8) + per-doctor consent (#10) + server notifications (#11). **Later:** P2 polish + scale items.
