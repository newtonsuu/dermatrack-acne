# DermaTrack — Flutter App (v0.1)

Patient-facing mobile companion for longitudinal acne severity monitoring.
This is the **week-1 scaffold**: login, dashboard, profile, and camera. Auth
is stubbed; nothing talks to a backend yet.

## Prerequisites

- Flutter SDK **3.19 or newer** (`flutter --version` to check)
- Android Studio with an Android emulator, or a physical Android device with
  USB debugging on, or Xcode + iOS Simulator on macOS
- VS Code or Android Studio with the Flutter / Dart plugins

Run `flutter doctor` once — it should report no missing dependencies for the
platform you plan to target.

## First-time setup

The repo contains only the Dart source and `pubspec.yaml`. The platform
folders (`android/`, `ios/`, `web/`, etc.) need to be generated locally
once. From inside `DermaTrack/app/`:

```bash
flutter create .
flutter pub get
```

`flutter create .` is safe to run in an existing folder — it fills in the
missing platform code without overwriting your Dart files.

## Run it

```bash
# Pick a device first
flutter devices

# Then run (replace <id> with the device id from the line above)
flutter run -d <id>
```

Hot reload is `r` in the terminal; hot restart is `R`.

## What works in v1

| Screen        | Status                                                                 |
| ------------- | ---------------------------------------------------------------------- |
| Login / Signup| Stub — any valid email + password (≥6 chars) signs you in.             |
| Dashboard     | Greeting, stat placeholders, recent-scans empty state, tips.           |
| Profile       | Avatar with initials, settings list (placeholders), sign-out.          |
| Camera        | Opens system camera via `image_picker`, preview, retake / use.         |

## Project layout

```
app/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
└── lib/
    ├── main.dart              # entry point + auth gate
    ├── theme/
    │   └── app_theme.dart     # colors, text styles, component themes
    ├── services/
    │   └── auth_service.dart  # stub auth — swap for Supabase later
    └── screens/
        ├── login_screen.dart
        ├── home_shell.dart    # bottom-nav container
        ├── dashboard_screen.dart
        ├── profile_screen.dart
        └── camera_screen.dart
```

## What's next (week 2)

- Swap `AuthService` stub for real **Supabase Auth**.
- Wire image upload to **Supabase Storage**.
- Add the **Acne Grading API** integration (Dr. Bell Eapen) for severity
  scoring and lesion-type breakdown.
- Persist scan history (Supabase Postgres + RLS policies).

## Platform permissions

When you run `flutter create .`, you'll need to add camera + photo
permissions:

**Android** — `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-feature android:name="android.hardware.camera" android:required="false"/>
```

**iOS** — `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>DermaTrack uses your camera to capture skin scans.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>DermaTrack can also use a saved photo for analysis.</string>
```
