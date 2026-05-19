import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/scan.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_thumbnail.dart';
import '../widgets/user_avatar_action.dart';
import 'gallery_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    ProfileService.instance.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    ProfileService.instance.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openPictureSheet() async {
    final hasPicture = ProfileService.instance.profilePictureUrl != null;
    final action = await showModalBottomSheet<_PictureAction>(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: AppTheme.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppTheme.primary),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop(_PictureAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.primary),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(_PictureAction.gallery),
            ),
            if (hasPicture)
              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: Colors.red.shade600),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: Colors.red.shade600),
                ),
                onTap: () => Navigator.of(context).pop(_PictureAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;

    switch (action) {
      case _PictureAction.camera:
        await _pickPicture(ImageSource.camera);
        break;
      case _PictureAction.gallery:
        await _pickPicture(ImageSource.gallery);
        break;
      case _PictureAction.remove:
        await ProfileService.instance.clearProfilePicture();
        break;
    }
  }

  Future<void> _pickPicture(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1000,
      );
      if (file != null) {
        // Read bytes via the XFile API so this works on web, mobile, and
        // desktop alike — dart:io's File class doesn't exist on Flutter Web.
        final bytes = await file.readAsBytes();
        await ProfileService.instance.setProfilePicture(bytes);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load image: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final pictureUrl = ProfileService.instance.profilePictureUrl;
    final recentScans = ProfileService.instance.recentScans();

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [UserAvatarAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _ProfileHeader(
            displayName: user?.displayName ?? 'DermaTrack User',
            email: user?.email ?? '',
            pictureUrl: pictureUrl,
            onEditPicture: _openPictureSheet,
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            title: 'Recent scans',
            actionLabel: 'View all',
            onAction: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GalleryScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _RecentScansRow(scans: recentScans),
        ],
      ),
    );
  }
}

enum _PictureAction { camera, gallery, remove }

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.email,
    required this.pictureUrl,
    required this.onEditPicture,
  });

  final String displayName;
  final String email;
  final String? pictureUrl;
  final VoidCallback onEditPicture;

  String get _initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _Avatar(
              pictureUrl: pictureUrl,
              initials: _initials,
              onEdit: onEditPicture,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.pictureUrl,
    required this.initials,
    required this.onEdit,
  });

  final String? pictureUrl;
  final String initials;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      width: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 72,
            width: 72,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: pictureUrl != null
                ? Image.network(
                    pictureUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _InitialsAvatar(initials),
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : _InitialsAvatar(initials),
                  )
                : _InitialsAvatar(initials),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Material(
              color: AppTheme.accent,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.camera_alt,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar(this.initials);
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: AppTheme.primary,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _RecentScansRow extends StatelessWidget {
  const _RecentScansRow({required this.scans});
  final List<Scan> scans;

  @override
  Widget build(BuildContext context) {
    if (scans.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_outlined,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'No scans yet — take your first one from the Scan tab.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 138,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: scans.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return ScanThumbnail(
            scan: scans[index],
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Scan detail for ${scans[index].id} — coming soon.',
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
