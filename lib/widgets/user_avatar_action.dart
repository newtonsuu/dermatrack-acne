import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';

/// Top-right AppBar action showing the signed-in user's avatar.
///
/// Tap opens a popup with: name + email header, Settings link, and Sign out
/// (with confirmation dialog). Reactively rebuilds when the user changes
/// their profile picture or signs in/out.
class UserAvatarAction extends StatefulWidget {
  const UserAvatarAction({super.key});

  @override
  State<UserAvatarAction> createState() => _UserAvatarActionState();
}

class _UserAvatarActionState extends State<UserAvatarAction> {
  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_refresh);
    ProfileService.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_refresh);
    ProfileService.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String get _initials {
    final name = AuthService.instance.currentUser?.displayName ?? '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Future<void> _handleSelection(String value) async {
    switch (value) {
      case 'settings':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        break;
      case 'signout':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text(
              "You'll need to sign in again to access your scans and progress.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        // Pop any pushed routes (Gallery, Settings, etc.) so the AuthGate
        // cleanly swaps to the LoginScreen with nothing sitting on top.
        Navigator.of(context).popUntil((route) => route.isFirst);
        await ProfileService.instance.clearProfilePicture();
        await AuthService.instance.signOut();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pictureUrl = ProfileService.instance.profilePictureUrl;
    final user = AuthService.instance.currentUser;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: 'Account menu',
        position: PopupMenuPosition.under,
        offset: const Offset(-8, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppTheme.border(context)),
        ),
        onSelected: _handleSelection,
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.displayName ?? 'DermaTrack User',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'settings',
            child: Row(
              children: [
                Icon(Icons.settings_outlined,
                    size: 20, color: AppTheme.primary),
                SizedBox(width: 12),
                Text('Settings'),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'signout',
            child: Row(
              children: [
                Icon(Icons.logout, size: 20, color: Colors.red.shade600),
                const SizedBox(width: 12),
                Text(
                  'Sign out',
                  style: TextStyle(color: Colors.red.shade600),
                ),
              ],
            ),
          ),
        ],
        child: SizedBox(
          height: 36,
          width: 36,
          child: ClipOval(
            child: pictureUrl != null
                ? Image.network(
                    pictureUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _InitialsCircle(_initials),
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : _InitialsCircle(_initials),
                  )
                : _InitialsCircle(_initials),
          ),
        ),
      ),
    );
  }
}

class _InitialsCircle extends StatelessWidget {
  const _InitialsCircle(this.initials);
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primary,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
