# DermaTrack — Diagram captions & render guide

Every diagram is derived from the actual codebase (see `../00_system_overview.md`). For each file below: a **figure caption** (for under the figure in your paper) and a **3–5 sentence description**.

> Scope note: DermaTrack has no appointment/booking/diagnosis/payment features, so the appointment-style diagrams from a generic clinic template were replaced with the system's real flows (scan analysis, consent-gated doctor review, prescriptions, break-glass).

---

## How to render to PNG/SVG
Java 21 is installed on this machine, but `plantuml.jar` is not. To render:

```powershell
# 1) Download PlantUML once
Invoke-WebRequest -Uri https://github.com/plantuml/plantuml/releases/latest/download/plantuml.jar -OutFile plantuml.jar
# 2) From thesis-docs/diagrams, render all .puml to PNG and SVG
java -jar plantuml.jar -tpng *.puml
java -jar plantuml.jar -tsvg *.puml
```
Mermaid ERD (`database_erd.mmd`): paste into <https://mermaid.live>, or render with the CLI:
```powershell
npx -y @mermaid-js/mermaid-cli -i database_erd.mmd -o database_erd.png
```
(No-install option for any `.puml`: paste its contents into <https://www.plantuml.com/plantuml>.)

---

## Use-case diagrams

**`system_usecase.puml`** — *Figure: DermaTrack system-wide use-case diagram.*
Shows all four human/secondary actors (Patient, Doctor, Admin, plus Roboflow and Hugging Face as analysis actors) against every implemented use case. Authentication is shared and `<<include>>`s role resolution with an `<<extend>>` for account lockout. Scanning `<<include>>`s analysis (which calls the two ML services) and the result view. It scopes the whole system to what the code actually supports — no appointments or diagnosis records.

**`patient_usecase.puml`** — *Figure: Patient use cases.*
Enumerates the patient capabilities found in `screens/` and `services/`: quick and per-region scans, history/calendar/trend, clinical intake, doctor consent, notifications/reminders, privacy/data (export, delete, deletion request), chat, and help. Notes that doctor notes/plans become visible only after consent. Every item maps to a real screen.

**`doctor_usecase.puml`** — *Figure: Doctor use cases (consent-gated).*
The dermatologist's capabilities: view the consenting-patient list, review scans/history/trend, compare scans, write notes, set treatment plans, issue prescriptions, chat, and export a PDF report. A note records the key control: `doctor_service.loadPatients()` returns only patients with `shared_with_doctor = true`, so doctors never see all patients by default.

**`admin_usecase.puml`** — *Figure: Admin use cases.*
Implemented admin capabilities: monitoring overview, user/role management, account activation/deactivation, audit-log viewing, and break-glass emergency access. Every state-changing action `<<include>>`s an audit-write, and break-glass `<<include>>`s the read-only patient-record view. A note explicitly lists the admin modules that are **not** implemented (content/FAQ/notification-template/support-ticket management) so the figure isn't over-claimed.

## Data & domain

**`database_erd.puml`** / **`database_erd.mmd`** — *Figure: Entity-Relationship Diagram.*
The nine application tables plus Supabase-managed `auth.users`, with exact fields, types, primary and foreign keys, and cardinality taken from `full_schema.sql`. `auth.users` is the hub: 1:1 to `profiles`/`patient_histories`/`treatment_plans`, 1:N to `scans`/`prescriptions`/`messages`, and `scans` is 1:0..1 to `doctor_notes`. A note documents the three private storage buckets that hold the image files referenced by path columns. The `.mmd` version renders directly in GitHub/VS Code.

**`class_diagram.puml`** — *Figure: Domain model and key services.*
The core Dart model classes (`Scan`, `Lesion`, `SeverityGuidance`, `AppNotification`, `Prescription`, `Message`, `PatientHistory`, admin DTOs) with their enums and the `ChangeNotifier` service singletons (`AuthService`, `ScanService`, `DoctorService`, `AdminService`, `NotificationCenterService`). Associations show ownership (a service holds a list of models) and dependencies (a `Scan` is graded by `SeverityGuidance`). It captures attributes and the key methods that drive behavior.

## Sequence diagrams

**`seq_authentication.puml`** — *Figure: Authentication & role routing.*
Walks from the "Login as" screen through `signInWithPassword`, the security-activity log, the `profiles` role/`is_active` read, and the AuthGate decision that routes to the Admin/Doctor/Patient shell. Includes the lockout branch (≥5 failed attempts) and the deactivated-account branch.

**`seq_scan_analysis.puml`** — *Figure: Scan capture → analysis → severity result.*
The system's "upload and analyze" flow: image upload to private Storage, the `analyze-scan` edge function calling Roboflow then Hugging Face, the Cook-grade/severity computation, the `scans` insert, and the result screen rendering Mild/Moderate/Severe via `SeverityGuidance`. A note records the HF abort timeout and Roboflow-only soft-fail. This is monitoring, not a human diagnosis.

**`seq_doctor_review.puml`** — *Figure: Consent-gated doctor review.*
Shows the doctor loading the consenting-patient list (RLS filters to `shared_with_doctor = true`), fetching scans with short-lived signed image URLs, and writing a `doctor_notes` row that the patient later sees. RLS notes mark exactly where consent is enforced.

**`seq_prescription.puml`** — *Figure: Prescription issuance and viewing.*
The doctor uploads prescription images to a private bucket and inserts a `prescriptions` row (RLS: doctor + consenting patient); later the patient loads their prescriptions with freshly signed URLs. Demonstrates the doctor→patient clinical-content path end to end.

**`seq_break_glass.puml`** — *Figure: Admin break-glass emergency access.*
The admin opens a time-limited, read-only `break_glass_sessions` row (reason + duration), which writes an `audit_log` entry (the "reviewed" record), then reads the patient's scan/history rows gated by `has_active_break_glass()`. Includes the revoke branch. A note states images are not exposed via break-glass.

**`seq_chat.puml`** — *Figure: Patient–doctor messaging (Realtime).*
Both parties subscribe to a Supabase Realtime channel keyed by patient; inserts to `messages` broadcast live to the other side. RLS notes show patients write their own thread and doctors only consenting threads.

## Workflow, flow & architecture

**`activity_diagram.puml`** — *Figure: Core end-to-end workflow.*
Swimlaned across Patient/System/Doctor: sign in → scan → analyze → severity result; if Moderate/Severe and the patient consents, the doctor reviews and prescribes and it surfaces in the patient's Notification Center; reminders drive the follow-up scan. Captures the real monitoring loop rather than a booking workflow.

**`dfd_context.puml`** — *Figure: Data Flow Diagram, Level 0 (context).*
One process (DermaTrack) with the external entities Patient, Doctor, Admin, Roboflow, and Hugging Face, and the major data flows between them. Establishes the system boundary and what crosses it.

**`dfd_level1.puml`** — *Figure: Data Flow Diagram, Level 1.*
Decomposes the system into five processes (Authenticate, Scan & analyze, Review & treat, Messaging, Admin & break-glass) and the data stores (the Supabase tables + Storage). Shows where consent is checked and where break-glass read access is limited to an active session.

**`architecture_diagram.puml`** — *Figure: Component / layered architecture.*
Presentation and service layers of the Flutter app over the Supabase SDK, talking to Auth, Postgres+RLS, Storage, Realtime, and the `analyze-scan` edge function, which in turn calls Roboflow/Hugging Face; plus the GitHub Actions CI/APK pipeline. Protocols (HTTPS/WSS) are labelled.

**`deployment_diagram.puml`** — *Figure: Deployment topology.*
Physical/cloud nodes: the Android device running the APK; the Supabase project (Auth, Postgres, Storage, Edge runtime); Roboflow and Hugging Face clouds; and GitHub Actions building the APK published to Releases. Shows the install path and all inter-node links.

## State & security extras

**`status_statediagram.puml`** — *Figure: Break-glass session lifecycle.*
The richest real state machine: a session goes Active → (Expired automatically when `expires_at` passes) or → Revoked by the admin, with audit entries on transitions. A note states `has_active_break_glass()` is true only in the Active state and access is read-only.

**`scan_review_state.puml`** — *Figure: Scan review status.*
Derived from the presence of a `doctor_notes` row: a scan is Unreviewed (shown under the doctor's "needs review" filter) until a consenting-patient note moves it to Reviewed; the patient then sees "From your dermatologist."

**`rbac_matrix.puml`** — *Figure: RBAC permission matrix.*
A capability × role table showing exactly what Patient/Doctor/Admin can do, with the consent asterisk and the RLS functions that enforce each cell. A compact companion to the use-case diagrams and the security chapter.

**`trust_boundary_dfd.puml`** — *Figure: Security trust-boundary data flow.*
Overlays trust boundaries (user device, Supabase cloud, external ML) on the data flow, marking the RLS enforcement point, signed-URL image access, the client-side session/lockout controls, and the boundary where scan images leave to third-party ML. Strengthens the health-data security narrative and maps to the OWASP chapter.
