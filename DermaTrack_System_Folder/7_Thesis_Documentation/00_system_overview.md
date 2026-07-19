# DermaTrack — System Overview (Phase 0)

> Source of truth for the thesis diagrams and testing documentation. **Everything here is derived from the actual codebase** (`app/lib/**`, `supabase/full_schema.sql`, `supabase/migrations/0001–0011`, `supabase/functions/analyze-scan`). Generated read-only; no features, tables, or tests are invented.

---

## 1. What DermaTrack does

DermaTrack is a **mobile acne-severity *monitoring* application** — explicitly **non-diagnostic** decision-support (the result screen and `lib/data/severity_guidance.dart` state this). A patient captures facial photos; the app grades severity on the **Cook 0–8 scale**, presents it as **Mild / Moderate / Severe** with self-care guidance, and tracks the trend over time. With the patient's explicit **consent**, a dermatologist can review scans, leave notes, set a treatment plan, issue prescriptions, and chat. An **admin** manages users and roles and can perform **logged, time-limited break-glass** access to a patient record.

**The app does NOT contain:** appointment booking, a "diagnosis" record entity, payments, or SMS. It is severity monitoring, not a clinic-management system.

## 2. Technology stack

| Layer | Technology |
|---|---|
| Frontend | **Flutter / Dart** (Android primary; iOS configured; web buildable). State via `ChangeNotifier` singleton services. |
| Backend | **Supabase**: PostgreSQL, Auth (GoTrue), Storage, Realtime, and an **Edge Function** (`analyze-scan`, Deno/TypeScript). |
| Authorization | **PostgreSQL Row-Level Security (RLS)** — enforced in the database, not the client. |
| ML / image analysis | **Roboflow** (`acne-detection-zukbx/4`, lesion detection) + **Hugging Face Space** (`imfarzanansari/skintelligent-acne`, severity classifier), combined in `analyze-scan`. |
| Email | Supabase Auth built-in mailer (password reset only). No app-sent email/SMS/push. |
| Notifications | **Local** on-device (`flutter_local_notifications`) + an in-app **Notification Center** synthesized client-side. No FCM/push, no notifications table. |
| CI/CD | GitHub Actions builds split-ABI release APKs on `v*` tags. |

**There is no traditional web "routes/controllers" layer.** Business logic lives in `app/lib/services/*` (singletons); screens in `app/lib/screens/*`; **access control is RLS** in Postgres.

## 3. Project structure

```
app/lib/
  models/      scan, app_notification, prescription, message, treatment_plan, patient_history, acne_reference
  services/    auth, scan, doctor, admin, profile, prescription, chat, patient_history,
               notification_center, notification_prefs, security_activity, session_timeout,
               scan_reminder, face_detection, region_alignment_evaluator, doctor_report
  data/        severity_guidance, acne_references
  screens/     welcome, login, register, forgot_password, dashboard, camera, calendar, gallery,
               profile, edit_profile, change_password, settings, notification_center,
               notification_settings, scan_reminder, privacy_data, help_support, scan_detail,
               admin/ (admin_shell, break_glass), doctor/ (shell, patient list/detail, scan
               compare/detail, prescriptions), scan_session/ (session, complete), patient_history/
  widgets/     facial_summary_card, notification_bell_action, settings widgets, nav_profile_icon, …
  theme/
supabase/
  migrations/  0001_init … 0011_roles_admin_breakglass
  full_schema.sql           (consolidated, authoritative)
  functions/analyze-scan/   (Deno edge function: Roboflow + HF)
loadtest/  qa/  security/    (Python test harnesses from earlier work)
.github/workflows/           (release-apk CI)
```

## 4. Roles & permissions (RBAC) — what each role ACTUALLY can do

Roles are stored in **`profiles.role`** (`patient | doctor | admin`, migration 0011) and resolved in `auth_service.dart` (`userRoleFromString`, `isDoctor`, `isAdmin`). **Enforcement is RLS** via SQL functions: `is_demo_doctor()` (role = doctor), `is_admin()` (role = admin), `has_active_break_glass(patient)`.

| Capability (grounded in RLS policies + services) | Patient | Doctor | Admin |
|---|:--:|:--:|:--:|
| Create/read/update/delete **own** scans + scan images | ✅ | — | — |
| Own clinical intake `patient_histories` (full CRUD) | ✅ | read* | — |
| Read own `doctor_notes` / `treatment_plans` / `prescriptions` | ✅ | write* | — |
| Patient↔doctor **messages** (Realtime) | own thread | consenting* | — |
| Grant/revoke **doctor consent** (`profiles.shared_with_doctor`) | ✅ | — | — |
| Read **consenting** patients' scans/history/plan/Rx/messages/images | — | ✅ (consent‑gated) | — |
| User management: change **role**, **activate/deactivate** accounts | — | — | ✅ |
| Read **audit_log** | own/related | — | ✅ (all) |
| **Break-glass**: open/revoke time-limited read-only access | — | — | ✅ (logged) |
| Read a patient's scan/history rows during active break-glass | — | — | ✅ (metadata only — see §5) |

\* **Doctor access is consent-gated** by `profiles.shared_with_doctor = true`. Doctors do **not** see all patients by default. *(Verified live this session: `is_demo_doctor()` returns true only for role=doctor; admin and patient correctly return false.)*

## 5. UI-vs-implemented gaps (flagged honestly)

- **Admin content modules are not implemented:** educational-content, FAQ, notification-template, and support-ticket/bug-report management have **no tables and no screens**. The Admin console implements **Overview (monitoring) + User management + Audit log + Break-glass** only.
- **Break-glass reads scan *metadata*, not photos:** RLS grants admins read on `scans`/`patient_histories` during a session, but there is **no break-glass storage policy**, so scan **images** are not retrievable via break-glass.
- **"Super admin notified"** on break-glass = an **`audit_log`** entry (no real push/email).
- **Doctor/Admin accounts are seed-only:** registration always creates a **patient**; the "Login as Doctor/Admin" buttons only theme the login screen — the effective role comes from the database.
- **Notifications are local + in-app only** (no FCM/push, no notifications table). **Session timeout (15 min) and login lockout (5 attempts → 60 s) are client-side.**

## 6. Database schema

**9 application tables** + Supabase-managed **`auth.users`** + **3 private storage buckets** (`profile-pictures`, `scan-images`, `prescription-images`). 🔒 marks tables holding PHI/PII.

| Table | PK | Notable fields (type) | Foreign keys / relationship |
|---|---|---|---|
| 🔒 `profiles` | `id` uuid | `username` text uniq(≥3), `display_name`, `profile_picture_path`, **`role`** text(patient/doctor/admin), **`is_active`** bool, `shared_with_doctor` bool, `messaging_restricted` bool, `can_switch_roles` bool, `created_at`, `updated_at` | `id` → `auth.users(id)` (1:1, cascade) |
| 🔒 `scans` | `id` uuid | `user_id`, `taken_at`, `image_path`, `cook_grade` int(−1..8), `severity_label`, `inflammatory_count`/`non_inflammatory_count`/`post_acne_count` int, `lesions` jsonb, `source_metadata` jsonb, `notes`, `region` text, `session_id` uuid, `created_at` | `user_id` → `auth.users` (N:1, cascade) |
| 🔒 `doctor_notes` | `scan_id` uuid | `note` text, `created_at`, `updated_at` | `scan_id` → `scans` (1:1, cascade) |
| 🔒 `patient_histories` | `user_id` uuid | `full_name`, `address`, `birthday` date, `sex`, `occupation`, `contact_no`, `past_medical_conditions` text[], `past_medical_others`, `previous_surgery_detail`, `allergies_detail`, `family_history_conditions` text[], `family_history_others`, `smoker_pack_years` numeric, `uses_prohibited_drugs` bool, `is_alcohol_drinker` bool, `social_others`, `current_medications`, timestamps | `user_id` → `auth.users` (1:1, cascade) |
| 🔒 `treatment_plans` | `user_id` uuid | `plan` text, `created_at`, `updated_at` | `user_id` → `auth.users` (1:1, cascade) |
| 🔒 `prescriptions` | `id` uuid | `user_id`, `body` text, `image_paths` text[], `created_at`, `updated_at` | `user_id` → `auth.users` (N:1) |
| 🔒 `messages` | `id` uuid | `patient_id`, `sender_id`, `sender_role` text(patient/doctor), `body` text, `edited_at`, `deleted_at`, `removed_by_admin` bool, `created_at` | `patient_id`, `sender_id` → `auth.users` |
| `audit_log` | `id` uuid | `actor_id`, `actor_role`, `action`, `target_user_id`, `detail`, `created_at` | `actor_id` → `auth.users` (set null) |
| `break_glass_sessions` | `id` uuid | `admin_id`, `target_patient_id`, `reason`, `duration_minutes` (15/30/60), `read_only` bool, `granted_at`, `expires_at`, `revoked` bool | `admin_id`, `target_patient_id` → `auth.users` (cascade) |

**PHI/PII concentration:** identity (`profiles`), full clinical intake incl. name/address/birthday/contact/medical & family history/substance use (`patient_histories`), facial **images** (`scan-images` / `prescription-images` buckets), and severity history (`scans`). All gated by per-user RLS; images are private and served via **short-lived signed URLs**; transport is **HTTPS** (Supabase).

## 7. Key data flows (for the sequence/activity diagrams)

1. **Authentication** — "Login as" selection → `signInWithPassword` → role resolved from `profiles.role` → routed to Patient / Doctor / Admin shell (lockout after 5 failed attempts).
2. **Scan analysis** (the "upload & analyze" flow) — capture/select image → `scan_service` uploads to `scan-images` → `analyze-scan` edge function calls Roboflow + Hugging Face → derives Cook grade + severity → writes `scans` row → result screen shows Mild/Moderate/Severe + guidance.
3. **Per-region session** — five facial zones (forehead, cheeks, chin, nose) each analyzed → overall worst-region summary.
4. **Doctor review** — consent-gated: doctor loads consenting patient's scans → writes `doctor_notes` / `treatment_plans`.
5. **Prescription** — doctor creates `prescriptions` (+ images) → patient views.
6. **Chat** — patient↔doctor `messages` over Supabase Realtime.
7. **Break-glass** — admin opens a time-limited read-only `break_glass_sessions` row (reason + duration) → reads patient records → `audit_log` entry.

## 8. Scope corrections vs. a generic clinic-app template

The diagrams replace appointment/booking/diagnosis flows (which **do not exist**) with the **real** flows above. The "patient uploads image → doctor reviews" requirement maps to **scan analysis + consent-gated doctor review**. The "case/appointment status" state machine maps to **break-glass session lifecycle** and **scan review status** (unreviewed → reviewed), both of which are real in the code.
