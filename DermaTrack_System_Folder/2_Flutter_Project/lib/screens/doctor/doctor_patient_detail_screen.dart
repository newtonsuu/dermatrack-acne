import 'package:flutter/material.dart';

import '../../models/patient_history.dart';
import '../../models/scan.dart';
import '../../models/treatment_plan.dart';
import '../../services/doctor_report_service.dart';
import '../../services/doctor_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/scan_thumbnail.dart';
import '../../widgets/severity_trend_chart.dart';
import '../../widgets/skin_summary_card.dart';
import '../chat_screen.dart';
import 'doctor_prescriptions_screen.dart';
import 'doctor_scan_compare_screen.dart';
import 'doctor_scan_detail_screen.dart';

/// Read-only view of a patient's scan history, severity trend, and skin
/// summary — what the doctor opens after tapping a row in the patient list.
///
/// Reuses three patient-side widgets (SeverityTrendChart, SkinSummaryCard,
/// ScanThumbnail) verbatim because the data shape is identical — a Scan is
/// a Scan whether the viewer is the patient or the doctor. The doctor's
/// tap on a thumbnail routes to DoctorScanDetailScreen (read-only) instead
/// of the patient's ScanDetailScreen (which has edit + delete affordances).
class DoctorPatientDetailScreen extends StatefulWidget {
  const DoctorPatientDetailScreen({super.key, required this.patient});

  final DoctorPatient patient;

  @override
  State<DoctorPatientDetailScreen> createState() =>
      _DoctorPatientDetailScreenState();
}

class _DoctorPatientDetailScreenState extends State<DoctorPatientDetailScreen> {
  bool _isSavingPlan = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    DoctorService.instance.addListener(_onChanged);
    // Kick off the scan, medical-history, and treatment-plan loads. The
    // service caches all three, so re-opening the patient is instant on
    // subsequent visits.
    DoctorService.instance.loadPatientScans(widget.patient.id);
    DoctorService.instance.loadPatientHistory(widget.patient.id);
    DoctorService.instance.loadTreatmentPlan(widget.patient.id);
  }

  @override
  void dispose() {
    DoctorService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await Future.wait([
      DoctorService.instance.loadPatientScans(widget.patient.id),
      DoctorService.instance.loadPatientHistory(widget.patient.id, force: true),
      DoctorService.instance.loadTreatmentPlan(widget.patient.id, force: true),
    ]);
  }

  /// Opens an edit dialog for the patient-level treatment plan, pre-filled
  /// with the current plan. Returns null (dismiss / no-op), '' (clear), or
  /// the new text. Mirrors the doctor-note edit flow on the scan screen.
  Future<void> _editTreatmentPlan() async {
    if (_isSavingPlan) return;
    final current =
        DoctorService.instance.planFor(widget.patient.id)?.plan ?? '';
    final controller = TextEditingController(text: current);

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current.isEmpty ? 'Add treatment plan' : 'Edit treatment plan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 10,
          minLines: 5,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText:
                'Standing guidance for the patient — regimen, products, '
                'and when to follow up. Visible to the patient.',
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

    setState(() => _isSavingPlan = true);
    try {
      await DoctorService.instance.setTreatmentPlan(
        patientId: widget.patient.id,
        plan: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.trim().isEmpty
              ? 'Treatment plan cleared.'
              : 'Treatment plan saved. The patient can see it.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save plan: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSavingPlan = false);
    }
  }

  /// Builds and shares a PDF report for this patient from the currently
  /// loaded scans, medical history, and treatment plan.
  Future<void> _exportReport() async {
    if (_isExporting) return;
    final service = DoctorService.instance;
    final scans = service.scansFor(widget.patient.id);
    if (scans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No scans to include in the report yet.')),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      await DoctorReportService.sharePatientReport(
        patient: widget.patient,
        scans: scans,
        history: service.historyFor(widget.patient.id),
        plan: service.planFor(widget.patient.id),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't generate report: $e")),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = DoctorService.instance;
    final scans = service.scansFor(widget.patient.id);
    final isLoading = service.isLoadingScansFor(widget.patient.id);
    final error = service.scansErrorFor(widget.patient.id);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text(widget.patient.displayLabel),
        actions: [
          IconButton(
            tooltip: 'Message patient',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    patientId: widget.patient.id,
                    title: widget.patient.displayLabel,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Prescriptions',
            icon: const Icon(Icons.medication_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DoctorPrescriptionsScreen(patient: widget.patient),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Export PDF report',
            onPressed: _isExporting ? null : _exportReport,
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
        // Tiny visual reminder that this is the doctor's read-only lens, not
        // the patient's editable view.
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(20),
          child: _ReadOnlyRibbon(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _body(scans: scans, isLoading: isLoading, error: error),
      ),
    );
  }

  Widget _body({
    required List<Scan> scans,
    required bool isLoading,
    required Object? error,
  }) {
    // First load with no cached data → centered spinner. Subsequent refreshes
    // keep the existing layout visible so the doctor doesn't lose context.
    if (isLoading && scans.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(48),
        children: const [
          SizedBox(height: 96),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (scans.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          _EmptyState(error: error, patientLabel: widget.patient.displayLabel),
        ],
      );
    }

    final service = DoctorService.instance;
    final patientId = widget.patient.id;
    final history = service.historyFor(patientId);
    final hasHistory = service.hasHistoryFor(patientId);
    final historyLoading = service.isLoadingHistoryFor(patientId);
    final plan = service.planFor(patientId);
    final planLoading = service.isLoadingPlanFor(patientId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _PatientHeader(patient: widget.patient, scanCount: scans.length),
        const SizedBox(height: 16),
        _TreatmentPlanCard(
          plan: plan,
          isLoading: planLoading && !service.hasPlanFor(patientId),
          isSaving: _isSavingPlan,
          onEdit: _editTreatmentPlan,
        ),
        const SizedBox(height: 16),
        _MedicalHistoryCard(
          history: history,
          hasFetched: hasHistory,
          isLoading: historyLoading,
        ),
        const SizedBox(height: 16),
        SkinSummaryCard(scans: scans),
        const SizedBox(height: 20),
        _SectionTitle('Severity trend (30 days)'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: SeverityTrendChart(scans: scans),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _SectionTitle('Scan history (${scans.length})')),
            // Comparison needs two scans to be meaningful; hide the action
            // until the patient has at least a baseline and a follow-up.
            if (scans.length >= 2)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DoctorScanCompareScreen(
                        patient: widget.patient,
                        scans: scans,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.compare_arrows, size: 18),
                label: const Text('Compare'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _ScansGrid(
          scans: scans,
          onTap: (scan) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DoctorScanDetailScreen(
                  patient: widget.patient,
                  scan: scan,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ReadOnlyRibbon extends StatelessWidget {
  const _ReadOnlyRibbon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.primary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.visibility_outlined,
              color: AppTheme.primary, size: 13),
          const SizedBox(width: 6),
          Text(
            'Read-only — shared by the patient',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only summary of the patient's medical-history intake. Collapsed
/// by default to keep the patient-detail screen scannable; tap to expand
/// the full sectioned view.
///
/// Renders three states:
///   - isLoading + !hasFetched → spinner placeholder.
///   - hasFetched + history == null → "Patient hasn't filled this in yet."
///   - hasFetched + history != null → expandable sectioned summary.
class _MedicalHistoryCard extends StatefulWidget {
  const _MedicalHistoryCard({
    required this.history,
    required this.hasFetched,
    required this.isLoading,
  });

  final PatientHistory? history;
  final bool hasFetched;
  final bool isLoading;

  @override
  State<_MedicalHistoryCard> createState() => _MedicalHistoryCardState();
}

class _MedicalHistoryCardState extends State<_MedicalHistoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Medical history',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const Spacer(),
                if (widget.history != null)
                  TextButton(
                    onPressed: () =>
                        setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(_expanded ? 'Collapse' : 'Expand'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _body(context),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!widget.hasFetched && widget.isLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Loading history…',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      );
    }
    final history = widget.history;
    if (history == null) {
      return Text(
        "Patient hasn't filled in their medical history yet.",
        style: TextStyle(
          fontSize: 13,
          color: AppTheme.textSecondary(context),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (!_expanded) {
      // Compact preview: one-line summary of the most salient bits.
      return Text(
        _summaryLine(history),
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: AppTheme.textPrimary(context),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kvSection(context, 'About', _aboutLines(history)),
        _kvSection(context, 'Past medical history',
            _pastMedicalLines(history)),
        _kvSection(context, 'Family history', _familyLines(history)),
        _kvSection(
            context, 'Personal and social history', _socialLines(history)),
        if ((history.currentMedications ?? '').trim().isNotEmpty)
          _kvSection(context, 'Current medications',
              [history.currentMedications!.trim()]),
      ],
    );
  }

  Widget _kvSection(BuildContext context, String title, List<String> lines) {
    if (lines.isEmpty) {
      lines = const ['—'];
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Text(
              line,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textPrimary(context),
              ),
            ),
        ],
      ),
    );
  }

  String _summaryLine(PatientHistory h) {
    final parts = <String>[];
    if ((h.fullName ?? '').trim().isNotEmpty) {
      parts.add(h.fullName!.trim());
    }
    if (h.birthday != null) {
      parts.add('born ${h.birthday!.year}');
    }
    if (h.pastMedicalConditions.isNotEmpty) {
      parts.add('${h.pastMedicalConditions.length} past condition'
          '${h.pastMedicalConditions.length == 1 ? '' : 's'}');
    }
    if (h.familyHistoryConditions.isNotEmpty) {
      parts.add('${h.familyHistoryConditions.length} family condition'
          '${h.familyHistoryConditions.length == 1 ? '' : 's'}');
    }
    if (h.smokerPackYears != null) parts.add('smoker');
    if (h.isAlcoholDrinker) parts.add('alcohol');
    if ((h.currentMedications ?? '').trim().isNotEmpty) {
      parts.add('on medications');
    }
    if (parts.isEmpty) return 'No fields filled.';
    return parts.join(' · ');
  }

  List<String> _aboutLines(PatientHistory h) {
    final lines = <String>[];
    if ((h.fullName ?? '').trim().isNotEmpty) lines.add(h.fullName!.trim());
    final demo = <String>[];
    if (h.birthday != null) {
      demo.add('born ${h.birthday!.year}-${_2(h.birthday!.month)}-${_2(h.birthday!.day)}');
    }
    if (h.sex != null) {
      demo.add(kSexOptions[h.sex] ?? h.sex!);
    }
    if (demo.isNotEmpty) lines.add(demo.join(' · '));
    if ((h.occupation ?? '').trim().isNotEmpty) {
      lines.add('Occupation: ${h.occupation!.trim()}');
    }
    if ((h.address ?? '').trim().isNotEmpty) {
      lines.add('Address: ${h.address!.trim()}');
    }
    if ((h.contactNo ?? '').trim().isNotEmpty) {
      lines.add('Contact: ${h.contactNo!.trim()}');
    }
    return lines;
  }

  List<String> _pastMedicalLines(PatientHistory h) {
    final lines = <String>[];
    if (h.pastMedicalConditions.isNotEmpty) {
      lines.add(h.pastMedicalConditions
          .map((k) => kPastMedicalConditions[k] ?? k)
          .join(', '));
    }
    if ((h.previousSurgeryDetail ?? '').trim().isNotEmpty) {
      lines.add('Previous surgery: ${h.previousSurgeryDetail!.trim()}');
    }
    if ((h.allergiesDetail ?? '').trim().isNotEmpty) {
      lines.add('Allergies: ${h.allergiesDetail!.trim()}');
    }
    if ((h.pastMedicalOthers ?? '').trim().isNotEmpty) {
      lines.add('Others: ${h.pastMedicalOthers!.trim()}');
    }
    return lines;
  }

  List<String> _familyLines(PatientHistory h) {
    final lines = <String>[];
    if (h.familyHistoryConditions.isNotEmpty) {
      lines.add(h.familyHistoryConditions
          .map((k) => kFamilyHistoryConditions[k] ?? k)
          .join(', '));
    }
    if ((h.familyHistoryOthers ?? '').trim().isNotEmpty) {
      lines.add('Others: ${h.familyHistoryOthers!.trim()}');
    }
    return lines;
  }

  List<String> _socialLines(PatientHistory h) {
    final lines = <String>[];
    if (h.smokerPackYears != null) {
      lines.add('Smoker · ${h.smokerPackYears!.toStringAsFixed(0)} pack-years');
    }
    if (h.usesProhibitedDrugs) lines.add('Uses prohibited drugs');
    if (h.isAlcoholDrinker) lines.add('Alcoholic beverage drinker');
    if ((h.socialOthers ?? '').trim().isNotEmpty) {
      lines.add('Others: ${h.socialOthers!.trim()}');
    }
    return lines;
  }

  static String _2(int n) => n.toString().padLeft(2, '0');
}

/// Editable, doctor-authored treatment plan for the patient. Uses the accent
/// color to read as an actionable card (like the doctor-note card on the scan
/// screen). "Add" when empty, "Edit" when populated.
class _TreatmentPlanCard extends StatelessWidget {
  const _TreatmentPlanCard({
    required this.plan,
    required this.isLoading,
    required this.isSaving,
    required this.onEdit,
  });

  final TreatmentPlan? plan;
  final bool isLoading;
  final bool isSaving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasPlan = plan != null && plan!.plan.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medication_outlined,
                    color: AppTheme.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Treatment plan (visible to the patient)',
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
                  onPressed: (isSaving || isLoading) ? null : onEdit,
                  icon: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(hasPlan ? Icons.edit_outlined : Icons.add,
                          size: 16),
                  label: Text(hasPlan ? 'Edit' : 'Add'),
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
              child: _content(context, hasPlan),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, bool hasPlan) {
    if (isLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Loading plan…',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary(context))),
        ],
      );
    }
    if (!hasPlan) {
      return Text(
        'No treatment plan yet. Tap Add to give the patient a regimen and '
        'follow-up guidance.',
        style: TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: AppTheme.textSecondary(context),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan!.plan.trim(),
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppTheme.textPrimary(context),
          ),
        ),
        if (plan!.updatedAt != null) ...[
          const SizedBox(height: 6),
          Text(
            'Updated ${plan!.updatedAt!.year}-${_2(plan!.updatedAt!.month)}-${_2(plan!.updatedAt!.day)}',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ],
    );
  }

  static String _2(int n) => n.toString().padLeft(2, '0');
}

class _PatientHeader extends StatelessWidget {
  const _PatientHeader({required this.patient, required this.scanCount});

  final DoctorPatient patient;
  final int scanCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                patient.initials,
                style: const TextStyle(
                  color: Colors.white,
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
                    patient.displayLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${patient.username}',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$scanCount ${scanCount == 1 ? 'scan' : 'scans'} shared',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary(context),
      ),
    );
  }
}

class _ScansGrid extends StatelessWidget {
  const _ScansGrid({required this.scans, required this.onTap});

  final List<Scan> scans;
  final ValueChanged<Scan> onTap;

  @override
  Widget build(BuildContext context) {
    // Wrap with Wrap rather than GridView so the list flexes nicely on the
    // narrow phone widths the demo will run on, without needing intrinsic
    // height calculations inside a parent ListView.
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final scan in scans)
          ScanThumbnail(scan: scan, onTap: () => onTap(scan)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.patientLabel, this.error});

  final String patientLabel;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          hasError ? Icons.error_outline : Icons.photo_library_outlined,
          size: 56,
          color: AppTheme.textSecondary(context),
        ),
        const SizedBox(height: 16),
        Text(
          hasError ? 'Could not load scans' : 'No scans to show yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasError
              ? 'Pull to retry.\n\n${error.toString()}'
              : "$patientLabel hasn't shared any scans yet, or sharing was just turned on. Pull to refresh.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary(context),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
