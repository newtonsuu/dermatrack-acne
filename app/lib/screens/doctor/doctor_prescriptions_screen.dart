import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/prescription.dart';
import '../../services/doctor_service.dart';
import '../../services/prescription_service.dart';
import '../../theme/app_theme.dart';

/// Doctor-side prescriptions for one patient: a dated list of prescriptions
/// (text + image attachments) the dermatologist has sent, with a composer to
/// add a new one. Writes are RLS-gated to consenting patients (migration 0008).
class DoctorPrescriptionsScreen extends StatefulWidget {
  const DoctorPrescriptionsScreen({super.key, required this.patient});

  final DoctorPatient patient;

  @override
  State<DoctorPrescriptionsScreen> createState() =>
      _DoctorPrescriptionsScreenState();
}

class _DoctorPrescriptionsScreenState
    extends State<DoctorPrescriptionsScreen> {
  @override
  void initState() {
    super.initState();
    PrescriptionService.instance.addListener(_onChanged);
    PrescriptionService.instance.loadForPatient(widget.patient.id);
  }

  @override
  void dispose() {
    PrescriptionService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() =>
      PrescriptionService.instance.loadForPatient(widget.patient.id, force: true);

  @override
  Widget build(BuildContext context) {
    final svc = PrescriptionService.instance;
    final items = svc.forPatient(widget.patient.id);
    final loading = svc.isLoadingFor(widget.patient.id) &&
        !svc.hasLoadedFor(widget.patient.id);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: Text('Prescriptions · ${widget.patient.displayLabel}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openComposer,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
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
                          'Tap "New" to send ${widget.patient.displayLabel} a prescription with instructions and optional photos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary(context),
                            height: 1.4,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _PrescriptionCard(
                        prescription: items[i],
                        onDelete: () => _confirmDelete(items[i]),
                      ),
                    ),
            ),
    );
  }

  Future<void> _confirmDelete(Prescription p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete prescription?'),
        content: const Text(
            'This removes it (and its images) for the patient too.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PrescriptionService.instance
          .deletePrescription(patientId: widget.patient.id, prescription: p);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't delete: $e")));
      }
    }
  }

  Future<void> _openComposer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PrescriptionComposer(patient: widget.patient),
    );
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.prescription, required this.onDelete});

  final Prescription prescription;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final d = prescription.createdAt;
    final dateStr =
        '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medication_outlined,
                    size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete',
                  color: Colors.red.shade400,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                prescription.body,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
            if (prescription.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ImageStrip(urls: prescription.imageUrls),
            ],
          ],
        ),
      ),
    );
  }

  static String _2(int n) => n.toString().padLeft(2, '0');
}

/// Horizontal strip of attachment thumbnails; tap to view full-screen.
class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: InteractiveViewer(
                child: Image.network(urls[i], fit: BoxFit.contain),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              urls[i],
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 84,
                height: 84,
                color: Colors.black12,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet composer: prescription text + optional image attachments.
class _PrescriptionComposer extends StatefulWidget {
  const _PrescriptionComposer({required this.patient});
  final DoctorPatient patient;

  @override
  State<_PrescriptionComposer> createState() => _PrescriptionComposerState();
}

class _PrescriptionComposerState extends State<_PrescriptionComposer> {
  final TextEditingController _controller = TextEditingController();
  final List<Uint8List> _images = [];
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      for (final x in picked) {
        _images.add(await x.readAsBytes());
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't pick images: $e")));
      }
    }
  }

  Future<void> _save() async {
    final body = _controller.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add prescription instructions first.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await PrescriptionService.instance.addPrescription(
        patientId: widget.patient.id,
        body: body,
        images: _images,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't send: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New prescription for ${widget.patient.displayLabel}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText:
                  'e.g. Adapalene 0.1% gel nightly for 8 weeks; clindamycin in the morning. Avoid sun; use SPF 30+.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_images.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_images[i],
                          width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _saving ? null : _pickImages,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Attach images'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
