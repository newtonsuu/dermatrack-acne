import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Reactive checklist of password rules.
///
/// Pass the current password string in and the widget will tick off each
/// requirement that the password satisfies. Pair it with a TextEditingController
/// listener in the parent so this rebuilds as the user types.
class PasswordStrengthChecklist extends StatelessWidget {
  const PasswordStrengthChecklist({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final missing = unmetPasswordRequirements(password).toSet();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.background(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password must include:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          for (final req in PasswordRequirement.values)
            _RuleRow(label: req.label, satisfied: !missing.contains(req)),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.satisfied});

  final String label;
  final bool satisfied;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            satisfied ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: satisfied ? AppTheme.primary : AppTheme.textSecondary(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: satisfied
                    ? AppTheme.textPrimary(context)
                    : AppTheme.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
