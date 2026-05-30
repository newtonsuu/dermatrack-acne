import 'package:flutter/material.dart';

import '../../services/doctor_service.dart';
import '../../theme/app_theme.dart';
import 'doctor_patient_detail_screen.dart';

/// List of patients who have toggled "Share with my dermatologist" on.
///
/// Each row shows the patient's display name, their last scan timestamp,
/// and a severity chip for their most recent grade. Tapping a row opens the
/// patient detail view.
///
/// Pull-to-refresh re-runs DoctorService.loadPatients so the list reflects
/// recent opt-ins / opt-outs without restarting the app — useful during
/// the demo if the dermatologist asks "what happens when the patient
/// turns sharing off?"
class DoctorPatientListScreen extends StatefulWidget {
  const DoctorPatientListScreen({super.key});

  @override
  State<DoctorPatientListScreen> createState() =>
      _DoctorPatientListScreenState();
}

class _DoctorPatientListScreenState extends State<DoctorPatientListScreen> {
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

  Future<void> _refresh() => DoctorService.instance.loadPatients();

  @override
  Widget build(BuildContext context) {
    final service = DoctorService.instance;
    final patients = service.patients;
    final isLoading = service.isLoadingPatients;
    final error = service.patientsError;

    // First-time load with no cached data → centered spinner. Subsequent
    // refreshes keep the existing list visible so the doctor isn't staring
    // at a blank screen during pull-to-refresh.
    if (isLoading && patients.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (patients.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          children: [
            _EmptyState(error: error),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: patients.length + 1, // +1 for the header card
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _ListHeader(count: patients.length);
          }
          final patient = patients[index - 1];
          return _PatientTile(
            patient: patient,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DoctorPatientDetailScreen(patient: patient),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? 'patient sharing' : 'patients sharing';
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.people_alt_outlined,
              color: AppTheme.textSecondary(context), size: 18),
          const SizedBox(width: 8),
          Text(
            '$count $label',
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({required this.patient, required this.onTap});

  final DoctorPatient patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = patient.latestScan;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              _PatientAvatar(initials: patient.initials),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.displayLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitleFor(latest),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (latest != null) ...[
                const SizedBox(width: 8),
                _SeverityChip(
                  label: latest.severityLabel,
                  color: _severityColor(latest.cookGrade),
                ),
              ],
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary(context), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleFor(DoctorScanSummary? latest) {
    if (latest == null) return 'No scans yet';
    final age = DateTime.now().difference(latest.takenAt);
    if (age.inMinutes < 1) return 'Last scan just now';
    if (age.inMinutes < 60) return 'Last scan ${age.inMinutes}m ago';
    if (age.inHours < 24) return 'Last scan ${age.inHours}h ago';
    if (age.inDays < 7) return 'Last scan ${age.inDays}d ago';
    if (age.inDays < 30) return 'Last scan ${(age.inDays / 7).floor()}w ago';
    return 'Last scan ${(age.inDays / 30).floor()}mo ago';
  }

  static Color _severityColor(int cookGrade) {
    if (cookGrade < 0) return const Color(0xFF4CAF50);
    if (cookGrade <= 1) return const Color(0xFF4CAF50);
    if (cookGrade <= 3) return const Color(0xFF8BC34A);
    if (cookGrade <= 5) return const Color(0xFFFFC107);
    if (cookGrade <= 7) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          hasError ? Icons.error_outline : Icons.inbox_outlined,
          size: 56,
          color: AppTheme.textSecondary(context),
        ),
        const SizedBox(height: 16),
        Text(
          hasError ? 'Could not load patients' : 'No patients sharing yet',
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
              : 'Patients who toggle "Share with my dermatologist" in their profile will appear here. Pull to refresh.',
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
