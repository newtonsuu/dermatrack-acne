import 'package:flutter/material.dart';

import '../../models/scan.dart';
import '../../services/doctor_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/scan_thumbnail.dart';
import '../../widgets/severity_trend_chart.dart';
import '../../widgets/skin_summary_card.dart';
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
  @override
  void initState() {
    super.initState();
    DoctorService.instance.addListener(_onChanged);
    // Kick off the scan load. If the doctor opens this patient again later,
    // the service's cache makes that re-entry instant.
    DoctorService.instance.loadPatientScans(widget.patient.id);
  }

  @override
  void dispose() {
    DoctorService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() =>
      DoctorService.instance.loadPatientScans(widget.patient.id);

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _PatientHeader(patient: widget.patient, scanCount: scans.length),
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
        _SectionTitle('Scan history (${scans.length})'),
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
