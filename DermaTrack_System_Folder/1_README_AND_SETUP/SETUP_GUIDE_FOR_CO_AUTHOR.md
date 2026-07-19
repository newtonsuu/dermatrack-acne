# DermaTrack — Setup guide for a new contributor

For a co-author setting up DermaTrack on a fresh Windows machine. Total
time end-to-end: about **2 to 3 hours** of mostly waiting on downloads
and installers, plus ~15 minutes of active config.

This guide assumes:

- **Windows 10 or 11** (Mac steps are similar but use different
  installers — note the differences inline where relevant).
- About **20 GB of free disk space** (Android SDK + Flutter + Android
  Studio together are big).
- An **Android phone with USB debugging enabled** to install and test
  the APK, OR enough RAM (8 GB+) to run an Android emulator.

If you only have what AJ gave you (the `DermaTrack` workspace folder
and the Claude memory folder) and nothing else, follow this top to bottom.

---

## Section A — Install the development tools

These are installed once and serve every Flutter project you'll ever
touch. Don't try to copy them from another machine — they register
system entries that won't survive a copy-paste. Install fresh.

### A1. Git for Windows (~5 min)

Used to download the DermaTrack code from GitHub.

1. Download from <https://git-scm.com/download/win>.
2. Run the installer.
3. Accept the defaults **except** at "Adjusting your PATH environment":
   choose **"Git from the command line and also from 3rd-party software"**.
4. After it finishes, open a new PowerShell or Command Prompt window and
   verify:
   ```
   git --version
   ```
   Should print something like `git version 2.45.0.windows.1`.

### A2. Java JDK 17 (~10 min)

Flutter's Android build chain needs Java 17 specifically. Older or
newer Java versions can cause confusing build errors.

1. Download Eclipse Temurin JDK 17 (free, open-source) from
   <https://adoptium.net/temurin/releases/?version=17>.
2. Pick the Windows x64 `.msi` installer.
3. During install, **check the box** for "Set JAVA_HOME variable" and
   "Add to PATH".
4. After it finishes, open a fresh PowerShell window and verify:
   ```
   java -version
   echo $env:JAVA_HOME
   ```
   The first should print `openjdk version "17..."` and the second
   should print the install path (e.g.
   `C:\Program Files\Eclipse Adoptium\jdk-17.0.x.x-hotspot`).

### A3. Flutter SDK (~15 min)

The framework DermaTrack is built on.

1. Download the latest stable Flutter SDK zip from
   <https://docs.flutter.dev/get-started/install/windows>.
2. **Important: do NOT extract to `C:\Program Files\`** — Windows
   permission quirks will bite you. Use a simple path instead:
   ```
   C:\src\flutter
   ```
   Create the `C:\src\` folder if it doesn't exist and extract the zip
   there. The resulting layout should be `C:\src\flutter\bin\flutter.bat`.
3. Add `C:\src\flutter\bin` to your PATH:
   - Start menu → search "environment variables" → "Edit the system
     environment variables".
   - Click **Environment Variables…**
   - Under **User variables**, select **Path** → **Edit** → **New** →
     paste `C:\src\flutter\bin` → **OK** all dialogs.
4. **Close and reopen** PowerShell so the new PATH takes effect.
5. Verify:
   ```
   flutter --version
   ```
   Should print the Flutter and Dart versions.

### A4. Android Studio (~30 min download + install)

Provides the Android SDK, build-tools, and platform-tools that Flutter
needs to compile and install APKs. You don't have to use it as your
editor — VS Code is lighter — but its install is the easiest way to get
the Android toolchain.

1. Download from <https://developer.android.com/studio>.
2. Run the installer with default options.
3. On first launch, the Setup Wizard will offer to download the latest
   Android SDK. **Accept** — you need it.
4. Once Android Studio is open, go to **More Actions → SDK Manager**
   (or **File → Settings → Languages & Frameworks → Android SDK** if a
   project is already open).
5. In the **SDK Platforms** tab, install:
   - **Android 14 (API 34)** — the current target for DermaTrack
   - **Android 13 (API 33)** — for testing on older devices
6. In the **SDK Tools** tab, make sure these are installed (most are
   on by default):
   - Android SDK Build-Tools
   - Android SDK Command-line Tools (latest)
   - Android SDK Platform-Tools
   - Android Emulator
7. Click **Apply** to download everything (~3-5 GB total, takes 15-30 min
   depending on connection).

### A5. Accept Android SDK licenses (~2 min)

Flutter won't build without these acknowledged.

```
flutter doctor --android-licenses
```

Press **y** at every prompt. There will be 5-7 of them.

### A6. Supabase CLI (~5 min)

Used to link to the DermaTrack Supabase project and apply database
migrations.

Easiest way on Windows is via **Scoop** (a package manager). If you
don't have Scoop yet, install it first:

```
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
```

Then:

```
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
```

Verify:

```
supabase --version
```

Alternative without Scoop: download the latest Windows binary from
<https://github.com/supabase/cli/releases> and put it on your PATH.

### A7. VS Code with Flutter extension (optional but recommended) (~10 min)

Lighter editor than Android Studio. Most Flutter devs use it.

1. Download from <https://code.visualstudio.com/>.
2. Install with defaults.
3. Open VS Code → **Extensions** (Ctrl+Shift+X) → search and install:
   - **Flutter** (publisher: Dart Code)
   - **Dart** (auto-installs as Flutter dependency)
   - **GitHub Pull Requests and Issues** (optional, helps with PR workflow)

### A8. Claude Desktop App

AJ mentioned this is already on the new device. If not, install from
<https://claude.ai/download>.

---

## Section B — Verify the toolchain works

Before touching DermaTrack, run Flutter's self-diagnostic:

```
flutter doctor
```

You should see check marks for:

- **Flutter** (version 3.x.x or higher)
- **Android toolchain** — develop for Android devices
- **Chrome** (if installed; not required for the Android build)
- **VS Code** or **Android Studio**
- **Connected device** (only shows if you've plugged in a phone or
  started an emulator — fine if empty for now)

If any line shows a red ✗, **stop and fix it** before continuing. The
most common issues:

- **"Android licenses not accepted"** → re-run `flutter doctor --android-licenses`
- **"Unable to find bundled Java version"** → reinstall Android Studio or
  point Flutter at your JDK: `flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-17.0.x.x-hotspot"`
- **"Android SDK at unexpected location"** → run `flutter config --android-sdk "<path>"` with your actual SDK path (usually
  `C:\Users\<you>\AppData\Local\Android\Sdk`)

---

## Section C — Get the DermaTrack code

Two paths. Pick whichever is easier.

### Option C-1 — Clone from GitHub (recommended)

```
cd C:\
mkdir dev
cd dev
git clone https://github.com/apjakilan/DermaTrack.git
cd DermaTrack
```

This puts the project at `C:\dev\DermaTrack\`. Cleaner than OneDrive
for build artifacts.

You'll also want git configured with your name and email if you plan to
commit:

```
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

### Option C-2 — Receive the workspace folder from AJ

If AJ is handing you the folder directly (USB drive, zip file), put it
at a clean path like `C:\dev\DermaTrack\` to match what most of the
guides assume. **Skip these subfolders when copying** — they're
regenerated and will only slow the transfer:

- `app\build\`
- `app\.dart_tool\`
- `app\.flutter-plugins-dependencies`

---

## Section D — Install project dependencies

From wherever you put the project, cd into the `app` folder:

```
cd C:\dev\DermaTrack\app
flutter pub get
```

This downloads every Dart/Flutter package the app needs (camera, ML Kit,
Supabase client, local notifications, etc.). Takes 1-3 minutes the
first time.

If you see errors about packages not resolving, double-check your
internet connection and rerun.

---

## Section E — Set up the Supabase credentials

DermaTrack needs two environment values to talk to the backend. AJ will
give you both privately — they should not be committed to the repo.

- `SUPABASE_URL` (looks like `https://abcd1234.supabase.co`)
- `SUPABASE_ANON_KEY` (a long `eyJ…` JWT-style string, safe to embed in
  the APK but **don't paste into commits**)

You'll pass these to every `flutter run` or `flutter build` command via
`--dart-define`. The easiest way to avoid typing them every time is to
save them in `app\dart-define.json` (gitignored) and reference them on
build, but for now just include them in the command line.

---

## Section F — Build and run the app

### F1. Pick a target device

Either:

- **Plug in your Android phone** with USB debugging enabled. The phone
  may prompt "Allow USB debugging from this computer?" → tap **Allow**.
- Or **start an Android emulator** from Android Studio's **Device
  Manager** (the icon that looks like a phone in the toolbar).

Verify the device is visible:

```
flutter devices
```

Should list your phone and/or the emulator.

### F2. First debug run (~3-5 min)

From `app\`:

```
flutter run ^
  --dart-define=SUPABASE_URL=https://your-project.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=eyJ...your-anon-key...
```

(`^` is for cmd; use `` ` `` in PowerShell, or put it all on one line.)

This compiles the app in debug mode and installs it on your device.
First run is slow because Gradle has to download about 1 GB of build
tooling. Subsequent runs are 30-60 seconds.

When it finishes, the DermaTrack icon should appear on your phone and
launch automatically.

### F3. Release build (when you want a shareable APK)

```
flutter build apk --release --split-per-abi ^
  --dart-define=SUPABASE_URL=https://your-project.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

The APK lands at:

```
app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

The arm64 file works on essentially every modern phone.

---

## Section G — Set up the Claude project memory

AJ will give you a `memory` folder. To install it:

1. Make sure the Claude app has been opened at least once on this device
   (so its app-data folder exists).
2. The path on Windows is roughly:
   ```
   C:\Users\<your-username>\AppData\Roaming\Claude\local-agent-mode-sessions\<some-id>\<another-id>\spaces\<space-id>\memory\
   ```
3. Copy the contents of AJ's `memory` folder into your equivalent path.
   (The folder names with IDs will be different on your machine; just
   match the structure as best you can.)
4. Open Claude and start a new conversation in the DermaTrack workspace
   folder. Claude should pick up the project context from the markdown
   files.

If the memory transfer doesn't land cleanly, no big deal — Claude can
read the code on this machine and reconstruct most of the context. Just
start your first conversation by telling it "this is the DermaTrack
thesis project" and it'll figure the rest out from the codebase.

---

## Section H — Verify it all works end to end

Quick sanity check:

1. **Sign in / register** in the running app. Account creation should
   succeed and you should land on the dashboard.
2. **Take a scan** (Scan tab → Quick single scan). Should upload,
   analyze, and show a severity grade within ~5-10 seconds (longer if
   the Hugging Face server is cold-starting).
3. **Check the trend chart and recent scans** — both should reflect
   your new scan immediately.

If all three work, you're set up.

---

## Common issues and fixes

**Gradle build fails with "AAPT: error: failed to open: The data is invalid"**

Stale build cache. Run:

```
flutter clean
flutter pub get
```

Then rebuild. This bites whenever native config changes (icon
regeneration, manifest edits, etc.).

**"adb: device unauthorized"**

Phone hasn't trusted your computer yet. Unplug the cable, plug back
in, look at the phone screen for the "Allow USB debugging?" prompt,
tap Allow. Check "Always allow from this computer" so it doesn't ask
again.

**"App not installed — package conflicts with existing package"**

The APK on your phone was signed with a different key than the new
build. Uninstall the old DermaTrack from your phone, then install the
new APK.

**Build takes forever / Gradle hangs**

First-ever build downloads ~1 GB of Gradle dependencies. Be patient
(give it 10 min). If it's still hanging after that, kill and rerun.

**`flutter doctor` keeps showing red ✗ for Android licenses**

Re-run `flutter doctor --android-licenses` and accept all prompts.

**Notification permission denied on Android 13+**

Phone Settings → Apps → DermaTrack → Notifications → enable.

**Daily scan reminder doesn't fire even though it's enabled**

Almost always battery optimization. Phone Settings → Apps →
DermaTrack → Battery → set to **Unrestricted**.

---

## What to ask AJ for

Before you start, get from AJ:

- ☐ `SUPABASE_URL` and `SUPABASE_ANON_KEY` (private — don't share or
   commit)
- ☐ A copy of the `memory` folder from his Claude app data
- ☐ Access to the GitHub repo at <https://github.com/apjakilan/DermaTrack>
- ☐ (When the time comes) the release keystore file and its password
   for shipping signed APKs

If you run into anything this guide doesn't cover, ping AJ or open
Claude with the DermaTrack workspace selected — Claude can read the
codebase and walk you through whatever's broken.

Good luck.
