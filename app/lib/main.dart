import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/doctor/doctor_shell.dart';
import 'screens/home_shell.dart';
import 'screens/welcome_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_center_service.dart';
import 'services/notification_prefs_service.dart';
import 'services/scan_reminder_service.dart';
import 'services/security_activity_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// Supabase project credentials.
///
/// Provided at build time via --dart-define so the keys never live in the
/// repo. Example run command:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// The anon key is safe to embed in a client app — RLS policies in the
/// database enforce per-user access. NEVER pass the service_role key here.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the persisted theme choice before runApp so we don't flash the
  // default light theme on launch. Bounded with a timeout so a slow storage
  // read can never hold the splash screen.
  try {
    await ThemeController.instance.init().timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('ThemeController.init failed/slow: $e');
  }

  // Initialize Supabase before the first frame so AuthService has a client,
  // but bound it: a network stall must not pin the app on the splash screen
  // forever. If it times out, the app still launches and surfaces a clear
  // connectivity error rather than hanging on the logo.
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    debugPrint(
      'WARNING: SUPABASE_URL or SUPABASE_ANON_KEY not provided via '
      '--dart-define. Auth and database calls will fail. See main.dart.',
    );
  } else {
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Supabase.initialize failed/slow: $e');
    }
  }

  runApp(const DermaTrackApp());

  // Boot the scan-reminder service AFTER the UI is up. It initializes the
  // local-notifications + timezone plugins, which can be slow (or hang on
  // platforms without an implementation) — doing it before runApp was what
  // could leave the app stuck on the splash logo. It's best-effort and only
  // needs to be ready before the user toggles a reminder, so we fire it in
  // the background and never block first paint on it.
  ScanReminderService.instance.initialize().catchError((Object e) {
    debugPrint('ScanReminderService.initialize failed: $e');
  });

  // Notification preferences + the in-app Notification Center feed. Both are
  // best-effort and synthesize/read from already-loaded data, so they never
  // block first paint. The center listens to prefs + data services and
  // rebuilds itself as those change.
  NotificationPrefsService.instance.init().catchError((Object e) {
    debugPrint('NotificationPrefsService.init failed: $e');
  });
  NotificationCenterService.instance.init().catchError((Object e) {
    debugPrint('NotificationCenterService.init failed: $e');
  });
  SecurityActivityService.instance.init().catchError((Object e) {
    debugPrint('SecurityActivityService.init failed: $e');
  });
}

class DermaTrackApp extends StatefulWidget {
  const DermaTrackApp({super.key});

  @override
  State<DermaTrackApp> createState() => _DermaTrackAppState();
}

class _DermaTrackAppState extends State<DermaTrackApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DermaTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeController.instance.mode,
      home: const _AuthGate(),
    );
  }
}

/// Watches the auth service and routes between the welcome screen and the
/// main app shell. When you swap the stub for Supabase, this gate keeps
/// working as-is.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    if (!auth.isSignedIn) return const WelcomeScreen();
    // Demo doctor account routes to the read-only doctor shell. Everyone else
    // gets the normal patient experience.
    if (auth.isDoctor) return const DoctorShell();
    return const HomeShell();
  }
}
