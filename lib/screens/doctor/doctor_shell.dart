import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'doctor_patient_list_screen.dart';

/// Top-level shell for the demo doctor account.
///
/// Deliberately minimal: a single screen (patient list) plus a sign-out
/// affordance in the app bar. No bottom nav, no "doctor profile" tab —
/// keeps the demo focused on the patient↔doctor exchange.
///
/// Reached from main.dart's _AuthGate when AuthService.isDoctor is true.
class DoctorShell extends StatelessWidget {
  const DoctorShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Dermatologist view'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSignOut(context),
          ),
        ],
      ),
      body: const DoctorPatientListScreen(),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You\'ll be returned to the welcome screen and the patient view '
            'will reappear on the next sign-in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService.instance.signOut();
    }
  }
}
