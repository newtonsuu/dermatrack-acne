import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/scan_service.dart';
import '../services/security_activity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_widgets.dart';

/// Privacy & Data controls: privacy notice, how data is stored, doctor-sharing
/// consent, export, deleting scan records, requesting account deletion, and a
/// recent security-activity log.
class PrivacyDataScreen extends StatefulWidget {
  const PrivacyDataScreen({super.key});

  @override
  State<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends State<PrivacyDataScreen> {
  final _profile = ProfileService.instance;
  final _security = SecurityActivityService.instance;

  @override
  void initState() {
    super.initState();
    _profile.addListener(_onChange);
    _security.addListener(_onChange);
  }

  @override
  void dispose() {
    _profile.removeListener(_onChange);
    _security.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleConsent(bool value) async {
    try {
      await _profile.setSharedWithDoctor(value);
      await _security.record(
        SecurityEventType.consentChange,
        value
            ? 'You allowed your dermatologist to view your records.'
            : 'You stopped sharing your records with your dermatologist.',
      );
      _snack(value
          ? 'Your dermatologist can now review your records.'
          : 'Sharing turned off.');
    } catch (e) {
      _snack("Couldn't update sharing. Please try again.");
    }
  }

  Future<void> _exportRecords() async {
    final user = AuthService.instance.currentUser;
    final scans = ScanService.instance.scans;
    final export = <String, dynamic>{
      'exported_at': DateTime.now().toIso8601String(),
      'account': {
        'username': user?.username,
        'email': user?.email,
      },
      'scan_count': scans.length,
      'scans': [
        for (final s in scans)
          {
            'taken_at': s.takenAt.toIso8601String(),
            'region': s.region.wireName,
            'severity_label': s.severityLabel,
            'cook_grade': s.cookGrade,
            'inflammatory_count': s.inflammatoryCount,
            'non_inflammatory_count': s.nonInflammatoryCount,
            'post_acne_count': s.postAcneCount,
            if (s.notes != null && s.notes!.trim().isNotEmpty) 'notes': s.notes,
          },
      ],
    };
    final json = const JsonEncoder.withIndent('  ').convert(export);
    await Clipboard.setData(ClipboardData(text: json));
    await _security.record(
      SecurityEventType.dataExport,
      'You exported ${scans.length} scan record(s).',
    );
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Records exported'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              'Copied to your clipboard as JSON. Paste it anywhere to save '
              'your records.\n\n$json',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request account deletion'),
        content: const Text(
          'This sends a request to deactivate your account and delete your '
          'personal data (scans, history, and profile). An administrator '
          'reviews and processes deletion requests.\n\n'
          'You can also delete individual scan records yourself from '
          '“Delete scan records”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _security.record(
      SecurityEventType.deletionRequest,
      'You requested account deletion / deactivation.',
    );
    _snack('Your deletion request has been recorded for admin review.');
  }

  @override
  Widget build(BuildContext context) {
    final events = _security.events;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Privacy & data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const SettingsSectionLabel('Privacy notice'),
          const SizedBox(height: 8),
          SettingsCard(children: const [
            SettingsProse(
              'DermaTrack is a monitoring-support tool, not a medical device, '
              'and does not provide a diagnosis. Your scan photos and results '
              'belong to you and are used to track your skin over time.',
            ),
          ]),
          const SizedBox(height: 20),
          const SettingsSectionLabel('How your data is stored'),
          const SizedBox(height: 8),
          SettingsCard(children: const [
            SettingsProse(
              'Your facial scan photos are stored in private cloud storage and '
              'are never publicly accessible — the app loads them through '
              'short-lived signed links. Scan results and notes are protected '
              'by row-level security so only you (and a dermatologist you '
              'explicitly share with) can read them. All traffic between the '
              'app and the server is encrypted over HTTPS.',
            ),
          ]),
          const SizedBox(height: 20),
          const SettingsSectionLabel('Doctor access'),
          const SizedBox(height: 8),
          SettingsCard(children: [
            SettingsSwitchTile(
              icon: Icons.medical_services_outlined,
              title: 'Share my records with a dermatologist',
              subtitle:
                  'Consent for a dermatologist to review your scans, history, '
                  'and progress. You can turn this off at any time.',
              value: _profile.sharedWithDoctor,
              onChanged: (v) => _toggleConsent(v),
            ),
          ]),
          const SizedBox(height: 20),
          const SettingsSectionLabel('Your data'),
          const SizedBox(height: 8),
          SettingsCard(children: [
            SettingsTile(
              icon: Icons.download_outlined,
              title: 'Export my records',
              subtitle: 'Copy your scan history as JSON.',
              onTap: _exportRecords,
            ),
            const SettingsDivider(),
            SettingsTile(
              icon: Icons.delete_sweep_outlined,
              title: 'Delete scan records',
              subtitle: 'Choose individual scans to permanently remove.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeleteScansScreen()),
              ),
            ),
            const SettingsDivider(),
            SettingsTile(
              icon: Icons.no_accounts_outlined,
              title: 'Request account deletion',
              subtitle: 'Deactivate your account and delete your data.',
              iconColor: Colors.red.shade600,
              titleColor: Colors.red.shade600,
              onTap: _requestAccountDeletion,
            ),
          ]),
          const SizedBox(height: 20),
          const SettingsSectionLabel('Recent security activity'),
          const SizedBox(height: 8),
          SettingsCard(
            children: events.isEmpty
                ? const [
                    SettingsProse(
                      'No recent activity yet. Sign-ins, password changes, and '
                      'data actions will appear here.',
                    ),
                  ]
                : [
                    for (var i = 0; i < events.length && i < 12; i++) ...[
                      if (i > 0) const SettingsDivider(),
                      _SecurityEventTile(event: events[i]),
                    ],
                  ],
          ),
        ],
      ),
    );
  }
}

class _SecurityEventTile extends StatelessWidget {
  const _SecurityEventTile({required this.event});
  final SecurityEvent event;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: _iconFor(event.type),
      title: event.type.label,
      subtitle: '${event.description}\n${_relative(event.timestamp)}',
      onTap: null,
      trailing: const SizedBox.shrink(),
    );
  }

  static IconData _iconFor(SecurityEventType t) {
    switch (t) {
      case SecurityEventType.signIn:
        return Icons.login;
      case SecurityEventType.passwordChange:
        return Icons.password;
      case SecurityEventType.profileUpdate:
        return Icons.person_outline;
      case SecurityEventType.consentChange:
        return Icons.medical_services_outlined;
      case SecurityEventType.dataExport:
        return Icons.download_outlined;
      case SecurityEventType.dataDelete:
        return Icons.delete_outline;
      case SecurityEventType.deletionRequest:
        return Icons.no_accounts_outlined;
    }
  }

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, ${t.year}';
  }
}

/// Lets the patient select scan records and delete them permanently. Uses the
/// patient's own RLS-gated delete (ScanService.deleteScan).
class DeleteScansScreen extends StatefulWidget {
  const DeleteScansScreen({super.key});

  @override
  State<DeleteScansScreen> createState() => _DeleteScansScreenState();
}

class _DeleteScansScreenState extends State<DeleteScansScreen> {
  final Set<String> _selected = {};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    ScanService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    ScanService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _deleting) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count scan${count == 1 ? '' : 's'}?'),
        content: const Text(
          'This permanently removes the selected scans and their photos. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deleting = true);
    var deleted = 0;
    for (final id in _selected.toList()) {
      try {
        await ScanService.instance.deleteScan(id);
        deleted++;
      } catch (e) {
        debugPrint('DeleteScansScreen: failed to delete $id: $e');
      }
    }
    if (deleted > 0) {
      await SecurityActivityService.instance.record(
        SecurityEventType.dataDelete,
        'You deleted $deleted scan record(s).',
      );
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _deleting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted $deleted scan${deleted == 1 ? '' : 's'}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scans = ScanService.instance.scans;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Delete scan records'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _deleting ? null : _deleteSelected,
              child: Text(
                'Delete (${_selected.length})',
                style: TextStyle(color: Colors.red.shade600),
              ),
            ),
        ],
      ),
      body: scans.isEmpty
          ? Center(
              child: Text(
                'You have no scans to delete.',
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              itemCount: scans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final s = scans[i];
                final selected = _selected.contains(s.id);
                return CheckboxListTile(
                  value: selected,
                  activeColor: AppTheme.primary,
                  onChanged: _deleting
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _selected.add(s.id);
                            } else {
                              _selected.remove(s.id);
                            }
                          }),
                  secondary: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: s.severityColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text('${s.region.label} • ${s.severityLabel}'),
                  subtitle: Text(_formatDate(s.takenAt)),
                );
              },
            ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h12 = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $h12:${d.minute.toString().padLeft(2, '0')} $ampm';
  }
}
