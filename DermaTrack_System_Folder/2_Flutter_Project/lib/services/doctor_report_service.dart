import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/patient_history.dart';
import '../models/scan.dart';
import '../models/treatment_plan.dart';
import 'doctor_service.dart';

/// Builds and shares a one- or two-page PDF summary of a patient for the
/// dermatologist: identity, current treatment plan, medical-history snapshot,
/// scan statistics, a recent-scans table, and the latest scan image.
///
/// Stateless utility — all inputs are passed in (the doctor screens already
/// hold them via DoctorService), so this has no dependency on the widget tree
/// and can be unit-tested in isolation.
class DoctorReportService {
  const DoctorReportService._();

  static final PdfColor _accent = PdfColor.fromInt(0xFF1F8A8A);
  static final PdfColor _muted = PdfColor.fromInt(0xFF6B7280);

  /// Generates the report PDF and opens the OS share/print sheet. [scans] is
  /// expected newest-first (the order DoctorService returns). Throws on
  /// failure so the caller can surface a snackbar.
  static Future<void> sharePatientReport({
    required DoctorPatient patient,
    required List<Scan> scans,
    PatientHistory? history,
    TreatmentPlan? plan,
  }) async {
    final doc = pw.Document();
    final generatedAt = DateTime.now();

    // Best-effort fetch of the latest scan's image. If the signed URL has
    // expired or the network hiccups, we simply omit the image rather than
    // failing the whole export.
    pw.ImageProvider? latestImage;
    final latest = scans.isNotEmpty ? scans.first : null;
    if (latest?.imageUrl != null) {
      try {
        latestImage = await networkImage(latest!.imageUrl!);
      } catch (e) {
        debugPrint('DoctorReportService: latest scan image fetch failed: $e');
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 42),
        footer: (ctx) => _footer(ctx, generatedAt),
        build: (ctx) => [
          _header(patient),
          pw.SizedBox(height: 14),
          _treatmentPlanSection(plan),
          pw.SizedBox(height: 14),
          _scanStatsSection(scans),
          pw.SizedBox(height: 14),
          if (latestImage != null) ...[
            _latestScanSection(latest!, latestImage),
            pw.SizedBox(height: 14),
          ],
          _recentScansTable(scans),
          pw.SizedBox(height: 14),
          _medicalHistorySection(history),
        ],
      ),
    );

    final bytes = await doc.save();
    final safeName = patient.displayLabel
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final stamp =
        '${generatedAt.year}${_2(generatedAt.month)}${_2(generatedAt.day)}';
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'dermatrack_${safeName.isEmpty ? 'patient' : safeName}_$stamp.pdf',
    );
  }

  // ===== Sections =====

  static pw.Widget _header(DoctorPatient patient) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('DermaTrack',
                style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _accent)),
            pw.Text('Patient report',
                style: pw.TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
        pw.Divider(color: _accent, thickness: 1.4),
        pw.SizedBox(height: 4),
        pw.Text(patient.displayLabel,
            style:
                pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('@${patient.username}',
            style: pw.TextStyle(fontSize: 10, color: _muted)),
      ],
    );
  }

  static pw.Widget _treatmentPlanSection(TreatmentPlan? plan) {
    final hasPlan = plan != null && plan.plan.trim().isNotEmpty;
    return _card(
      title: 'Treatment plan',
      child: hasPlan
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(plan.plan.trim(),
                    style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
                if (plan.updatedAt != null) ...[
                  pw.SizedBox(height: 6),
                  pw.Text('Last updated ${_fmtDate(plan.updatedAt!)}',
                      style: pw.TextStyle(fontSize: 9, color: _muted)),
                ],
              ],
            )
          : pw.Text('No treatment plan recorded yet.',
              style: pw.TextStyle(
                  fontSize: 11,
                  color: _muted,
                  fontStyle: pw.FontStyle.italic)),
    );
  }

  static pw.Widget _scanStatsSection(List<Scan> scans) {
    if (scans.isEmpty) {
      return _card(
        title: 'Scan summary',
        child: pw.Text('No scans shared.',
            style: pw.TextStyle(
                fontSize: 11, color: _muted, fontStyle: pw.FontStyle.italic)),
      );
    }
    // scans newest-first → first is latest, last is earliest.
    final latest = scans.first;
    final earliest = scans.last;
    return _card(
      title: 'Scan summary',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _kv('Total scans', '${scans.length}'),
          _kv('Date range',
              '${_fmtDate(earliest.takenAt)}  to  ${_fmtDate(latest.takenAt)}'),
          _kv('Latest grade',
              '${_gradeText(latest.cookGrade)}  (${latest.severityLabel})'),
          _kv('Latest lesion counts',
              'Inflammatory ${latest.inflammatoryCount} · '
                  'Non-inflammatory ${latest.nonInflammatoryCount} · '
                  'Post-acne ${latest.postAcneCount}'),
        ],
      ),
    );
  }

  static pw.Widget _latestScanSection(Scan latest, pw.ImageProvider image) {
    return _card(
      title: 'Latest scan · ${_fmtDate(latest.takenAt)}',
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.Image(image, width: 120, height: 120,
                fit: pw.BoxFit.cover),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(latest.severityLabel,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(_gradeText(latest.cookGrade),
                    style: pw.TextStyle(fontSize: 10, color: _muted)),
                pw.SizedBox(height: 6),
                pw.Text('Region: ${latest.region.label}',
                    style: const pw.TextStyle(fontSize: 10)),
                if ((latest.notes ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text('Patient note: ${latest.notes!.trim()}',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
                if ((latest.doctorNote ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('Doctor note: ${latest.doctorNote!.trim()}',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _recentScansTable(List<Scan> scans) {
    if (scans.isEmpty) return pw.SizedBox();
    final rows = scans.take(12).toList(); // cap so the table stays one-ish page
    return _card(
      title: 'Recent scans',
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE0E0E0)),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.2),
          1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(2.4),
          4: const pw.FlexColumnWidth(1.4),
        },
        children: [
          _tableHeaderRow(
              ['Date', 'Region', 'Grade', 'Severity', 'Lesions']),
          for (final s in rows)
            pw.TableRow(children: [
              _td(_fmtDate(s.takenAt)),
              _td(s.region.label),
              _td(_gradeText(s.cookGrade)),
              _td(s.severityLabel),
              _td('${s.inflammatoryCount + s.nonInflammatoryCount + s.postAcneCount}'),
            ]),
        ],
      ),
    );
  }

  static pw.Widget _medicalHistorySection(PatientHistory? history) {
    if (history == null) {
      return _card(
        title: 'Medical history',
        child: pw.Text("Patient hasn't filled in their medical history yet.",
            style: pw.TextStyle(
                fontSize: 11, color: _muted, fontStyle: pw.FontStyle.italic)),
      );
    }
    final about = <String>[];
    if ((history.fullName ?? '').trim().isNotEmpty) {
      about.add(history.fullName!.trim());
    }
    if (history.birthday != null) {
      about.add('Born ${_fmtDate(history.birthday!)}');
    }
    if (history.sex != null) {
      about.add(kSexOptions[history.sex] ?? history.sex!);
    }
    if ((history.occupation ?? '').trim().isNotEmpty) {
      about.add('Occupation: ${history.occupation!.trim()}');
    }
    if ((history.contactNo ?? '').trim().isNotEmpty) {
      about.add('Contact: ${history.contactNo!.trim()}');
    }

    final past = <String>[];
    if (history.pastMedicalConditions.isNotEmpty) {
      past.add(history.pastMedicalConditions
          .map((k) => kPastMedicalConditions[k] ?? k)
          .join(', '));
    }
    if ((history.allergiesDetail ?? '').trim().isNotEmpty) {
      past.add('Allergies: ${history.allergiesDetail!.trim()}');
    }
    if ((history.previousSurgeryDetail ?? '').trim().isNotEmpty) {
      past.add('Previous surgery: ${history.previousSurgeryDetail!.trim()}');
    }
    if ((history.pastMedicalOthers ?? '').trim().isNotEmpty) {
      past.add('Others: ${history.pastMedicalOthers!.trim()}');
    }

    final family = <String>[];
    if (history.familyHistoryConditions.isNotEmpty) {
      family.add(history.familyHistoryConditions
          .map((k) => kFamilyHistoryConditions[k] ?? k)
          .join(', '));
    }
    if ((history.familyHistoryOthers ?? '').trim().isNotEmpty) {
      family.add('Others: ${history.familyHistoryOthers!.trim()}');
    }

    final social = <String>[];
    if (history.smokerPackYears != null) {
      social.add('Smoker · ${history.smokerPackYears!.toStringAsFixed(0)} pack-years');
    }
    if (history.usesProhibitedDrugs) social.add('Uses prohibited drugs');
    if (history.isAlcoholDrinker) social.add('Alcoholic beverage drinker');
    if ((history.socialOthers ?? '').trim().isNotEmpty) {
      social.add('Others: ${history.socialOthers!.trim()}');
    }

    final meds = (history.currentMedications ?? '').trim();

    return _card(
      title: 'Medical history',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _historyBlock('About', about),
          _historyBlock('Past medical history', past),
          _historyBlock('Family history', family),
          _historyBlock('Personal and social history', social),
          if (meds.isNotEmpty) _historyBlock('Current medications', [meds]),
        ],
      ),
    );
  }

  // ===== Small building blocks =====

  static pw.Widget _card({required String title, required pw.Widget child}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromInt(0xFFDDDDDD)),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _accent,
                  letterSpacing: 0.5)),
          pw.SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  static pw.Widget _kv(String key, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(key,
                style: pw.TextStyle(fontSize: 10, color: _muted)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _historyBlock(String title, List<String> lines) {
    final content = lines.where((l) => l.trim().isNotEmpty).toList();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(content.isEmpty ? '—' : content.join('\n'),
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.5)),
        ],
      ),
    );
  }

  static pw.TableRow _tableHeaderRow(List<String> cells) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F4F4)),
      children: [
        for (final c in cells)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: pw.Text(c,
                style: pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
      ],
    );
  }

  static pw.Widget _td(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
      );

  static pw.Widget _footer(pw.Context ctx, DateTime generatedAt) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Generated ${_fmtDateTime(generatedAt)}   ·   Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
    );
  }

  // ===== Formatting =====

  static String _gradeText(int cookGrade) =>
      cookGrade < 0 ? 'Clear' : 'Cook $cookGrade';

  static String _fmtDate(DateTime d) =>
      '${d.year}-${_2(d.month)}-${_2(d.day)}';

  static String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${_2(d.hour)}:${_2(d.minute)}';

  static String _2(int n) => n.toString().padLeft(2, '0');
}
