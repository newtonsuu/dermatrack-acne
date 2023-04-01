import 'package:flutter/material.dart';

import '../data/acne_references.dart';
import '../models/acne_reference.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/lesion_overlay.dart';

/// Detail view for a single scan.
///
/// Reached from:
///   - the camera screen, after a successful submission (newest-scan pop-in)
///   - the gallery grid (tap a thumbnail)
///   - the profile preview row (tap a thumbnail)
///   - the calendar grid (tap a day with a scan)
///
/// Shows: the scan image with bbox overlay, severity badge, layman-readable
/// summary derived from the row's counts + severity_label, a three-card
/// counts row, and a per-class breakdown of detected lesions. Top-right
/// action deletes the scan (with confirmation).
class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.scan});
  final Scan scan;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen> {
  bool _isDeleting = false;
  bool _isSavingNote = false;

  @override
  void initState() {
    super.initState();
    // Listen so that notes edits (or any other field updates) reflect on
    // this screen without a navigation pop+push round-trip.
    ScanService.instance.addListener(_onScansChanged);
  }

  @override
  void dispose() {
    ScanService.instance.removeListener(_onScansChanged);
    super.dispose();
  }

  void _onScansChanged() {
    if (mounted) setState(() {});
  }

  /// Pulls the freshest copy of this screen's scan from ScanService — so
  /// when `updateScanNotes` (or any future write) refreshes the list, the
  /// detail view automatically picks up the new fields. Falls back to the
  /// original constructor scan if for some reason the id is gone (e.g.,
  /// the user deleted it from another surface).
  Scan get _scan {
    final fromService = ScanService.instance.scans;
    for (final s in fromService) {
      if (s.id == widget.scan.id) return s;
    }
    return widget.scan;
  }

  Future<void> _editNote() async {
    if (_isSavingNote) return;
    final current = _scan.notes ?? '';
    final controller = TextEditingController(text: current);
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current.isEmpty ? 'Add a note' : 'Edit note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText:
                "What's worth remembering? Routine changes, how your skin "
                'feels, anything that might explain this scan.',
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
    // Dialog dismissed without confirming — nothing to do.
    if (result == null || !mounted) return;
    // Empty string from the "Clear" button or a save-with-blank counts as
    // a delete; the service normalizes blank → NULL.
    setState(() => _isSavingNote = true);
    try {
      await ScanService.instance.updateScanNotes(widget.scan.id, result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save note: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingNote = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this scan?'),
        content: const Text(
          'This removes the photo and analysis from your history. '
          'It cannot be undone.',
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
    if (ok != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await ScanService.instance.deleteScan(widget.scan.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    final hasNote = scan.notes != null && scan.notes!.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Scan details'),
        actions: [
          IconButton(
            onPressed: _isDeleting ? null : _confirmDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete scan',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LesionOverlay(
                imageUrl: scan.imageUrl,
                lesions: scan.lesions,
              ),
              const SizedBox(height: 10),
              Text(
                _formatDate(scan.takenAt),
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 20),
              _SeverityBadge(scan: scan),
              const SizedBox(height: 16),
              _SummaryCard(scan: scan),
              if (scan.doctorNote != null &&
                  scan.doctorNote!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                _FromDoctorCard(note: scan.doctorNote!.trim()),
              ],
              const SizedBox(height: 16),
              _CountsRow(scan: scan),
              if (scan.lesions.isNotEmpty) ...[
                const SizedBox(height: 20),
                const _SectionHeader(title: 'Detected lesions'),
                const SizedBox(height: 8),
                _ClassBreakdown(lesions: scan.lesions),
              ],
              if (scan.analysisDetails != null) ...[
                const SizedBox(height: 20),
                _AnalysisDetailsCard(details: scan.analysisDetails!),
              ],
              const SizedBox(height: 20),
              _NotesSection(
                notes: scan.notes,
                hasNote: hasNote,
                isSaving: _isSavingNote,
                onEdit: _editNote,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notes row + card. Always rendered (unlike the old conditional display)
/// so the user has a discoverable entry point to add a note even on a
/// fresh scan. When empty, the card is a soft prompt; when populated, it
/// shows the note text and an Edit affordance.
class _NotesSection extends StatelessWidget {
  const _NotesSection({
    required this.notes,
    required this.hasNote,
    required this.isSaving,
    required this.onEdit,
  });

  final String? notes;
  final bool hasNote;
  final bool isSaving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader(title: 'Notes')),
            TextButton.icon(
              onPressed: isSaving ? null : onEdit,
              icon: Icon(
                hasNote ? Icons.edit_outlined : Icons.add,
                size: 18,
              ),
              label: Text(hasNote ? 'Edit' : 'Add'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: isSaving ? null : onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: hasNote
                  ? Text(
                      notes!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  : Text(
                      "No note yet. Tap to add one — what changed in your "
                      'routine, how your skin feels, anything worth '
                      'remembering.',
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Read-only card displaying the dermatologist's note for this scan, when
/// one exists. Placed high on the screen (right under the summary card)
/// because if the patient's dermatologist has left them a note, that's
/// the thing they came to see — bury it below the lesion breakdown and
/// you've wasted the message.
///
/// Styled with the accent color and a "stethoscope" icon to clearly mark
/// it as coming *from* the doctor — distinct from the patient's own
/// notes section further down the screen.
class _FromDoctorCard extends StatelessWidget {
  const _FromDoctorCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.medical_services_outlined,
                    color: AppTheme.accent, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                'From your dermatologist',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            note,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Severity badge =====

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scan.severityColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scan.severityColor.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: scan.severityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              scan.severityLabel,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          Text(
            scan.cookGrade < 0 ? 'Clear' : 'Cook ${scan.cookGrade}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Summary paragraph =====

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _summaryText(scan),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      ),
    );
  }
}

/// Builds a 1–2 sentence layman-readable description from a scan's counts +
/// severity label. Deliberately descriptive, not prescriptive — no
/// "try this skincare routine" suggestions (that's the dermatologist's job).
String _summaryText(Scan s) {
  if (s.cookGrade < 0) {
    return 'No active acne detected in this scan. Your skin looks clear.';
  }

  final parts = <String>[];
  if (s.inflammatoryCount > 0) {
    final w = s.inflammatoryCount == 1 ? 'lesion' : 'lesions';
    parts.add('${s.inflammatoryCount} inflammatory $w');
  }
  if (s.nonInflammatoryCount > 0) {
    final w = s.nonInflammatoryCount == 1 ? 'lesion' : 'lesions';
    parts.add('${s.nonInflammatoryCount} non-inflammatory $w');
  }
  if (s.postAcneCount > 0) {
    final w = s.postAcneCount == 1 ? 'mark' : 'marks';
    parts.add('${s.postAcneCount} post-acne $w');
  }

  if (parts.isEmpty) {
    return 'Severity reads as ${s.severityLabel} in this scan.';
  }

  final detected = _joinList(parts);
  return 'We detected $detected. Your skin reads as ${s.severityLabel} overall.';
}

String _joinList(List<String> items) {
  if (items.length == 1) return items.first;
  if (items.length == 2) return '${items[0]} and ${items[1]}';
  return '${items.sublist(0, items.length - 1).join(", ")}, and ${items.last}';
}

// ===== Counts row =====

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
            count: scan.inflammatoryCount,
            color: const Color(0xFFF44336),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountCard(
            label: 'Non-inflammatory',
            count: scan.nonInflammatoryCount,
            color: const Color(0xFFFFC107),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountCard(
            label: 'Post-acne',
            count: scan.postAcneCount,
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
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Per-class breakdown =====

class _ClassBreakdown extends StatelessWidget {
  const _ClassBreakdown({required this.lesions});
  final List<Lesion> lesions;

  @override
  Widget build(BuildContext context) {
    // Group by class name → count.
    final counts = <String, int>{};
    final bucketByClass = <String, String>{};
    for (final l in lesions) {
      counts[l.className] = (counts[l.className] ?? 0) + 1;
      bucketByClass[l.className] = l.bucket;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: AppTheme.border(context),
                ),
              ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _bucketColorFor(bucketByClass[entries[i].key] ?? ''),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(_prettyClassName(entries[i].key)),
                subtitle: Text(
                  _prettyBucket(bucketByClass[entries[i].key] ?? ''),
                  style: TextStyle(color: AppTheme.textSecondary(context)),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '×${entries[i].value}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: AppTheme.textSecondary(context),
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => _showAcneReference(
                  context,
                  rawClassName: entries[i].key,
                  prettyClassName: _prettyClassName(entries[i].key),
                  bucket: bucketByClass[entries[i].key] ?? '',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pops a modal bottom sheet with the educational reference for a lesion
/// class. Looks up the AcneReference by raw class name (handles plurals /
/// case / spelling variants); if none exists yet, shows a graceful
/// "details coming soon" state instead of an error.
void _showAcneReference(
  BuildContext context, {
  required String rawClassName,
  required String prettyClassName,
  required String bucket,
}) {
  final reference = lookupAcneReference(rawClassName);
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surface(context),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AcneReferenceSheet(
      prettyClassName: prettyClassName,
      bucket: bucket,
      reference: reference,
    ),
  );
}

class _AcneReferenceSheet extends StatelessWidget {
  const _AcneReferenceSheet({
    required this.prettyClassName,
    required this.bucket,
    this.reference,
  });

  /// Display-cased class name from the detected-lesions list.
  final String prettyClassName;

  /// Coarse bucket (`inflammatory` / `non_inflammatory` / `post_acne`)
  /// — drives the colored bucket chip in the header.
  final String bucket;

  /// Reference entry from acne_references.dart. Null = no reference for
  /// this class yet (or the lookup failed); the sheet renders a graceful
  /// placeholder instead.
  final AcneReference? reference;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle.
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        prettyClassName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (bucket.isNotEmpty) _BucketChip(bucket: bucket),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ReferenceImage(asset: reference?.imageAsset),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  reference?.description ??
                      'A detailed reference for this lesion class is coming soon. '
                          'For now, the colored bucket chip above tells you '
                          'whether it falls into our inflammatory, non-inflammatory, '
                          'or post-acne grouping.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                      ),
                ),
              ),
              if (reference?.attribution != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    reference!.attribution!,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({required this.bucket});
  final String bucket;

  @override
  Widget build(BuildContext context) {
    final color = _bucketColorFor(bucket);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _prettyBucket(bucket),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ReferenceImage extends StatelessWidget {
  const _ReferenceImage({this.asset});
  final String? asset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: asset == null
            ? const _ReferenceImagePlaceholder()
            : Image.asset(
                asset!,
                fit: BoxFit.cover,
                // errorBuilder catches the asset-not-found case so missing
                // images degrade gracefully to the placeholder. Keeps the
                // app shippable while we source the real DermNet NZ
                // images.
                errorBuilder: (_, __, ___) =>
                    const _ReferenceImagePlaceholder(),
              ),
      ),
    );
  }
}

class _ReferenceImagePlaceholder extends StatelessWidget {
  const _ReferenceImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primary.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 40,
            color: AppTheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 6),
          Text(
            'Reference image coming soon',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

Color _bucketColorFor(String bucket) {
  switch (bucket) {
    case 'inflammatory':
      return const Color(0xFFF44336);
    case 'non_inflammatory':
      return const Color(0xFFFFC107);
    case 'post_acne':
      return const Color(0xFF9E9E9E);
    default:
      return const Color(0xFF607D8B);
  }
}

String _prettyBucket(String bucket) {
  switch (bucket) {
    case 'inflammatory':
      return 'Inflammatory';
    case 'non_inflammatory':
      return 'Non-inflammatory';
    case 'post_acne':
      return 'Post-acne';
    default:
      return 'Other';
  }
}

String _prettyClassName(String raw) {
  // Strip trailing 's', capitalize. "papules" → "Papule".
  // Display as Title Case for readability in the list.
  final s = raw.trim();
  if (s.isEmpty) return s;
  final singular = s.toLowerCase().endsWith('s') && s.length > 1
      ? s.substring(0, s.length - 1)
      : s;
  // Replace underscores with spaces (e.g. dark_spot → "Dark spot").
  final humanized = singular.replaceAll('_', ' ');
  return humanized[0].toUpperCase() + humanized.substring(1);
}

// ===== Analysis details (per-model breakdown, expandable) =====

/// Collapsed-by-default card surfacing the dual-signal reasoning the
/// analyze-scan Edge Function recorded in `source_metadata`. Lets a curious
/// user (or thesis-defense panel) see exactly which model voted what and
/// how the final grade was reconciled.
///
/// Only rendered when `scan.analysisDetails != null` (i.e., the row carries
/// post-phase-2 provenance). When the classifier failed at scan time, the
/// Classifier section explains that instead of going blank.
class _AnalysisDetailsCard extends StatelessWidget {
  const _AnalysisDetailsCard({required this.details});
  final AnalysisDetails details;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Hide the divider lines ExpansionTile draws above/below itself —
        // the surrounding Card already gives us the visual frame.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.info_outline, color: AppTheme.primary),
          title: const Text(
            'Analysis details',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          children: [
            _DetailSection(
              title: 'DETECTION',
              children: [
                _DetailRow(
                  label: 'Model',
                  value: details.detectionModel,
                ),
                _DetailRow(
                  label: 'Confidence threshold',
                  value:
                      '${(details.confidenceThreshold * 100).toStringAsFixed(0)}%',
                ),
                _DetailRow(
                  label: 'Cook grade (alone)',
                  value: '${details.detectionCookGrade}',
                ),
                if (details.detectionLatencyMs != null)
                  _DetailRow(
                    label: 'Latency',
                    value:
                        '${(details.detectionLatencyMs! / 1000).toStringAsFixed(1)}s',
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _DetailSection(
              title: 'CLASSIFIER',
              children: details.hasClassifier
                  ? [
                      _DetailRow(
                        label: 'Model',
                        value: details.classifierModel ?? '—',
                      ),
                      _DetailRow(
                        label: 'Top label',
                        value: details.classifierTopLabel ?? '—',
                      ),
                      if (details.classifierTopConfidence != null)
                        _DetailRow(
                          label: 'Confidence',
                          value:
                              '${(details.classifierTopConfidence! * 100).toStringAsFixed(0)}%',
                        ),
                      if (details.classifierCookGrade != null)
                        _DetailRow(
                          label: 'Cook grade (alone)',
                          value: '${details.classifierCookGrade}',
                        ),
                      if (details.classifierLatencyMs != null)
                        _DetailRow(
                          label: 'Latency',
                          value:
                              '${(details.classifierLatencyMs! / 1000).toStringAsFixed(1)}s',
                        ),
                    ]
                  : [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Classifier was unavailable on this scan. The grade '
                          'reflects detection only.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary(context),
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
            ),
            const SizedBox(height: 14),
            _DetailSection(
              title: 'FINAL GRADE',
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _rationaleText(details.combinerRationale),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          fontSize: 13,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary(context),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Turns a combiner_rationale tag from source_metadata into a sentence the
/// scan-detail screen can show next to "Final grade".
String _rationaleText(String rationale) {
  switch (rationale) {
    case 'agreement':
      return 'Both models arrived at the same severity grade — the displayed '
          'grade is the agreed value.';
    case 'minor_disagreement_kept':
      return 'Detection and classifier disagreed by one severity step. The '
          'detection grade was kept because its count-based reasoning is more '
          'consistent with the lesion overlay above.';
    case 'hf_override':
      return 'Detection and classifier disagreed by more than one severity '
          'step. The classifier rates severity holistically and was given '
          'priority — useful on dense-acne faces where the detection model '
          'may under-count.';
    case 'roboflow_only':
      return 'The classifier did not respond at scan time. The displayed '
          'grade reflects detection only.';
    default:
      return 'Final grade derived from the available signals.';
  }
}

// ===== Section header =====

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

// ===== Date formatting =====

String _formatDate(DateTime d) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final hour12 = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  final minute = d.minute.toString().padLeft(2, '0');
  return 'Taken ${months[d.month - 1]} ${d.day}, ${d.year} at $hour12:$minute $ampm';
}
