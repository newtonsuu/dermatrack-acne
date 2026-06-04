import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet that lets a role-switchable account (`canSwitchRoles`) change
/// its active role between Patient / Doctor / Admin. On selection it calls
/// [AuthService.switchRole]; the AuthGate then re-routes to the matching shell.
/// Only show this from entry points already guarded by `canSwitchRoles`.
Future<void> showRoleSwitcher(BuildContext context) async {
  final auth = AuthService.instance;
  final messenger = ScaffoldMessenger.of(context);
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Switch role',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          for (final r in UserRole.values)
            ListTile(
              leading: Icon(_iconFor(r), color: AppTheme.primary),
              title: Text(_labelFor(r)),
              trailing: auth.role == r
                  ? Icon(Icons.check, color: AppTheme.primary)
                  : null,
              onTap: () async {
                Navigator.of(ctx).pop();
                if (r == auth.role) return;
                try {
                  await auth.switchRole(r);
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Could not switch role: $e')));
                }
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

IconData _iconFor(UserRole r) {
  switch (r) {
    case UserRole.patient:
      return Icons.person_outline;
    case UserRole.doctor:
      return Icons.medical_services_outlined;
    case UserRole.admin:
      return Icons.admin_panel_settings_outlined;
  }
}

String _labelFor(UserRole r) {
  switch (r) {
    case UserRole.patient:
      return 'Patient';
    case UserRole.doctor:
      return 'Doctor';
    case UserRole.admin:
      return 'Admin';
  }
}
