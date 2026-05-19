import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_shell.dart';
import 'screens/welcome_screen.dart';
import 'services/auth_service.dart';
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
  // default light theme on launch when the user previously picked dark.
  await ThemeController.instance.init();

  // Initialize Supabase. If the keys weren't passed in, log loudly and
  // continue — the AuthService will surface a clear error if anyone tries
  // to use it without an initialized client.
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    debugPrint(
      'WARNING: SUPABASE_URL or SUPABASE_ANON_KEY not provided via '
      '--dart-define. Auth and database calls will fail. See main.dart.',
    );
  } else {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  runApp(const DermaTrackApp());
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
    return AuthService.instance.isSignedIn
        ? const HomeShell()
        : const WelcomeScreen();
  }
}
