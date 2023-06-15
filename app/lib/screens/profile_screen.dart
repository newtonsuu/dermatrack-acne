import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/patient_history.dart';
import '../models/scan.dart';
import '../services/auth_service.dart';
import '../services/patient_history_service.dart';
import '../services/profile_service.dart';
import '../services/scan_reminder_service.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_thumbnail.dart';
import '../widgets/skin_summary_card.dart';
import '../widgets/user_avatar_action.dart';
import 'gallery_screen.dart';
import 'patient_history/patient_history_screen.dart';
import 'scan_detail_screen.dart';

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
    // ProfileService drives the profile picture / display name; ScanService
    // drives the recent-scans row; PatientHistoryService drives the
    // medical-history card. Listen to all three so any update rebuilds.
    ProfileService.instance.addListener(_onProfileChanged);
    ScanService.instance.addListener(_onProfileChanged);
    PatientHistoryService.instance.addListener(_onProfileChanged);
    ScanReminderService.instance.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    ProfileService.instance.removeListener(_onProfileChanged);
    ScanService.instance.removeListener(_onProfileChanged);
    PatientHistoryService.instance.removeListener(_onProfileChanged);
    ScanReminderService.instance.removeListener(_onProfileChanged);
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
    final allScans = ScanService.instance.scans;
    final recentScans = ScanService.instance.recentScans();

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
          // Skin summary card sits below the header — first-time users
          // (no scans yet) don't see it; after the first scan it appears
          // and starts taking shape as more days come in.
          if (allScans.isNotEmpty) ...[
            const SizedBox(height: 16),
            SkinSummaryCard(scans: allScans),
          ],
          const SizedBox(height: 16),
          _PatientHistoryCard(
            history: PatientHistoryService.instance.history,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PatientHistoryScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _DailyReminderCard(
            enabled: ScanReminderService.instance.enabled,
            hour: ScanReminderService.instance.hour,
            minute: ScanReminderService.instance.minute,
            permissionGranted: ScanReminderService.instance.permissionGranted,
            onToggle: (next) async {
              try {
                await ScanReminderService.instance.setEnabled(next);
                if (!mounted) return;
                final actuallyEnabled =
                    ScanReminderService.instance.enabled;
                if (next && !actuallyEnabled) {
                  // Toggle bounced off because permission was denied.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Notification permission denied. Enable it in '
                          'system settings to use daily reminders.'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                } else if (actuallyEnabled) {
                  final h = ScanReminderService.instance.hour;
                  final m = ScanReminderService.instance.minute;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Daily reminder set for ${_formatTime(h, m)}.'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Couldn't update reminder: $e")),
                );
              }
            },
            onPickTime: () async {
              final initial = TimeOfDay(
                hour: ScanReminderService.instance.hour,
                minute: ScanReminderService.instance.minute,
              );
              final picked = await showTimePicker(
                context: context,
                initialTime: initial,
              );
              if (picked != null && mounted) {
                try {
                  await ScanReminderService.instance
                      .setTime(picked.hour, picked.minute);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Reminder time updated to ${_formatTime(picked.hour, picked.minute)}.'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Couldn't update time: $e")),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 16),
          _ShareWithDoctorCard(
            value: ProfileService.instance.sharedWithDoctor,
            onChanged: (next) async {
              try {
                await ProfileService.instance.setSharedWithDoctor(next);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(next
                        ? 'Sharing turned on — your dermatologist can now see your scans.'
                        : 'Sharing turned off — your dermatologist no longer has access.'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not update sharing: $e')),
                );
              }
            },
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

/// Formats `hour24:minute` as a 12-hour clock string (e.g. "9:00 AM").
/// Kept top-level (private to the file) so the build closure and the
/// [_DailyReminderCard] widget can share it.
String _formatTime(int hour24, int minute) {
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final h12 = (hour24 % 12 == 0) ? 12 : hour24 % 12;
  final mm = minute.toString().padLeft(2, '0');
  return '$h12:$mm $period';
}

/// Profile-screen card for the daily scan reminder. Switch toggles the
/// reminder on or off; tapping the time row opens a time picker for
/// choosing when the reminder fires.
///
/// Handles the OS-permission edge cases via [permissionGranted]: when
/// the user enables the toggle and the OS denies notifications, the
/// service flips the toggle back off and we show a "go enable in
/// settings" hint here. Distinct from the toggle being plain off.
class _DailyReminderCard extends StatelessWidget {
  const _DailyReminderCard({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.permissionGranted,
    required this.onToggle,
    required this.onPickTime,
  });

  final bool enabled;
  final int hour;
  final int minute;
  final bool? permissionGranted;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final permissionDenied = permissionGranted == false;
    final iconColor = enabled ? AppTheme.primary : AppTheme.textSecondary(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (enabled
                            ? AppTheme.primary
                            : AppTheme.textSecondary(context))
                        .withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.notifications_active_outlined,
                      color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily scan reminder',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        enabled
                            ? 'A gentle reminder every day so your scan history stays consistent.'
                            : 'Turn this on to get a daily nudge at a time that works for you.',
                        style: TextStyle(
                          color: AppTheme.textSecondary(context),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: onToggle,
                  activeColor: AppTheme.primary,
                ),
              ],
            ),
            // Time row — only visible when the reminder is on.
            if (enabled) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onPickTime,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 18,
                          color: AppTheme.textSecondary(context)),
                      const SizedBox(width: 10),
                      Text(
                        'Remind me at',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(hour, minute),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.edit_outlined,
                          size: 16,
                          color: AppTheme.textSecondary(context)),
                    ],
                  ),
                ),
              ),
            ] else if (permissionDenied) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8, bottom: 8),
                child: Text(
                  'Notification permission is off — enable it for DermaTrack '
                  'in your phone\'s Settings → Apps to turn this on.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.red.shade400,
                    height: 1.4,
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Profile-screen card for the patient's medical history. Shows a
/// completion badge ("Not started" / "Demographics only" / etc.) and
/// links into the [PatientHistoryScreen] form when tapped.
class _PatientHistoryCard extends StatelessWidget {
  const _PatientHistoryCard({required this.history, required this.onTap});

  final PatientHistory? history;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completion = history?.completion ?? PatientHistoryCompletion.notStarted;
    final (badgeText, badgeColor) = _badgeFor(completion);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment_outlined,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medical history',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitleFor(completion),
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: badgeColor.withValues(alpha: 0.4), width: 1),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary(context), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleFor(PatientHistoryCompletion c) {
    switch (c) {
      case PatientHistoryCompletion.notStarted:
        return 'Tell your dermatologist about your medical background — '
            'helps her understand what might be driving your acne.';
      case PatientHistoryCompletion.demographicsOnly:
        return "We've got your basics. Add medical history when you're "
            'ready.';
      case PatientHistoryCompletion.clinicalOnly:
        return 'Clinical sections are filled. Add your demographics next.';
      case PatientHistoryCompletion.complete:
        return 'Your dermatologist sees this when sharing is on.';
    }
  }

  (String, Color) _badgeFor(PatientHistoryCompletion c) {
    switch (c) {
      case PatientHistoryCompletion.notStarted:
        return ('Not started', const Color(0xFF9E9E9E));
      case PatientHistoryCompletion.demographicsOnly:
        return ('Demographics only', const Color(0xFFFFC107));
      case PatientHistoryCompletion.clinicalOnly:
        return ('Clinical only', const Color(0xFFFFC107));
      case PatientHistoryCompletion.complete:
        return ('Complete', const Color(0xFF4CAF50));
    }
  }
}

/// Opt-in card that controls whether the demo doctor account can read this
/// user's scans. Wired to ProfileService.setSharedWithDoctor — the parent
/// handles success/failure snackbars.
///
/// DEMO ONLY copy. When we replace the hardcoded-doctor model with proper
/// patient↔doctor linking, this card becomes the "Connect with my
/// dermatologist" flow (search → invite → consent), and the description
/// here gets rewritten to match.
class _ShareWithDoctorCard extends StatelessWidget {
  const _ShareWithDoctorCard({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final iconColor = value ? AppTheme.primary : AppTheme.textSecondary(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (value ? AppTheme.primary : AppTheme.textSecondary(context))
                    .withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.medical_services_outlined,
                  color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share with my dermatologist',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value
                        ? 'Your dermatologist can view your scan history, severity trend, and analysis details. Notes stay private.'
                        : 'Off — only you can see your scans. Turn this on to let your dermatologist view your progress between visits.',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.primary,
            ),
          ],
        ),
      ),
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
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ScanDetailScreen(scan: scans[index]),
              ),
            ),
          );
        },
      ),
    );
  }
}
