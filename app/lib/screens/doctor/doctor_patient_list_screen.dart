import 'package:flutter/material.dart';

import '../../services/doctor_service.dart';
import '../../theme/app_theme.dart';
import 'doctor_patient_detail_screen.dart';

/// How the patient list is ordered. Recent (most recent scan first) is the
/// default the dermatologist opens to; severity surfaces the patients doing
/// worst; name is the predictable A–Z fallback.
enum _PatientSort {
  recent('Recent'),
  severity('Severity'),
  name('Name');

  const _PatientSort(this.label);
  final String label;
}

/// List of patients who have toggled "Share with my dermatologist" on.
///
/// Each row shows the patient's display name, their last scan timestamp,
/// and a severity chip for their most recent grade. Tapping a row opens the
/// patient detail view.
///
/// A search field + sort control + "Needs review" filter sit above the list
/// so the dermatologist can find a patient by name, surface the most severe
/// cases first, or focus only on patients whose latest scan hasn't been
/// annotated yet. All three operate client-side over the already-loaded
/// patient list — no extra round-trips.
///
/// Pull-to-refresh re-runs DoctorService.loadPatients so the list reflects
/// recent opt-ins / opt-outs without restarting the app.
class DoctorPatientListScreen extends StatefulWidget {
  const DoctorPatientListScreen({super.key});

  @override
  State<DoctorPatientListScreen> createState() =>
      _DoctorPatientListScreenState();
}

class _DoctorPatientListScreenState extends State<DoctorPatientListScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  _PatientSort _sort = _PatientSort.recent;
  bool _needsReviewOnly = false;

  @override
  void initState() {
    super.initState();
    DoctorService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    DoctorService.instance.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() => DoctorService.instance.loadPatients();

  /// Applies the active search query, "needs review" filter, and sort to the
  /// service's patient list. Pure — derives the visible list from inputs.
  List<DoctorPatient> _visible(List<DoctorPatient> all) {
    final q = _query.trim().toLowerCase();
    final filtered = all.where((p) {
      if (_needsReviewOnly) {
        final latest = p.latestScan;
        // "Needs review" = the patient has a most-recent scan that the
        // doctor hasn't annotated yet. Patients with no scans aren't
        // actionable, so they drop out of this filter.
        if (latest == null || latest.hasDoctorNote) return false;
      }
      if (q.isEmpty) return true;
      return p.displayLabel.toLowerCase().contains(q) ||
          p.username.toLowerCase().contains(q);
    }).toList();

    int byRecent(DoctorPatient a, DoctorPatient b) {
      final aDate = a.latestScan?.takenAt;
      final bDate = b.latestScan?.takenAt;
      if (aDate != null && bDate != null) return bDate.compareTo(aDate);
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return a.displayLabel
          .toLowerCase()
          .compareTo(b.displayLabel.toLowerCase());
    }

    switch (_sort) {
      case _PatientSort.recent:
        filtered.sort(byRecent);
        break;
      case _PatientSort.severity:
        // Worst grade first. Patients with no scan have no grade, so they
        // sink to the bottom; ties fall back to most-recent then name.
        filtered.sort((a, b) {
          final aGrade = a.latestScan?.cookGrade;
          final bGrade = b.latestScan?.cookGrade;
          if (aGrade != null && bGrade != null && aGrade != bGrade) {
            return bGrade.compareTo(aGrade);
          }
          if (aGrade != null && bGrade == null) return -1;
          if (aGrade == null && bGrade != null) return 1;
          return byRecent(a, b);
        });
        break;
      case _PatientSort.name:
        filtered.sort((a, b) => a.displayLabel
            .toLowerCase()
            .compareTo(b.displayLabel.toLowerCase()));
        break;
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final service = DoctorService.instance;
    final all = service.patients;
    final isLoading = service.isLoadingPatients;
    final error = service.patientsError;

    // First-time load with no cached data → centered spinner. Subsequent
    // refreshes keep the existing list visible so the doctor isn't staring
    // at a blank screen during pull-to-refresh.
    if (isLoading && all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // No patients sharing at all → just the empty state, no controls (there's
    // nothing to search or filter).
    if (all.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          children: [_EmptyState(error: error)],
        ),
      );
    }

    final visible = _visible(all);
    final needsReviewCount = all
        .where((p) => p.latestScan != null && !p.latestScan!.hasDoctorNote)
        .length;

    return Column(
      children: [
        _Controls(
          searchController: _searchController,
          onQueryChanged: (v) => setState(() => _query = v),
          sort: _sort,
          onSortChanged: (s) => setState(() => _sort = s),
          needsReviewOnly: _needsReviewOnly,
          needsReviewCount: needsReviewCount,
          onNeedsReviewToggled: (v) => setState(() => _needsReviewOnly = v),
          totalCount: all.length,
          visibleCount: visible.length,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: visible.isEmpty
                ? ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 48),
                    children: const [_NoMatchesState()],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final patient = visible[index];
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
          ),
        ),
      ],
    );
  }
}

/// Search field + sort selector + "Needs review" filter chip, plus a small
/// count line so the doctor always knows how many of the total are showing.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.searchController,
    required this.onQueryChanged,
    required this.sort,
    required this.onSortChanged,
    required this.needsReviewOnly,
    required this.needsReviewCount,
    required this.onNeedsReviewToggled,
    required this.totalCount,
    required this.visibleCount,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final _PatientSort sort;
  final ValueChanged<_PatientSort> onSortChanged;
  final bool needsReviewOnly;
  final int needsReviewCount;
  final ValueChanged<bool> onNeedsReviewToggled;
  final int totalCount;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search patients by name',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear',
                      onPressed: () {
                        searchController.clear();
                        onQueryChanged('');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          // Sort chips + the needs-review filter, wrapped so they reflow on
          // narrow widths instead of overflowing the row.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.sort,
                  size: 18, color: AppTheme.textSecondary(context)),
              for (final s in _PatientSort.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: sort == s,
                  onSelected: (_) => onSortChanged(s),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12.5),
                ),
              FilterChip(
                avatar: Icon(
                  Icons.assignment_late_outlined,
                  size: 16,
                  color: needsReviewOnly
                      ? AppTheme.accent
                      : AppTheme.textSecondary(context),
                ),
                label: Text('Needs review ($needsReviewCount)'),
                selected: needsReviewOnly,
                onSelected: onNeedsReviewToggled,
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            visibleCount == totalCount
                ? '$totalCount ${totalCount == 1 ? 'patient' : 'patients'} sharing'
                : 'Showing $visibleCount of $totalCount',
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontSize: 12.5,
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
    final needsReview = latest != null && !latest.hasDoctorNote;
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
                    if (needsReview) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.assignment_late_outlined,
                              size: 13, color: AppTheme.accent),
                          const SizedBox(width: 4),
                          Text(
                            'Needs review',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    ],
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

/// Shown when patients exist but none match the active search/filter. Distinct
/// from [_EmptyState] (which means "no patients are sharing at all").
class _NoMatchesState extends StatelessWidget {
  const _NoMatchesState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search_off,
            size: 48, color: AppTheme.textSecondary(context)),
        const SizedBox(height: 14),
        Text(
          'No patients match',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Try a different name, clear the search, or turn off the '
          '"Needs review" filter.',
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
