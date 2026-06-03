import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';

/// Break-glass emergency access. An admin opens a **time-limited, read-only**
/// session against a specific patient, with a required reason — every use is
/// recorded in the audit log for review. After opening, the admin can view the
/// patient's scan trend (metadata only) until the session expires or is
/// revoked.
class BreakGlassScreen extends StatefulWidget {
  const BreakGlassScreen({super.key, this.presetPatient});

  /// Pre-selected patient (when launched from the user-management sheet).
  final AdminUser? presetPatient;

  @override
  State<BreakGlassScreen> createState() => _BreakGlassScreenState();
}

class _BreakGlassScreenState extends State<BreakGlassScreen> {
  static const _danger = Color(0xFFE53935);

  AdminUser? _patient;
  final _reasonController = TextEditingController();
  int _duration = 15;
  bool _confirmed = false;
  bool _busy = false;

  BreakGlassSession? _opened;
  List<Map<String, dynamic>>? _records;
  String? _recordsError;

  @override
  void initState() {
    super.initState();
    _patient = widget.presetPatient;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _canGrant =>
      !_busy &&
      _patient != null &&
      _reasonController.text.trim().isNotEmpty &&
      _confirmed;

  Future<void> _grant() async {
    if (!_canGrant) return;
    setState(() => _busy = true);
    try {
      final session = await AdminService.instance.openBreakGlass(
        patient: _patient!,
        reason: _reasonController.text,
        durationMinutes: _duration,
      );
      // Load the records under the freshly-opened session.
      List<Map<String, dynamic>>? records;
      String? err;
      try {
        records = await AdminService.instance.loadPatientScans(_patient!.id);
      } catch (e) {
        err = '$e';
      }
      if (!mounted) return;
      setState(() {
        _opened = session;
        _records = records;
        _recordsError = err;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open emergency access: $e')),
      );
    }
  }

  Future<void> _revoke() async {
    final s = _opened;
    if (s == null) return;
    setState(() => _busy = true);
    try {
      await AdminService.instance.revokeBreakGlass(s);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Revoke failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Break-glass access')),
      body: _opened == null ? _buildForm() : _buildActive(),
    );
  }

  Widget _buildForm() {
    final patients = AdminService.instance.patients;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // Warning banner.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _danger.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This emergency access will be logged and reviewed. Access is '
                  'read-only and expires automatically.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppTheme.textPrimary(context)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Patient', style: _labelStyle(context)),
        const SizedBox(height: 6),
        if (widget.presetPatient != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(widget.presetPatient!.username),
              subtitle: const Text('Selected patient'),
            ),
          )
        else
          DropdownButtonFormField<AdminUser>(
            initialValue: _patient,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Select a patient (by user ID / username)',
            ),
            items: [
              for (final p in patients)
                DropdownMenuItem(value: p, child: Text(p.username)),
            ],
            onChanged: (v) => setState(() => _patient = v),
          ),
        const SizedBox(height: 18),
        Text('Reason for access', style: _labelStyle(context)),
        const SizedBox(height: 6),
        TextField(
          controller: _reasonController,
          maxLines: 3,
          minLines: 2,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Why is emergency access needed?',
          ),
        ),
        const SizedBox(height: 18),
        Text('Access duration', style: _labelStyle(context)),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 15, label: Text('15 min')),
            ButtonSegment(value: 30, label: Text('30 min')),
            ButtonSegment(value: 60, label: Text('1 hour')),
          ],
          selected: {_duration},
          onSelectionChanged: (s) => setState(() => _duration = s.first),
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v ?? false),
          activeColor: _danger,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I understand this access is logged, time-limited, and read-only.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _canGrant ? _grant : null,
          style: FilledButton.styleFrom(
            backgroundColor: _danger,
            minimumSize: const Size.fromHeight(50),
          ),
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.lock_open),
          label: const Text('Grant emergency access'),
        ),
      ],
    );
  }

  Widget _buildActive() {
    final s = _opened!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _danger.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_open, color: _danger),
                  const SizedBox(width: 8),
                  Text('Emergency access active',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context))),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Patient: ${_patient!.username}\n'
                'Expires: ${_fmtTime(s.expiresAt)} (${s.durationMinutes} min)\n'
                'Read-only. This session is recorded in the audit log.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppTheme.textSecondary(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Patient scan records (read-only)', style: _labelStyle(context)),
        const SizedBox(height: 8),
        if (_recordsError != null)
          Text('Could not load records: $_recordsError',
              style: const TextStyle(color: _danger, fontSize: 12.5))
        else if (_records == null)
          const Center(child: CircularProgressIndicator())
        else if (_records!.isEmpty)
          Text('This patient has no scans.',
              style: TextStyle(color: AppTheme.textSecondary(context)))
        else
          ..._records!.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.image_outlined),
                  title: Text(
                      '${_regionLabel(r['region'] as String?)} · ${r['severity_label'] ?? '—'}'),
                  subtitle: Text(
                    '${_fmtTime(DateTime.tryParse(r['taken_at'] as String? ?? '') ?? DateTime.now())} · '
                    'Cook ${r['cook_grade'] ?? '—'} · '
                    'Inf ${r['inflammatory_count'] ?? 0} / Non ${r['non_inflammatory_count'] ?? 0}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _busy ? null : _revoke,
          style: OutlinedButton.styleFrom(
            foregroundColor: _danger,
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Revoke access now'),
        ),
      ],
    );
  }

  TextStyle _labelStyle(BuildContext context) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary(context),
      );

  static String _regionLabel(String? wire) {
    switch (wire) {
      case 'forehead':
        return 'Forehead';
      case 'left_cheek':
        return 'Left cheek';
      case 'right_cheek':
        return 'Right cheek';
      case 'chin':
        return 'Chin';
      case 'nose':
        return 'Nose';
      default:
        return 'Full face';
    }
  }

  static String _fmtTime(DateTime t) {
    final l = t.toLocal();
    final h12 = l.hour == 0 ? 12 : (l.hour > 12 ? l.hour - 12 : l.hour);
    final ampm = l.hour < 12 ? 'AM' : 'PM';
    return '${l.month}/${l.day} $h12:${l.minute.toString().padLeft(2, '0')} $ampm';
  }
}
