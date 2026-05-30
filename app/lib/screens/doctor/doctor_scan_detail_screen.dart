import 'package:flutter/material.dart';

import '../../models/scan.dart';
import '../../services/doctor_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lesion_overlay.dart';

/// Read-only scan detail view for the demo doctor account.
///
/// Mirrors the layout of the patient-side ScanDetailScreen but:
///   - no edit-notes action (the doctor sees the patient's note labelled
///     accordingly, but cannot change it)
///   - no delete action (the doctor must not be able to mutate a patient's
///     record — RLS already enforces this, but we remove the UI too)
///   - reads its Scan from DoctorService's per-patient cache, so opening the
///     same scan again is instant
///
/// Per-class lesion drill-down is intentionally omitted from the v1 doctor
/// view — the assumption is the dermatologist already knows the lesion
/// classes by name. We can fold it back in if Monday's feedback asks for it.
class DoctorScanDetailScreen extends StatefulWidget {
  const DoctorScanDetailScreen({
    super.key,
    required this.patient,
    required this.scan,
  });

  final DoctorPatient patient;
  final Scan scan;

  @override
  State<DoctorScanDetailScreen> createState() => _DoctorScanDetailScreenState();
}

class _DoctorScanDetailScreenState extends State<DoctorScanDetailScreen> {
  bool _isSavingNote = false;

  @override
  void initState() {
    super.initState();
    DoctorService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    DoctorService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Pulls the freshest copy of this screen's scan from DoctorService — so
  /// if the doctor pulls-to-refresh the patient detail screen, this screen
  /// reflects any updated fields without a navigation round-trip. Falls
  /// back to the constructor scan if the id has dropped out of the cache.
  Scan get _scan {
    final fromService = DoctorService.instance.scansFor(widget.patient.id);
    for (final s in fromService) {
      if (s.id == widget.scan.id) return s;
    }
    return widget.scan;
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text(_titleFor(scan)),
        // No delete action — read-only by design and by RLS.
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LesionOverlay(
              imageUrl: scan.imageUrl,
              lesions: scan.lesions,
            ),
            const SizedBox(height: 14),
            _GradeHeader(scan: scan),
            const SizedBox(height: 16),
            _CountsRow(scan: scan),
            const SizedBox(height: 20),
            _PatientNoteCard(note: scan.notes),
            const SizedBox(height: 12),
            _DoctorNoteCard(
              note: scan.doctorNote,
              isSaving: _isSavingNote,
              onEdit: _editDoctorNote,
            ),
            const SizedBox(height: 16),
            if (scan.analysisDetails != null) ...[
              _AnalysisCard(details: scan.analysisDetails!),
              const SizedBox(height: 16),
            ],
            _MetadataCard(scan: scan, patient: widget.patient),
          ],
        ),
      ),
    );
  }

  String _titleFor(Scan scan) {
    final d = scan.takenAt;
    return 'Scan · ${d.year}-${_2(d.month)}-${_2(d.day)}';
  }

  static String _2(int n) => n.toString().padLeft(2, '0');

  /// Opens an edit dialog pre-filled with the existing doctor note (if any).
  /// "Clear" appears when a note exists. Returns:
  ///   - null  → dialog dismissed without saving (no-op)
  ///   - ''    → "Clear" was tapped, or Save with blank text → delete the note
  ///   - text  → upsert the note
  Future<void> _editDoctorNote() async {
    if (_isSavingNote) return;
    final scan = _scan;
    final current = scan.doctorNote ?? '';
    final controller = TextEditingController(text: current);

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current.isEmpty ? "Add doctor's note" : "Edit doctor's note"),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText:
                'Clinical observation for the patient — e.g. lesion type '
                'distribution, recommended OTC routine, or what to track '
                'before the next scan.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          if (current.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
              child: const Text('Clear'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    setState(() => _isSavingNote = true);
    try {
      await DoctorService.instance.setDoctorNote(
        patientId: widget.patient.id,
        scanId: widget.scan.id,
        note: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.trim().isEmpty
              ? 'Note cleared. The patient will no longer see it.'
              : 'Note saved. The patient will see it on this scan.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save note: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSavingNote = false);
    }
  }
}

class _GradeHeader extends StatelessWidget {
  const _GradeHeader({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scan.severityColor.withValues(alpha: 0.18),
                border:
                    Border.all(color: scan.severityColor, width: 2),
                shape: BoxShape.circle,
              ),
              child: Text(
                scan.cookGrade < 0 ? '−' : scan.cookGrade.toString(),
                style: TextStyle(
                  color: scan.severityColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scan.severityLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    scan.cookGrade < 0
                        ? 'Classifier: clear skin'
                        : 'Cook grade ${scan.cookGrade} (0–8 scale)',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary(context),
                    ),
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

class _CountsRow extends StatelessWidget {
  const _CountsRow({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CountCard(
            label: 'Inflammatory',
            value: scan.inflammatoryCount,
            color: const Color(0xFFF44336),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CountCard(
            label: 'Non-inflam.',
            value: scan.nonInflammatoryCount,
            color: const Color(0xFFFFC107),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CountCard(
            label: 'Post-acne',
            value: scan.postAcneCount,
            color: const Color(0xFF9E9E9E),
          ),
        ),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientNoteCard extends StatelessWidget {
  const _PatientNoteCard({required this.note});
  final String? note;

  @override
  Widget build(BuildContext context) {
    final hasNote = note != null && note!.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sticky_note_2_outlined,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  "Patient's note",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasNote ? note!.trim() : 'No note on this scan.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: hasNote
                    ? AppTheme.textPrimary(context)
                    : AppTheme.textSecondary(context),
                fontStyle: hasNote ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editable card for the dermatologist's own note on this scan. Tap "Add"
/// when empty, "Edit" when populated. The card uses the accent color so
/// it's visually distinct from the patient's note card right above it.
class _DoctorNoteCard extends StatelessWidget {
  const _DoctorNoteCard({
    required this.note,
    required this.isSaving,
    required this.onEdit,
  });

  final String? note;
  final bool isSaving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasNote = note != null && note!.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medical_services_outlined,
                    color: AppTheme.accent, size: 18),
                const SizedBox(width: 8),
                // Wrapped in Expanded so a long title (or a phone with a
                // smaller text scale) can ellipsize instead of overflowing
                // the row and pushing the Edit button off the right edge.
                Expanded(
                  child: Text(
                    "Your note (visible to the patient)",
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: isSaving ? null : onEdit,
                  icon: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          hasNote ? Icons.edit_outlined : Icons.add,
                          size: 16,
                        ),
                  label: Text(hasNote ? 'Edit' : 'Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                hasNote
                    ? note!.trim()
                    : 'No note on this scan yet. Tap Add to leave a clinical observation the patient will see.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: hasNote
                      ? AppTheme.textPrimary(context)
                      : AppTheme.textSecondary(context),
                  fontStyle: hasNote ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.details});
  final AnalysisDetails details;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Analysis details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _kv(context, 'Detection model', details.detectionModel),
            _kv(context, 'Detection grade',
                'Cook ${details.detectionCookGrade}'),
            _kv(context, 'Conf. threshold',
                (details.confidenceThreshold).toStringAsFixed(2)),
            if (details.hasClassifier) ...[
              const Divider(height: 18),
              _kv(context, 'Classifier model',
                  details.classifierModel ?? '—'),
              if (details.classifierTopLabel != null)
                _kv(context, 'Classifier label',
                    details.classifierTopLabel!),
              if (details.classifierTopConfidence != null)
                _kv(context, 'Classifier conf.',
                    details.classifierTopConfidence!.toStringAsFixed(2)),
            ],
            const SizedBox(height: 8),
            Text(
              'Final grade rationale: ${details.combinerRationale.replaceAll('_', ' ')}',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              key,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textPrimary(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.scan, required this.patient});

  final Scan scan;
  final DoctorPatient patient;

  @override
  Widget build(BuildContext context) {
    final taken = scan.takenAt;
    final dateStr =
        '${taken.year}-${_2(taken.month)}-${_2(taken.day)} ${_2(taken.hour)}:${_2(taken.minute)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Scan metadata',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _row(context, 'Patient', patient.displayLabel),
            _row(context, 'Taken at', dateStr),
            _row(context, 'Scan ID', scan.id),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              key,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textPrimary(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _2(int n) => n.toString().padLeft(2, '0');
}
