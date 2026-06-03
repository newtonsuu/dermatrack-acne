import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Pre-login landing — "Login as" access-type selection.
///
/// The first screen a signed-out user sees. They pick an access type
/// (Patient / Doctor / Admin · Break-Glass), which opens a role-themed login.
/// The selection only themes the login screen — the actual role is enforced by
/// the account in the database after sign-in (migration 0011), so picking the
/// wrong door can't grant extra access.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _login(BuildContext context,
      {required String label, required bool showRegister}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LoginScreen(accessLabel: label, showRegister: showRegister),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const BrandLogo(size: 84),
                  const SizedBox(height: 28),
                  Text(
                    'Login as',
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose how you want to sign in.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  _RoleCard(
                    icon: Icons.person_outline,
                    title: 'Patient',
                    subtitle: 'Track your skin, scans, and reminders.',
                    color: AppTheme.primary,
                    onTap: () =>
                        _login(context, label: 'Patient', showRegister: true),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    icon: Icons.medical_services_outlined,
                    title: 'Doctor',
                    subtitle: 'Review consenting patients and leave notes.',
                    color: const Color(0xFF5C6BC0),
                    onTap: () =>
                        _login(context, label: 'Doctor', showRegister: false),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Admin · Break-Glass',
                    subtitle: 'User management, audit logs, emergency access.',
                    color: const Color(0xFF7E57C2),
                    onTap: () =>
                        _login(context, label: 'Admin', showRegister: false),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'New patient?',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary(context),
                            ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const RegisterScreen()),
                        ),
                        child: const Text('Create an account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.textSecondary(context)),
            ],
          ),
        ),
      ),
    );
  }
}
