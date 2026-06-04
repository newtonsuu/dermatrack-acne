# DermaTrack — Security Testing (OWASP-aligned)

> **See also `security_assessment.md`** for the full executed actor×operation×resource vulnerability matrix. Two access-control findings surfaced during testing — a self-service **privilege-escalation** hole and **UI-only account deactivation** — were both **fixed (migrations 0013/0014) and re-verified**; the `profiles` enumeration weakness was also closed (0014).

> All findings are derived from the actual codebase (`app/lib/**`, `supabase/full_schema.sql`, migrations 0001–0011, `supabase/functions/analyze-scan`) and from **live, read-only tests** run against the project's Supabase backend (`mqnoexkihwfmebalfobo`) during this assessment. No destructive actions were performed. Secret values are never printed.

## Environment & method
- **Target:** DermaTrack release build (v0.5.1) + Supabase backend.
- **Method:** code review of authentication, RLS policies, storage, and the edge function; plus **black-box live probes** authenticating as the demo accounts (`patient`, `doctor`, `admin`) and exercising the REST/RPC API directly to confirm what the server actually permits.
- **Authorization model under test:** PostgreSQL Row-Level Security (RLS) with role-based helper functions `is_demo_doctor()` (role=doctor), `is_admin()` (role=admin), `has_active_break_glass()`, and consent flag `profiles.shared_with_doctor`.

---

## A01 — Broken Access Control  *(tested live)*

**What was checked:** role separation (can a patient reach doctor/admin data?), IDOR (can a patient read another user's records by spoofing an id?), admin-only tables, and consent-gating.

**How:** signed in as `demo.patient@dermatrack.demo` and queried the REST API directly (raw HTTP, `Prefer: count=exact`).

| Probe (as patient) | Result (server) | Interpretation |
|---|---|---|
| `GET /scans` (own) | **15 rows** | reads only own scans |
| `GET /scans?user_id=eq.<adminId>` (IDOR attempt) | **0 rows** | **cannot** read another user's scans even when filtering by their id |
| `GET /patient_histories` | **1 row (own)** | history scoped to owner |
| `GET /break_glass_sessions` | **0 rows** | admin-only table blocked |
| `GET /audit_log` | **0 rows** | admin-only read blocked |
| RPC `is_admin()` / `is_demo_doctor()` (per role) | admin→`true`/`false`, doctor→`false`/`true`, patient→`false`/`false` | role gates resolve correctly |

**Findings:**
- **IDOR & vertical access control: PASS.** RLS scopes every PHI table to `auth.uid()`; a patient cannot read another patient's scans/history, nor any admin-only table. Doctor access is additionally consent-gated (`shared_with_doctor`).
- **Profile enumeration: NEEDS REVIEW (Low–Medium).** `GET /profiles` returned **all 5 profiles** (id, username, role) to a patient. The `profiles` SELECT policy is `USING (true)` (any authenticated user reads all profiles). No clinical PHI is exposed, but usernames and **who the doctors/admins are** become enumerable. *Recommendation:* restrict `profiles` SELECT to own row + (doctor) consenting patients + (admin) all.

## A07 — Identification & Authentication Failures

- **Password hashing:** delegated to **Supabase Auth (GoTrue)**, which stores bcrypt hashes server-side; the app never handles raw hashes. **PASS (managed).**
- **Password policy:** client-side complexity enforced in registration (`unmetPasswordRequirements`: upper/lower/digit/length) + Supabase minimum length server-side. **PASS (note: complexity is client-side; server enforces only length).**
- **Brute-force / lockout:** client-side lockout after **5 failed attempts → 60 s** (`auth_service.dart`), plus Supabase's own server-side auth rate limiting. **PASS (note: client lockout is defense-in-depth; the server limit is the real control).**
- **Session/token handling:** Supabase JWT (access + refresh); **idle session timeout 15 min** (`session_timeout_service.dart`); `roleResolved` gate prevents privilege-flash. **PASS.**
- **Logout:** `AuthService.signOut()` clears the session and routes to the welcome screen. **PASS.**
- **Password reset:** Supabase email reset; the app sends silently (no account-existence disclosure → no user enumeration via reset). **PASS.**

## A02 — Cryptographic Failures / Sensitive Data Exposure

- **In transit:** all API/Storage/Realtime traffic is **HTTPS/WSS** (Supabase enforced). **PASS.**
- **At rest:** PHI stored in Supabase Postgres + private Storage buckets; encryption-at-rest is provided by Supabase infrastructure. Application-level field encryption is **not** implemented. **PASS (infra) / note for production.**
- **Images:** `scan-images`, `prescription-images`, `profile-pictures` buckets are **private**; access is via **short-lived signed URLs** only. **PASS.**
- **Secrets in repo (checked):** `app/dart-define.json` is **gitignored**; the Supabase **access token is not present in any tracked file**; the string "service_role" appears only as a *warning comment* in `main.dart` and as env-var references in the Python harnesses (**no key value committed**). The embedded **anon key is safe by design** (RLS enforces access). ML API keys are Supabase Edge Function secrets, not in the repo. **PASS.**

## A03 — Injection

- **SQL/NoSQL:** the client uses **PostgREST** (parameterized) and the edge function uses parameterized inserts; no raw SQL is built from user input. RLS is a second layer. **PASS (Low risk).**
- **XSS:** the app is **Flutter (native canvas rendering)**, not an HTML DOM, so stored/reflected XSS does not apply to the mobile app; the optional web build has a minimal DOM surface. **N/A (mobile).**
- **Command injection:** no shell/exec of user input anywhere. **N/A.**

## A05 — Security Misconfiguration

- **CORS / security headers:** managed by Supabase (per-project allowed origins). **NEEDS REVIEW** — confirm production CORS is restricted to the app's origins rather than `*`.
- **Error handling / info leakage:** `auth_service._mapAuthException` maps backend errors to **friendly messages**; no stack traces or raw exceptions are shown to the user. **PASS.**
- **Exact-alarm / notification permissions** are declared correctly (Android manifest). **PASS.**

## A04 — Insecure Design  *(positive controls present)*

- **Consent-based doctor access**, **time-limited read-only break-glass**, **role-based RBAC**, and **append-only audit log** are explicit design controls. **PASS (well-designed for the scope).** *Gap:* break-glass exposes scan/history **rows** but the design does not log **doctor** read access (only admin/break-glass/privacy actions) — see A09.

## A06 — Vulnerable & Outdated Components

- `flutter analyze` clean (0 errors); however `flutter pub get` reports **32 packages have newer versions**. **NEEDS REVIEW** — run `flutter pub outdated` and patch security-relevant deps before final submission.

## A09 — Security Logging & Monitoring Failures

- **`audit_log`** records admin role changes, account (de)activation, and **break-glass** open/revoke; **`security_activity`** (on-device) logs sign-in, password/profile/consent changes, export, and deletion requests. **PARTIAL** — **doctor** read access to consenting patients is **not** server-logged. *Recommendation:* add audit entries for doctor record access.

## A10 — Server-Side Request Forgery (SSRF)

- The edge function calls **fixed** Roboflow/Hugging Face URLs (not user-controlled). **N/A / PASS.** *Governance note:* scan images leave the Supabase trust boundary to third-party ML — a data-processing agreement / de-identification is a production consideration (see `trust_boundary_dfd`).

## File-Upload Security  *(patients upload facial images)*

- **Type:** uploaded with `contentType: image/jpeg`; a **face-detection preflight** gates capture. **PASS** for the intended path. *Note:* the client does not hard-validate magic bytes or enforce an explicit size cap — Supabase bucket limits apply.
- **Storage location:** **private** bucket; **server-generated path** `{user_id}/{scan_id}.jpg` (filename is **not** user-controlled → no path traversal). **PASS.**
- **Execution risk:** stored objects are images served via signed URLs; not executable. **PASS.**

## A08 — Software & Data Integrity Failures

- Release APKs are built by **GitHub Actions** from tagged commits (traceable provenance). Currently signed with the **debug keystore** (`build.gradle.kts` TODO). **NEEDS REVIEW** — configure a release signing key before distribution.

---

## Summary table

| Test ID | Category (OWASP) | Test performed | Expected | Result | Severity | Recommendation |
|---|---|---|---|---|---|---|
| ST-AC-01 | A01 Access control | Patient reads another user's scans via `user_id` filter | 0 rows | **0 rows — PASS** | — | — |
| ST-AC-02 | A01 | Patient reads `patient_histories` | own only | **1 (own) — PASS** | — | — |
| ST-AC-03 | A01 | Patient reads `break_glass_sessions` / `audit_log` | denied | **0 rows — PASS** | — | — |
| ST-AC-04 | A01 | Role gates per account (RPC) | correct per role | **PASS** | — | — |
| ST-AC-05 | A01 | Patient reads `profiles` | own/limited | **all 5 — FINDING** | Low–Med | Restrict profiles SELECT policy |
| ST-AU-01 | A07 Auth | Password hashing | bcrypt (managed) | **PASS** | — | — |
| ST-AU-02 | A07 | Password policy | enforced | **PASS** (client+len) | Low | Enforce complexity server-side |
| ST-AU-03 | A07 | Brute-force lockout | limited | **PASS** | Low | Keep server rate limits |
| ST-AU-04 | A07 | Idle session timeout | auto logout | **PASS** (15 min) | — | — |
| ST-DA-01 | A02 Crypto | TLS in transit | HTTPS/WSS | **PASS** | — | — |
| ST-DA-02 | A02 | Secrets in repo | none committed | **PASS** | — | — |
| ST-DA-03 | A02 | Private images + signed URLs | enforced | **PASS** | — | — |
| ST-IN-01 | A03 Injection | SQL injection | parameterized + RLS | **PASS** | — | — |
| ST-CF-01 | A05 Misconfig | CORS / headers | restricted | **NEEDS REVIEW** | Low | Confirm prod CORS origins |
| ST-CF-02 | A05 | Error leakage | friendly msgs | **PASS** | — | — |
| ST-LG-01 | A09 Logging | Doctor read access logged | logged | **PARTIAL** | Low | Audit doctor reads |
| ST-FU-01 | File upload | Type/path/storage | safe | **PASS** | Low | Add size + magic-byte check |
| ST-IN-02 | A08 Integrity | Release signing | release key | **NEEDS REVIEW** | Med | Add release keystore |
| ST-DEP-01 | A06 Components | Dependency freshness | current | **NEEDS REVIEW** | Low | `flutter pub outdated` |

## Risk assessment

DermaTrack's **core access-control model is sound and was verified live**: row-level security correctly isolates each patient's scans, history, and messages; admin-only tables and IDOR attempts are blocked at the database; doctor access is consent-gated; and emergency admin access is read-only, time-limited, and audited. Authentication relies on a mature managed provider (Supabase/GoTrue) with bcrypt hashing, lockout, idle timeout, and non-enumerating password reset, and no secrets are committed to the repository. The residual risks are **low-to-medium and configuration-level rather than architectural**: (1) the `profiles` table is world-readable to authenticated users (enumeration of usernames/roles), (2) doctor read access is not server-audited, (3) the release APK is debug-signed, and (4) CORS and dependency freshness should be confirmed before production. None of these expose clinical PHI to unauthorized users in the tested configuration. Addressing items 1–3 would bring the system to a strong posture appropriate for handling health data at thesis-demonstration scale.
