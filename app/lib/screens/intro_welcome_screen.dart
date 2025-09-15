import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import 'welcome_screen.dart';

/// Branded landing / welcome screen — the first thing a signed-out user sees.
///
/// Introduces DermaTrack (brand, tagline, the monitoring-support framing) and
/// leads into the "Login as" access-type selection ([WelcomeScreen]) via the
/// Get Started button.
class IntroWelcomeScreen extends StatelessWidget {
  const IntroWelcomeScreen({super.key});

  void _continue(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primary.withValues(alpha: 0.10),
              AppTheme.background(context),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Center(child: BrandLogo(size: 108)),
                    const SizedBox(height: 28),
                    Text(
                      'Welcome to DermaTrack',
                      style: Theme.of(context).textTheme.headlineLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Track your facial acne severity, day by day.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppTheme.textSecondary(context),
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    const _Highlight(
                      icon: Icons.camera_alt_outlined,
                      text: 'Scan your skin and get a Mild / Moderate / Severe '
                          'reading with guidance.',
                    ),
                    const SizedBox(height: 14),
                    const _Highlight(
                      icon: Icons.timeline_outlined,
                      text: 'Follow your progress over time with history and '
                          'trends.',
                    ),
                    const SizedBox(height: 14),
                    const _Highlight(
                      icon: Icons.medical_services_outlined,
                      text: 'Share with a dermatologist for review — only with '
                          'your consent.',
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () => _continue(context),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Get Started'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => _continue(context),
                      child: const Text('I already have an account'),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'For monitoring support only — not a medical diagnosis.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.textSecondary(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: AppTheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
