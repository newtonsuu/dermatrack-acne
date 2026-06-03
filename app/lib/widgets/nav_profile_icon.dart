import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';

/// Bottom-navigation icon for the Profile tab. Shows the user's profile photo
/// when one is set, otherwise their initials on a brand-colored circle.
/// Listens to [ProfileService] (photo) and [AuthService] (name) so it updates
/// live when the avatar or display name changes.
class NavProfileIcon extends StatefulWidget {
  const NavProfileIcon({super.key, required this.selected});

  /// Whether this tab is the active one (adds a brand-colored ring).
  final bool selected;

  @override
  State<NavProfileIcon> createState() => _NavProfileIconState();
}

class _NavProfileIconState extends State<NavProfileIcon> {
  @override
  void initState() {
    super.initState();
    ProfileService.instance.addListener(_onChange);
    AuthService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    ProfileService.instance.removeListener(_onChange);
    AuthService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String get _initials {
    final name = AuthService.instance.currentUser?.displayName.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = ProfileService.instance.profilePictureUrl;
    const size = 26.0;
    final ring = widget.selected ? AppTheme.primary : Colors.transparent;

    return Container(
      width: size + 4,
      height: size + 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 2),
      ),
      child: ClipOval(
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initialsCircle(),
              )
            : _initialsCircle(),
      ),
    );
  }

  Widget _initialsCircle() {
    return Container(
      color: AppTheme.primary,
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
