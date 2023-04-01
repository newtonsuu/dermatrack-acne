import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// DermaTrack wordmark — icon tile + brand name.
/// Used on the login, register, and forgot-password screens.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: size,
          width: size,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(size / 3.6),
          ),
          child: Icon(
            Icons.face_retouching_natural,
            color: Colors.white,
            size: size * 0.55,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'DermaTrack',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
