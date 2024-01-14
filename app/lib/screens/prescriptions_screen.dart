import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../models/prescription.dart';
import '../services/prescription_service.dart';
import '../theme/app_theme.dart';

/// Patient-side, read-only view of prescriptions their dermatologist has sent
/// (text + image attachments). Backed by the same PrescriptionService; RLS
/// limits the patient to their own rows.
class PrescriptionsScreen extends StatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  State<PrescriptionsScreen> createState() => _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends State<PrescriptionsScreen> {
  String? get _uid => supa.Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    PrescriptionService.instance.addListener(_onChanged);
    final id = _uid;
    if (id != null) PrescriptionService.instance.loadForPatient(id);
  }

  @override
  void dispose() {
    PrescriptionService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = _uid;
    final svc = PrescriptionService.instance;
    final items = id == null ? <Prescription>[] : svc.forPatient(id);
    final loading =
        id != null && svc.isLoadingFor(id) && !svc.hasLoadedFor(id);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Prescriptions')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                if (id != null) {
                  await svc.loadForPatient(id, force: true);
                }
              },
              child: items.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 64),
                      children: [
                        Icon(Icons.medication_outlined,
                            size: 52, color: AppTheme.textSecondary(context)),
                        const SizedBox(height: 14),
                        Text(
                          'No prescriptions yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Prescriptions your dermatologist sends will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _PatientPrescriptionCard(items[i]),
                    ),
            ),
    );
  }
}

class _PatientPrescriptionCard extends StatelessWidget {
  const _PatientPrescriptionCard(this.prescription);
  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final d = prescription.createdAt;
    final dateStr = '${d.year}-${_2(d.month)}-${_2(d.day)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medical_services_outlined,
                    size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(
                  'From your dermatologist · $dateStr',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              prescription.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppTheme.textPrimary(context),
              ),
            ),
            if (prescription.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: prescription.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(
                          child: Image.network(prescription.imageUrls[i],
                              fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        prescription.imageUrls[i],
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 90,
                          height: 90,
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _2(int n) => n.toString().padLeft(2, '0');
}
