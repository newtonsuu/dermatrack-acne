# DermaTrack — System Specification & Simulation Run-Through
### Source material for the DermaTrack user manual

> Grounded in the actual code/backend. Features that were **not** runtime-tested on a device are marked accordingly; unknown details are marked **[To be filled in]**. Notes flag where the real app differs from a generic template.

---

## 1. System Overview
DermaTrack ("DermaTrack: A Mobile Decision Support Application for Severity-Based Tracking and Logging of Facial Acne") is a mobile app that helps a person **monitor their facial acne over time**. The user takes face photos; the app grades the severity (Mild / Moderate / Severe) and keeps a history so changes are easy to follow. With the user's consent, a dermatologist can review the scans, leave notes, set a treatment plan, send prescriptions, and chat. An administrator manages user accounts.

**It is a monitoring / decision-support tool, not a diagnosis.** Every result shows a reminder to consult a licensed dermatologist.

**Who uses it:** Patients/Users (track their own skin), Dermatologists/Reviewers (review consenting patients), and Administrators (manage users and moderate chats).

## 2. System Specifications

| Specification | Description |
|---|---|
| Application Name | DermaTrack |
| Application Type | Mobile decision-support application (acne severity monitoring; non-diagnostic) |
| Platform | Flutter application — Android (primary, released as APK); web build available; iOS configurable but not released |
| Frontend | Flutter / Dart |
| Backend | Supabase (PostgreSQL + Auth + Storage + Realtime + Edge Functions) |
| Database | Supabase PostgreSQL, with Row-Level Security (RLS) enforcing per-user access |
| Storage | Supabase Storage — three **private** buckets: `scan-images`, `prescription-images`, `profile-pictures` (accessed via short-lived signed URLs) |
| Authentication | Supabase Auth (GoTrue) — email + password, JWT sessions; password reset by email |
| External API / AI Service | **Roboflow** (`acne-detection-zukbx/4`, lesion detection) + **Hugging Face** Space (`imfarzanansari/skintelligent-acne`, severity classifier), combined in the `analyze-scan` Edge Function |
| Supported Environment | Android phones (minimum Android 5.0 / API 21; target 10–14), ABIs arm64-v8a / armeabi-v7a / x86_64; web build runs in Chrome (preview). Specific tested device: **[To be filled in]** |
| Internet Requirement | Required for login, image upload, API analysis, and data retrieval. (On-device reminders fire offline once scheduled.) |
| User Roles | Patient/User, Dermatologist/Reviewer (Doctor), Administrator |

## 3. Test Environment and Build Information

| Test Environment | Device / Browser / Emulator | Version | Screen Size / Resolution | Build Type | Remarks |
|---|---|---|---|---|---|
| Web build | Chrome (Desktop) | Latest Chrome | Desktop viewport | Web build (release) | `flutter build web --release` compiled & served successfully. Camera & notifications limited on web. |
| Android APK | **[Device or emulator — To be filled in]** | **[Android version]** | **[Resolution]** | APK build (release) | CI built 3 split-ABI release APKs (latest v0.7.0). On-device run **[To be filled in by developer]**. Currently debug-signed. |

## 4. Account Types and Access Rights

| Account Type | Description | Accessible Features |
|---|---|---|
| Patient/User | Main user who records and monitors acne progress | Login/register, dashboard, quick full-face scan, guided per-region scan, severity result + guidance, history/calendar/gallery, severity trend, scan notes, clinical intake form, **doctor-sharing consent**, view doctor notes / treatment plan / prescriptions, chat (with edit/unsend), notification center, notification & reminder settings, privacy & data (export JSON, delete scans, request account deletion, security activity), help & support, profile/avatar, change password |
| Dermatologist/Reviewer (Doctor) | Authorized reviewer who checks **consenting** patients' records | Login, list of **consenting** patients, view patient scans / history / severity trend, compare two scans, add/edit doctor notes, set treatment plan, issue prescriptions (with images), chat, **export PDF consultation report** |
| Administrator | System-level user who manages users and moderates chats | Login, monitoring overview (user/role counts, deactivated, active break-glass), user management (change role, activate/deactivate, restrict messaging), audit log, **break-glass** emergency read-only patient access (logged), **chat moderation** (view threads, remove messages, restrict users) |

> Note: A single account holds one role at a time (stored in `profiles.role`). One demo "super" account (`jjr`) is flagged to **switch roles** for demonstration.

## 5. Feature Inventory

| Feature | User Role | Purpose | Main Actions | Inputs Needed | Output / Result | Screenshot Needed |
|---|---|---|---|---|---|---|
| Login | All | Access the system | Enter email/password, tap Sign in | Email, password | Redirected to role-based dashboard | Login screen |
| "Login as" selection | All | Choose access type | Tap Patient / Doctor / Admin | — | Opens themed login | Welcome screen |
| Register | Patient | Create a patient account | Fill form, submit | Email, username, password | Account created, signed in | Register screen |
| Forgot password | All | Reset password | Enter email, send link | Email | Reset email sent (no account disclosure) | Reset screen |
| Quick full-face scan | Patient | Fast overall severity | Open Scan, capture/upload full-face photo | Facial image | Mild/Moderate/Severe + guidance | Full-face capture + result |
| Per-region scan (guided session) | Patient | Detailed per-zone severity | Walk through 5 zones (forehead, L cheek, R cheek, chin, **nose**), capture each | 5 facial-zone images | Per-region tiers + **Overall Result** summary | Region capture + summary |
| Scan result | Patient | Show severity + advice | View result | — | Tier, Cook grade, lesion counts, guidance, non-diagnostic disclaimer | Result screen |
| History / Calendar | Patient | Track scans over time | Open Calendar/History, tap a day | — | Past scans; day summary | Calendar + day sheet |
| Gallery | Patient | Browse scan thumbnails | Open Gallery | — | Grid of scans | Gallery screen |
| Severity trend | Patient | See progress trend | View dashboard chart | — | Trend chart | Dashboard |
| Scan notes | Patient | Add personal notes to a scan | Edit note | Text | Saved note | Result/notes |
| Clinical intake | Patient | Record medical history | Fill intake form | Demographics, medical/family history, etc. | Saved history | Patient history form |
| Share with dermatologist (consent) | Patient | Allow doctor access | Toggle in Privacy & Data | — | Consent on/off | Privacy & Data |
| View doctor note / plan / prescriptions | Patient | See dermatologist output | Open relevant card/screen | — | Note / plan / prescriptions list | Result + Prescriptions |
| Chat | Patient & Doctor | Message each other | Type, send; long-press own msg to **Edit/Unsend** | Message text | Live thread; "edited"/"unsent" labels | Chat screen |
| Notification Center | Patient | See alerts | Tap bell | — | Reminders, severity changes, doctor updates, security alerts | Notification center |
| Notification settings | Patient | Control alerts | Toggle categories, set reminder time | — | Saved preferences | Notification settings |
| Scan reminder | Patient | Daily scan nudge | Enable, pick time, choose frequency (daily/2-day/weekly) | Time | "Daily scan reminder updated" | Scan reminder screen |
| Privacy & Data | Patient | Manage data | Export (JSON), delete scans, request account deletion, view security activity | — | JSON export; deletions; recorded request | Privacy & Data |
| Help & Support | All | Get help | FAQ, how-to-scan, contact, report bug, disclaimer, terms | — | Info screens | Help & Support |
| Profile / avatar | Patient | Manage profile | Edit name/username, set photo | Name, username, image | Updated profile | Profile / edit profile |
| Change password / Sign out | All | Account security | Change password; sign out | New password | Updated / signed out | Settings |
| Doctor: patient list | Doctor | See consenting patients | Open list, search/sort, "needs review" | — | Consenting patients only | Doctor patient list |
| Doctor: patient detail | Doctor | Review a patient | Open patient → scans/history/trend | — | Patient records | Doctor patient detail |
| Doctor: compare scans | Doctor | See progression | Pick two scans | — | Side-by-side delta | Compare screen |
| Doctor: note / plan / prescription | Doctor | Provide care | Write note, set plan, issue Rx (+images) | Text/images | Saved, visible to patient | Doctor note / Rx |
| Doctor: PDF report | Doctor | Consultation summary | Tap export | — | Shareable PDF report | Doctor report (share sheet) |
| Admin: overview | Admin | System monitoring | Open Overview | — | User/role counts, deactivated, active break-glass | Admin overview |
| Admin: user management | Admin | Manage users | Change role, activate/deactivate, restrict messaging | — | Updated account (audited) | Admin users |
| Admin: audit log | Admin | Review actions | Open Audit tab | — | Logged admin/break-glass actions | Admin audit |
| Admin: break-glass | Admin | Emergency read-only patient access | Select patient, reason, duration, confirm | Patient, reason, 15/30/60 min | Read-only records (logged) | Break-glass |
| Admin: chat moderation | Admin | Moderate chats | View threads, remove message, restrict user | — | Moderated thread (audited) | Admin chats |
| Switch role (demo super account) | jjr only | Demo all roles | Settings/app-bar → Switch role | — | Re-routes to chosen role | Role switcher |

> **Important correction:** there is **no patient "Report" page that generates a PDF**. The **patient** exports their records as **JSON** (Privacy & Data). The **PDF consultation report is a doctor-side feature**. Scenario 5 below is annotated accordingly.

## 6. Image Capture Simulation Guidelines
These are the **recommended capture standards** for clear images. (The app guides capture with an on-screen oval frame and an automatic face-alignment check; it does not measure exact distance — treat the distances as guidance.)

- **Full-face scan distance:** ~45–60 cm so the whole face fits the oval guide.
- **Per-region scan distance:** ~20–35 cm for clearer detail of the selected zone.
- **Lighting:** bright, even, non-colored light; face a window or soft lamp; avoid harsh shadows/backlight.
- **Face positioning:** center the face (or the target zone) inside the on-screen guide; follow the alignment hint.
- **Device stability:** hold the phone steady before capturing to avoid blur.
- **Conditions to avoid:** dim or colored lighting, strong backlight, heavy makeup that hides lesions, motion blur, dirty lens, extreme angles.

| Capture Requirement | Recommended Standard | Purpose |
|---|---|---|
| Full-face scan distance | 45 to 60 centimeters | Captures the whole face inside the guide frame |
| Per-region scan distance | 20 to 35 centimeters | Captures clearer details of the selected facial area |
| Lighting | Bright, even, and non-colored lighting | Improves image clarity |
| Positioning | Face or target region centered inside the guide frame | Ensures the correct area is scanned |
| Stability | Hold the device steady before capturing | Reduces blur |

## 7. Simulation Run-Through
> Verification key: **Verified** = confirmed this assessment (auth/backend/data layer or automated tests). **To be executed on device** = correct per code but needs a physical-device run (camera/notifications).

**Scenario 1 — Patient/User Login**
1. Open DermaTrack. 2. Enter registered email + password. 3. Tap Sign in. 4. Dashboard appears.
*Expected:* user logs in and lands on the patient dashboard. **Status: Verified** (login + role routing confirmed live).

**Scenario 2 — Full-Face Scan**
1. Go to Scan. 2. Capture/select a full-face photo (align in the oval). 3. Wait for analysis. 4. View severity result.
*Expected:* the app shows Mild/Moderate/Severe + guidance and saves the scan. **Status:** analysis pipeline (upload → Roboflow + Hugging Face → grade → save) **Verified deployed**; on-device camera capture **To be executed on device**.

**Scenario 3 — Per-Region Scan**
1. Go to Scan → start the guided per-region session. 2. The app walks through **forehead → left cheek → right cheek → chin → nose** (it does **not** ask you to pick one region). 3. Capture each zone in the guide. 4. Wait for analysis. 5. View per-region tiers + an **Overall Result** summary.
*Expected:* per-zone results plus an overall facial-severity summary. **Status:** backend (incl. the "nose" region) **Verified**; on-device capture **To be executed on device**.

**Scenario 4 — View Scan History**
1. Open Calendar/History. 2. Tap a day/record. 3. Review image, result, date, notes; for a guided-session day, an overall summary is shown.
*Expected:* the selected record displays. **Status: Verified** at the data layer.

**Scenario 5 — Generate Consultation Report**
- **Patient:** there is no PDF "Report" page; the patient instead uses **Privacy & Data → Export my records (JSON)**.
- **Doctor:** opens a patient → **Export PDF report** (consultation summary share sheet).
*Expected:* JSON export (patient) or PDF consultation report (doctor). **Status:** patient JSON export **Verified** (logic); doctor PDF export **To be executed on device** (uses the OS share sheet).

**Scenario 6 — Dermatologist Review**
1. Log in as a doctor. 2. Open the patient list (shows **only consenting** patients). 3. Select a patient. 4. Review scans, severity outputs, history, notes.
*Expected:* the doctor sees the consenting patient's shared records. **Status: Verified** (consent-gated access confirmed live).

**Scenario 7 — Administrator User Management**
1. Log in as admin. 2. Open User management. 3. View accounts. 4. Change role / deactivate / reactivate / restrict messaging.
*Expected:* the admin can manage account status and access. **Status: Verified live** (role change, deactivate/reactivate confirmed; deactivation now enforced at the database).

## 8. Screenshot Checklist
*(All to be captured on a device/emulator — none are auto-generated.)*

| Screenshot No. | Screen / Feature | Purpose |
|---|---|---|
| 1 | Login / "Login as" screen | Where users choose role + enter credentials |
| 2 | Home dashboard | Main landing page after login |
| 3 | Full-face scan | Full-face capture guide |
| 4 | Per-region scan (guided session) | Regional capture guide + step progress |
| 5 | Acne result screen | Mild/Moderate/Severe output + guidance + disclaimer |
| 6 | Per-region overall summary | Combined facial-severity summary |
| 7 | Scan history / calendar | Saved scan records |
| 8 | Notification Center | Alerts feed |
| 9 | Scan reminder settings | Reminder time/frequency |
| 10 | Privacy & Data | Consent, export, delete, security activity |
| 11 | Chat (with edit/unsend) | Messaging + message actions |
| 12 | Doctor patient list & detail | Reviewer access to consenting patients |
| 13 | Doctor PDF report | Consultation report/share |
| 14 | Admin overview & user management | Monitoring + account control |
| 15 | Admin chat moderation / break-glass | Moderation + emergency access |
| 16 | Profile / settings | Profile, avatar, settings |

## 9. Issues Observed During Simulation

| Issue No. | Feature | Observed Issue | Possible Cause | Action Taken / Recommendation |
|---|---|---|---|---|
| 1 | Notification / reminder | "Couldn't update reminder — Missing type parameter" crash on release APK (earlier versions) | Corrupted local scheduled-notification cache in `flutter_local_notifications` | **Fixed (v0.5.1):** cache-recovery + retry, device-timezone, fixed ID. On-device re-confirmation recommended. |
| 2 | Camera access / capture | Not exercised in this assessment | No physical camera/device in the test environment | **To be executed on a physical device** (capture is device-only). |
| 3 | Patient "report" expectation | Patient has JSON export, not a PDF report page | Feature scope (PDF report is doctor-side) | Document accordingly in the manual; no fix needed. |
| 4 | Access control (security) | Self privilege-escalation + UI-only deactivation found | Permissive `profiles` UPDATE; deactivation not DB-enforced | **Fixed (migrations 0013/0014)** and re-verified. |
| 5 | Web build | Camera + OS notifications limited on web | Browser platform limits | Use the Android APK for full experience; web is a preview. |

## 10. Final Summary for User Manual Preparation
Ready to build the manual from:
- **Confirmed features:** login/register/reset; quick full-face scan + guided per-region (5-zone) scan; severity result (Mild/Moderate/Severe) + guidance + disclaimer; history/calendar/gallery/trend; scan notes; clinical intake; doctor-sharing consent; chat with edit/unsend; notification center + settings; scan reminder; privacy & data (JSON export, delete, deletion request, security activity); profile/settings; doctor review (notes, plan, prescriptions, compare, PDF report); admin (overview, user management, audit, break-glass, chat moderation).
- **User roles:** Patient/User, Dermatologist/Reviewer (Doctor), Administrator (one role per account; demo role-switch account exists).
- **System specifications:** Section 2 (Flutter + Supabase + Roboflow/Hugging Face).
- **Screenshots needed:** Section 8 checklist (all to be captured on device).
- **Step-by-step workflows:** Section 7 scenarios (with verification status).
- **Account management instructions:** admin role change / activate-deactivate / restrict messaging; patient consent + privacy/data controls.
- **Support & troubleshooting topics:** Help & Support (FAQ, how-to-scan, contact, report bug, disclaimer, terms); reminder permission on Android 13+; "use Android APK, not web, for camera/notifications"; internet required for scan/analysis.

**Still needed before finalizing the manual:** **[To be filled in]** — the actual test device(s) + Android version + resolution, and all screenshots (Section 8), captured from the installed v0.7.0 APK.
