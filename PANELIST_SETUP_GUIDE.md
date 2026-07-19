# DermaTrack — Panelist & Evaluator Setup Guide

**Version:** 0.8.1+14  
**Framework:** Flutter (Dart) — Mobile frontend  
**Backend:** Supabase (PostgreSQL + Auth + Storage + Edge Functions)  
**AI Integration:** Roboflow `acne-detection-zukbx/4` + Hugging Face `imfarzanansari/skintelligent-acne`  
**Target Platform:** Android (API 21+) — primary; Flutter Web available

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Project Folder Structure](#2-project-folder-structure)
3. [Prerequisites](#3-prerequisites)
4. [Environment Variables & API Keys](#4-environment-variables--api-keys)
5. [Running the Flutter App (Android)](#5-running-the-flutter-app-android)
6. [Running the Flutter App (Web — Evaluator Preview)](#6-running-the-flutter-app-web--evaluator-preview)
7. [Supabase Backend Setup](#7-supabase-backend-setup)
8. [Supabase Edge Functions](#8-supabase-edge-functions)
9. [Database Schema & Migrations](#9-database-schema--migrations)
10. [AI Integration Details](#10-ai-integration-details)
11. [Key Packages (pubspec.yaml)](#11-key-packages-pubspecyaml)
12. [Android Build & Signing](#12-android-build--signing)
13. [Test Accounts](#13-test-accounts)
14. [Feature Summary by Role](#14-feature-summary-by-role)
15. [Thesis Diagrams & Documentation](#15-thesis-diagrams--documentation)

---

## 1. System Overview

DermaTrack is a mobile application designed for longitudinal acne severity monitoring and dermatologist-patient decision support. It uses on-device face detection (Google ML Kit) combined with cloud-based AI inference (Roboflow object detection + Hugging Face classifier) to grade acne severity on the Cook scale (0–8).

**Three user roles:**

| Role | Description |
|------|-------------|
| **Patient** | Captures scans, tracks severity over time, views prescriptions/plans, messages dermatologist |
| **Dermatologist** | Reviews patient scans, adds clinical notes, issues prescriptions and treatment plans |
| **Admin** | Manages user accounts, roles, messaging controls, audit logs, and break-glass emergency access |

**Architecture at a glance:**

```
Flutter App (Android/Web)
        │
        ├── Supabase Auth (JWT + GoTrue)
        ├── Supabase Database (PostgreSQL + RLS)
        ├── Supabase Storage (private scan-images bucket)
        │
        └── Supabase Edge Function: analyze-scan (Deno)
                ├── Roboflow API  (lesion detection overlay)
                └── HF Space API (holistic severity classification)
```

---

## 2. Project Folder Structure

```
dermatrack-acne/
├── app/                          Flutter application
│   ├── lib/                      All Dart source code (77 files)
│   │   ├── main.dart             App entry point
│   │   ├── app_info.dart         Version metadata
│   │   ├── data/                 Static reference data
│   │   ├── models/               Data models (Scan, Prescription, etc.)
│   │   ├── screens/              All UI screens (30 screens)
│   │   │   ├── admin/            Admin console screens
│   │   │   ├── doctor/           Dermatologist screens
│   │   │   └── scan_session/     Guided 5-region scan session
│   │   ├── services/             Business logic & API layer (16 services)
│   │   ├── theme/                App theme + dark/light controller
│   │   └── widgets/              Reusable UI components (16 widgets)
│   ├── assets/
│   │   ├── icon/                 App launcher icons
│   │   └── references/           Educational acne reference images
│   ├── android/                  Android platform config
│   │   └── app/src/main/
│   │       ├── AndroidManifest.xml
│   │       └── res/              App resources (icons, splash, drawables)
│   ├── pubspec.yaml              Dependencies manifest
│   └── test/                     Unit + golden tests
│
├── supabase/
│   ├── functions/
│   │   └── analyze-scan/
│   │       └── index.ts          Edge Function (Deno, TypeScript)
│   ├── migrations/               14 SQL migration files (0001–0014)
│   ├── full_schema.sql           Complete database schema dump
│   ├── schema.md                 Schema documentation
│   └── apply_to_live_db.sql      One-shot live DB script
│
├── thesis-docs/
│   ├── diagrams/                 35+ UML/flowchart/ERD diagrams
│   ├── screenshots/              Thesis-quality app screenshots
│   ├── testing/                  Functional, security, compatibility docs
│   └── user_manual_source.md     User manual draft
│
├── PANELIST_SETUP_GUIDE.md       ← This file
├── README.md                     Developer readme
└── SETUP_GUIDE_FOR_CO_AUTHOR.md  Co-author onboarding guide
```

---

## 3. Prerequisites

### For running the Flutter app

| Tool | Version | Install |
|------|---------|---------|
| Flutter SDK | ≥ 3.19.0 | https://docs.flutter.dev/get-started/install |
| Dart SDK | ≥ 3.3.0 (bundled with Flutter) | — |
| Android Studio | Any recent | For emulator / physical device |
| Android SDK | API 21+ (Android 5.0) | Via Android Studio SDK Manager |
| Java | 17 | Via Android Studio or system JDK |

After installing Flutter, verify with:
```bash
flutter doctor
```
All green checkmarks are required for a successful build.

### For Supabase backend (read-only evaluation)

The live Supabase project (`mqnoexkihwfmebalfobo`) is already running. No local Supabase setup is required to use the app — the app connects to the live backend automatically.

If you want to inspect or re-run migrations locally:
```bash
npm install -g supabase
supabase login
supabase link --project-ref mqnoexkihwfmebalfobo
```

---

## 4. Environment Variables & API Keys

The app reads its Supabase connection details from compile-time dart-defines. These are already baked into the release APK.

For a local development build, create `app/dart-defines.json`:
```json
{
  "SUPABASE_URL": "https://mqnoexkihwfmebalfobo.supabase.co",
  "SUPABASE_ANON_KEY": "<anon-key-from-supabase-dashboard>"
}
```

Then run:
```bash
flutter run --dart-define-from-file=dart-defines.json
```

### Supabase Edge Function Secrets

The `analyze-scan` edge function requires two secrets set on the Supabase dashboard (Settings → Edge Functions → Secrets):

| Secret | Value | Purpose |
|--------|-------|---------|
| `ROBOFLOW_API_KEY` | `<roboflow-key>` | Roboflow detection API |
| `HF_SPACE_URL` | `https://apjakilan-dermatrack-skintelligent.hf.space` | Hugging Face classifier |

These are already configured on the live project. No action needed for evaluation.

---

## 5. Running the Flutter App (Android)

### Option A — Install the Release APK (Recommended for Panelists)

Download the latest release APK from the GitHub Releases page:
- **arm64-v8a** — for modern phones (Pixel, Samsung S/A series, most 2019+)
- **armeabi-v7a** — for older 32-bit phones
- **x86_64** — for Android emulators

Enable "Install from unknown sources" on the device, then install the APK directly.

### Option B — Build and Run from Source

```bash
# 1. Clone the repository
git clone https://github.com/newtonsuu/dermatrack-acne.git
cd dermatrack-acne/app

# 2. Install dependencies
flutter pub get

# 3. Connect a device or start an emulator

# 4. Run in debug mode
flutter run --dart-define-from-file=dart-defines.json

# OR build a release APK
flutter build apk --split-per-abi --dart-define-from-file=dart-defines.json
```

The release APK will be at:
```
app/build/outputs/apk/release/
```

---

## 6. Running the Flutter App (Web — Evaluator Preview)

```bash
cd app
flutter run -d chrome --dart-define-from-file=dart-defines.json
```

> **Note:** The camera scan feature is limited on web (image_picker fallback). Face detection (ML Kit) does not work on web — the scan session will skip the preflight gate. All other features (scan history, doctor review, admin console, messaging) work normally on web.

---

## 7. Supabase Backend Setup

The production Supabase project is live at:
```
Project ID:  mqnoexkihwfmebalfobo
Region:      Southeast Asia (ap-southeast-1)
Dashboard:   https://supabase.com/dashboard/project/mqnoexkihwfmebalfobo
```

### Key Supabase Services Used

| Service | Purpose |
|---------|---------|
| **Auth** (GoTrue/JWT) | User registration, login, session management |
| **PostgreSQL** | Relational database with Row-Level Security (RLS) |
| **Storage** | Private `scan-images` bucket (signed URL access only) |
| **Realtime** | Live messaging between patient ↔ dermatologist |
| **Edge Functions** | `analyze-scan` — AI inference orchestration (Deno) |

### Row-Level Security (RLS)

All tables use PostgreSQL RLS with RESTRICTIVE policies. Access is determined by JWT role claim:
- `patient` → own data only
- `doctor` → shared patient data only (patient must grant access)
- `admin` → account management scope only; uses SECURITY DEFINER functions to prevent privilege escalation

---

## 8. Supabase Edge Functions

### analyze-scan (`supabase/functions/analyze-scan/index.ts`)

This is the only edge function. It is deployed to Supabase's Deno runtime.

**Flow:**
1. Flutter client uploads image to Storage → sends `scan_id` + `image_path` to this function
2. Function mints a short-lived signed URL (300 s TTL)
3. Calls Roboflow + HF Space **in parallel** (parallel reduces cold-start latency)
4. Roboflow: per-lesion detection with bounding boxes → Cook grade from lesion counts
5. HF Space: holistic severity classification → Cook grade from label
6. Combines grades: if the two models disagree by ≥2 severity buckets, HF wins; otherwise Roboflow grade is kept
7. Inserts scan row into `public.scans` with lesion overlay data, severity label, and audit metadata
8. Returns the inserted row — Flutter navigates directly to scan detail

**Deploy command (developer only):**
```bash
supabase functions deploy analyze-scan
```

---

## 9. Database Schema & Migrations

Migrations are in `supabase/migrations/` and run in order:

| File | Description |
|------|-------------|
| `0001_init.sql` | Core tables: profiles, scans, doctor_notes |
| `0002_doctor_demo.sql` | Demo doctor account seeding |
| `0003_doctor_notes.sql` | Indexed doctor notes |
| `0004_scan_regions.sql` | Facial region enum + scan session tables |
| `0005_patient_histories.sql` | Patient medical history |
| `0006_treatment_plans.sql` | Treatment plan table |
| `0007_doctor_demo_emails.sql` | Demo email addresses |
| `0008_prescriptions.sql` | Prescription management |
| `0009_messages.sql` | In-app messaging (patient ↔ doctor) |
| `0010_scan_region_nose.sql` | Added nose region |
| `0011_roles_admin_breakglass.sql` | RBAC hardening + Admin role + emergency access |
| `0012_messaging_moderation.sql` | Admin messaging controls |
| `0013_role_switcher.sql` | Developer role switcher (debug only) |
| `0014_harden_deactivation_and_profile_reads.sql` | Security hardening: deactivation + profile read protection |

**Full schema dump:** `supabase/full_schema.sql`  
**Schema documentation:** `supabase/schema.md`

---

## 10. AI Integration Details

### Roboflow — Lesion Detection

- **Model:** `acne-detection-zukbx/4`
- **API Endpoint:** `https://detect.roboflow.com/acne-detection-zukbx/4`
- **Method:** POST with signed image URL
- **Output:** Bounding boxes per lesion + class label + confidence score
- **Lesion classes:** papule, pustule, nodule, cyst (inflammatory) · comedone, whitehead, blackhead (non-inflammatory) · dark spot (post-acne)
- **Background filtering:** Uses ML Kit face bounding box to exclude off-face detections (padding ratio: 15%)

### Hugging Face — Severity Classifier

- **Model:** `imfarzanansari/skintelligent-acne` (6-class severity)
- **Hosted via:** Self-deployed Gradio Space: `apjakilan-dermatrack-skintelligent.hf.space`
- **API:** Gradio async queue (SSE stream) — two-step call (enqueue → poll)
- **Output:** Severity level -1 to 4, mapped to Cook scale 0–8
- **Timeout:** 20 s hard cap; on timeout, falls back to Roboflow-only grading

### Cook Scale Severity Labels

| Cook Grade | Label |
|-----------|-------|
| 0 | Clear |
| 1–2 | Mild |
| 3–4 | Moderate |
| 5–6 | Severe |
| 7–8 | Very Severe |

---

## 11. Key Packages (pubspec.yaml)

| Package | Version | Purpose |
|---------|---------|---------|
| `supabase_flutter` | ^2.5.0 | Backend connectivity (Auth, DB, Storage, Realtime, Functions) |
| `google_mlkit_face_detection` | ^0.10.0 | On-device face detection — camera preflight gate |
| `camera` | ^0.11.0 | Live camera preview for guided scan session |
| `image_picker` | ^1.1.2 | Gallery/camera capture (single-shot scan tab) |
| `flutter_local_notifications` | ^17.2.3 | Daily scan reminder (local, not push) |
| `timezone` | ^0.9.4 | Time-zone-aware notification scheduling |
| `fl_chart` | ^0.68.0 | Severity trend charts on dashboard |
| `pdf` | ^3.11.1 | PDF report generation (dermatologist side) |
| `printing` | ^5.13.2 | OS-level share/print sheet for PDF |
| `shared_preferences` | ^2.3.2 | Local persistence (theme, reminder settings) |
| `path_provider` | ^2.1.4 | Device file system access |
| `uuid` | ^4.4.0 | UUID generation for scan IDs |

---

## 12. Android Build & Signing

**App ID:** `com.example.dermatrack`  
**Min SDK:** Android 21 (Android 5.0 Lollipop)  
**Target SDK:** Flutter default (33+)  
**Compile SDK:** Flutter default  
**Java compatibility:** Java 17

### Required Android Permissions

| Permission | Purpose |
|-----------|---------|
| `CAMERA` | Live camera for guided scan session |
| `READ_EXTERNAL_STORAGE` | Gallery image picker |
| `POST_NOTIFICATIONS` | Daily scan reminder notifications |
| `RECEIVE_BOOT_COMPLETED` | Reschedule notifications after device restart |
| `SCHEDULE_EXACT_ALARM` | Precise notification timing |
| `INTERNET` | Supabase / AI API connectivity |

### Release Build

Signed APKs are produced via GitHub Actions CI on push to a `v*` tag. The workflow produces three split-ABI APKs:
- `app-arm64-v8a-release.apk`
- `app-armeabi-v7a-release.apk`
- `app-x86_64-release.apk`

---

## 13. Test Accounts

Use these accounts on the live Supabase project for evaluation:

| Role | Email | Password |
|------|-------|---------|
| Patient | `demo.patient@dermatrack.app` | `DermaDemo2025!` |
| Dermatologist | `demo.doctor@dermatrack.app` | `DermaDemo2025!` |
| Admin | Contact thesis author for Admin credentials |

> These accounts have pre-loaded scan history, prescription data, and messaging records for demonstration purposes.

---

## 14. Feature Summary by Role

### Patient Features
- Registration with role selection
- Login with lockout (5 attempts → 60 s cooldown)
- Session idle timeout with automatic logout
- Guided 5-region scan session (forehead, left cheek, right cheek, chin, nose)
- Single-shot scan tab (full face)
- AI severity grading (Cook scale 0–8) with lesion overlay
- Scan history with severity trend charts
- Scan-to-scan comparison
- PDF report generation
- Share scan/report with dermatologist
- In-app messaging with dermatologist
- Daily scan reminder notifications
- View prescriptions and treatment plans from dermatologist
- Change password, edit profile, privacy data controls

### Dermatologist Features
- Dermatologist-scoped dashboard
- View all patients who have shared data
- Patient profile: medical history, scan history, severity results, doctor notes
- Add clinical notes to individual scans
- Create / update prescriptions
- Create / update treatment plans
- Reply to patient messages
- PDF report export of patient data

### Admin Features
- Admin console (restricted to `admin` role)
- User account management (activate / deactivate)
- User role management
- Messaging restriction controls (mute/unmute users)
- Audit log review
- Break-glass emergency access (reason required, time-limited, read-only, auto-revoke on expiry)
- Logout confirmation prompt

---

## 15. Thesis Diagrams & Documentation

All diagrams are in `thesis-docs/diagrams/`:

| File | Type | Description |
|------|------|-------------|
| `patient_flow_a.drawio` | Draw.io | Patient flow — Authentication and Scan (Part A) |
| `patient_flow_b.drawio` | Draw.io | Patient flow — Report and Consultation (Part B) |
| `dermatologist_flow_a.drawio` | Draw.io | Dermatologist flow — Login and Patient Access (Part A) |
| `dermatologist_flow_b.drawio` | Draw.io | Dermatologist flow — Review and Action (Part B) |
| `admin_flow_a.drawio` | Draw.io | Admin flow — Login and Account Management (Part A) |
| `admin_flow_b.drawio` | Draw.io | Admin flow — Audit Review and Break-Glass (Part B) |
| `system_usecase.puml` | PlantUML | Full system use case diagram |
| `database_erd.mmd` | Mermaid | Entity Relationship Diagram |
| `architecture_diagram.puml` | PlantUML | System architecture |
| `seq_scan_analysis.puml` | PlantUML | Scan analysis sequence diagram |
| `seq_authentication.puml` | PlantUML | Authentication sequence diagram |
| `trust_boundary_dfd.puml` | PlantUML | Data Flow Diagram with trust boundaries |

**Screenshots:** `thesis-docs/screenshots/`
- `welcome_screen.png` — App welcome screen (390×844 px)
- `logout_prompt.png` — Sign out confirmation dialog

**Testing documentation:** `thesis-docs/testing/`
- `functional_testing.md`
- `security_testing.md`
- `security_assessment.md`
- `compatibility_testing.md`
- `admin_functional_testing.md`

---

*DermaTrack v0.8.1 — Thesis Project, Mapúa University*  
*Framework: Flutter + Supabase | AI: Roboflow + Hugging Face*
