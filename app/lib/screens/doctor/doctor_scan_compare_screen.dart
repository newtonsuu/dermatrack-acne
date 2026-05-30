import 'package:flutter/material.dart';

import '../../models/scan.dart';
import '../../services/doctor_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lesion_overlay.dart';

/// Side-by-side progression view: pick two of a patient's scans and see how
/// the Cook grade and lesion counts changed between them.
///
/// Defaults to the patient's earliest scan (baseline, left) vs their most
/// recent (comparison, right) — the most common "is the treatment working?"
/// question. Both scans are independently re-selectable via the dropdowns.
///
/// Deltas are computed as `comparison - baseline` and color-coded clinically:
/// fewer lesions / lower grade is an improvement (green, ↓), more is a
/// regression (red, ↑), no change is neutral (grey). Read-only — this screen
/// never mutates a scan.
class DoctorScanCompareScreen extends StatefulWidget {
  const DoctorScanCompareScreen({
    super.key,
    required this.patient,
    required this.scans,
  });

  final DoctorPatient patient;

  /// The patient's scans, expected newest-first (the order DoctorService
  /// returns them in). Must contain at least two entries — the caller only
  /// offers this screen when that holds.
  final List<Scan> scans;

  @override
  State<DoctorScanCompareScreen> createState() =>
      _DoctorScanCompareScreenState();
}

class _DoctorScanCompareScreenState extends State<DoctorScanCompareScreen> {
  late String _baselineId;
  late String _comparisonId;

  @override
  void initState() {
    super.initState();
    // scans are newest-first → first is latest, last is earliest. Baseline
    // is the earliest capture; comparison is the latest.
    _baselineId = widget.scans.last.id;
    _comparisonId = widget.scans.first.id;
  }

  Scan _byId(String id) =>
      widget.scans.firstWhere((s) => s.id == id, orElse: () => widget.scans.first);

  @override
  Widget build(BuildContext context) {
    final baseline = _byId(_baselineId);
    final comparison = _byId(_comparisonId);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Compare scans')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            '${widget.patient.displayLabel} · ${widget.scans.length} scans',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary(context),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ScanColumn(
                  roleLabel: 'Baseline',
                  scans: widget.scans,
                  selectedId: _baselineId,
                  onChanged: (id) => setState(() => _baselineId = id),
                  scan: baseline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ScanColumn(
                  roleLabel: 'Comparison',
                  scans: widget.scans,
                  selectedId: _comparisonId,
                  onChanged: (id) => setState(() => _comparisonId = id),
                  scan: comparison,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Progression',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _spanLabel(baseline, comparison),
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),
          _ProgressionCard(baseline: baseline, comparison: comparison),
        ],
      ),
    );
  }

  String _spanLabel(Scan baseline, Scan comparison) {
    final days = comparison.takenAt.difference(baseline.takenAt).inDays.abs();
    if (days == 0) return 'Same day';
    return '$days ${days == 1 ? 'day' : 'days'} apart';
  }
}

/// One selectable scan: a dropdown to choose which scan fills this slot, the
/// image with its lesion overlay, and a small grade/date caption.
class _ScanColumn extends StatelessWidget {
  const _ScanColumn({
    required this.roleLabel,
    required this.scans,
    required this.selectedId,
    required this.onChanged,
    required this.scan,
  });

  final String roleLabel;
  final List<Scan> scans;
  final String selectedId;
  final ValueChanged<String> onChanged;
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          roleLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppTheme.textSecondary(context),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedId,
            isExpanded: true,
            isDense: true,
            borderRadius: BorderRadius.circular(10),
            items: [
              for (final s in scans)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    _fmtDate(s.takenAt),
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
        const SizedBox(height: 6),
        LesionOverlay(imageUrl: scan.imageUrl, lesions: scan.lesions),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scan.severityColor.withValues(alpha: 0.18),
                border: Border.all(color: scan.severityColor, width: 1.5),
                shape: BoxShape.circle,
              ),
              child: Text(
                scan.cookGrade < 0 ? '−' : scan.cookGrade.toString(),
                style: TextStyle(
                  color: scan.severityColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                scan.severityLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${_2(d.month)}-${_2(d.day)}';
  static String _2(int n) => n.toString().padLeft(2, '0');
}

/// The delta table: grade + each lesion bucket + total, comparison vs baseline.
class _ProgressionCard extends StatelessWidget {
  const _ProgressionCard({required this.baseline, required this.comparison});

  final Scan baseline;
  final Scan comparison;

  @override
  Widget build(BuildContext context) {
    final bTotal = baseline.inflammatoryCount +
        baseline.nonInflammatoryCount +
        baseline.postAcneCount;
    final cTotal = comparison.inflammatoryCount +
        comparison.nonInflammatoryCount +
        comparison.postAcneCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            _DeltaRow(
              label: 'Cook grade',
              baseline: baseline.cookGrade,
              comparison: comparison.cookGrade,
              emphasize: true,
            ),
            const Divider(height: 1),
            _DeltaRow(
              label: 'Inflammatory',
              baseline: baseline.inflammatoryCount,
              comparison: comparison.inflammatoryCount,
            ),
            const Divider(height: 1),
            _DeltaRow(
              label: 'Non-inflammatory',
              baseline: baseline.nonInflammatoryCount,
              comparison: comparison.nonInflammatoryCount,
            ),
            const Divider(height: 1),
            _DeltaRow(
              label: 'Post-acne',
              baseline: baseline.postAcneCount,
              comparison: comparison.postAcneCount,
            ),
            const Divider(height: 1),
            _DeltaRow(
              label: 'Total lesions',
              baseline: bTotal,
              comparison: cTotal,
              emphasize: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single metric row: label, baseline value, arrow, comparison value, and a
/// color-coded delta chip. Lower is better for every metric here, so a
/// negative delta is green (improvement) and positive is red (regression).
class _DeltaRow extends StatelessWidget {
  const _DeltaRow({
    required this.label,
    required this.baseline,
    required this.comparison,
    this.emphasize = false,
  });

  final String label;
  final int baseline;
  final int comparison;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final delta = comparison - baseline;
    final Color color;
    final IconData icon;
    if (delta < 0) {
      color = const Color(0xFF2E7D32); // green — improvement
      icon = Icons.arrow_downward;
    } else if (delta > 0) {
      color = const Color(0xFFC62828); // red — regression
      icon = Icons.arrow_upward;
    } else {
      color = AppTheme.textSecondary(context);
      icon = Icons.remove;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${_fmt(baseline)}  →  ${_fmt(comparison)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _DeltaChip(delta: delta, color: color, icon: icon),
        ],
      ),
    );
  }

  // Cook grade can be -1 (clear); show that as a dash so it reads cleanly.
  String _fmt(int v) => v < 0 ? '−' : v.toString();
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta, required this.color, required this.icon});

  final int delta;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = delta == 0 ? '0' : '${delta > 0 ? '+' : ''}$delta';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
