import 'package:flutter/material.dart';

import '../../models/patient_history.dart';
import '../../services/patient_history_service.dart';
import '../../theme/app_theme.dart';

/// Editable clinical-intake form for the patient.
///
/// Mirrors the OPD Medical Record form Dr. Christine Ann Olivete-Agdamag
/// uses at her aesthetic dermatology clinic — same sections, same
/// checkbox options. All fields are optional from the patient's
/// perspective; they can save with zero fields filled.
///
/// Reached from the "Medical history" card on the profile screen.
/// Saving returns to the profile screen.
class PatientHistoryScreen extends StatefulWidget {
  const PatientHistoryScreen({super.key});

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> {
  // Backing draft — what the user has edited but not yet saved. We start
  // from whatever PatientHistoryService has loaded (or PatientHistory.empty
  // if no row exists yet) and mutate via copyWith on each field change.
  late PatientHistory _draft;
  bool _isSaving = false;

  // Text controllers for the free-text fields. We keep them as instance
  // state (rather than rebuilding them on every change) so the user's
  // cursor position survives setState calls.
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _occupationCtrl;
  late final TextEditingController _contactNoCtrl;
  late final TextEditingController _pastMedicalOthersCtrl;
  late final TextEditingController _previousSurgeryCtrl;
  late final TextEditingController _allergiesCtrl;
  late final TextEditingController _familyHistoryOthersCtrl;
  late final TextEditingController _socialOthersCtrl;
  late final TextEditingController _currentMedicationsCtrl;
  late final TextEditingController _smokerPackYearsCtrl;

  @override
  void initState() {
    super.initState();
    _draft = PatientHistoryService.instance.history ?? PatientHistory.empty;

    _fullNameCtrl = TextEditingController(text: _draft.fullName ?? '');
    _addressCtrl = TextEditingController(text: _draft.address ?? '');
    _occupationCtrl = TextEditingController(text: _draft.occupation ?? '');
    _contactNoCtrl = TextEditingController(text: _draft.contactNo ?? '');
    _pastMedicalOthersCtrl =
        TextEditingController(text: _draft.pastMedicalOthers ?? '');
    _previousSurgeryCtrl =
        TextEditingController(text: _draft.previousSurgeryDetail ?? '');
    _allergiesCtrl = TextEditingController(text: _draft.allergiesDetail ?? '');
    _familyHistoryOthersCtrl =
        TextEditingController(text: _draft.familyHistoryOthers ?? '');
    _socialOthersCtrl = TextEditingController(text: _draft.socialOthers ?? '');
    _currentMedicationsCtrl =
        TextEditingController(text: _draft.currentMedications ?? '');
    _smokerPackYearsCtrl = TextEditingController(
      text: _draft.smokerPackYears?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _addressCtrl.dispose();
    _occupationCtrl.dispose();
    _contactNoCtrl.dispose();
    _pastMedicalOthersCtrl.dispose();
    _previousSurgeryCtrl.dispose();
    _allergiesCtrl.dispose();
    _familyHistoryOthersCtrl.dispose();
    _socialOthersCtrl.dispose();
    _currentMedicationsCtrl.dispose();
    _smokerPackYearsCtrl.dispose();
    super.dispose();
  }

  // ---- Field mutators (apply controller values to draft before save) ----

  PatientHistory _draftFromControllers() {
    double? parsedPackYears;
    final raw = _smokerPackYearsCtrl.text.trim();
    if (raw.isNotEmpty) {
      parsedPackYears = double.tryParse(raw);
    }
    return _draft.copyWith(
      fullName: _fullNameCtrl.text,
      address: _addressCtrl.text,
      occupation: _occupationCtrl.text,
      contactNo: _contactNoCtrl.text,
      pastMedicalOthers: _pastMedicalOthersCtrl.text,
      previousSurgeryDetail: _previousSurgeryCtrl.text,
      allergiesDetail: _allergiesCtrl.text,
      familyHistoryOthers: _familyHistoryOthersCtrl.text,
      socialOthers: _socialOthersCtrl.text,
      currentMedications: _currentMedicationsCtrl.text,
      smokerPackYears: parsedPackYears,
    );
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await PatientHistoryService.instance.upsert(_draftFromControllers());
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medical history saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save: $e")),
      );
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _draft.birthday ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _draft = _draft.copyWith(birthday: picked);
      });
    }
  }

  // ----- Build -----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Medical history'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _onSave,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _PrivacyBanner(),
          const SizedBox(height: 16),
          _DemographicsSection(
            draft: _draft,
            fullNameCtrl: _fullNameCtrl,
            addressCtrl: _addressCtrl,
            occupationCtrl: _occupationCtrl,
            contactNoCtrl: _contactNoCtrl,
            onPickBirthday: _pickBirthday,
            onSexChanged: (key) {
              setState(() => _draft = _draft.copyWith(sex: key));
            },
          ),
          const SizedBox(height: 16),
          _ChecklistSection(
            title: 'Past medical history',
            options: kPastMedicalConditions,
            selected: _draft.pastMedicalConditions,
            onChanged: (next) {
              setState(() {
                _draft =
                    _draft.copyWith(pastMedicalConditions: next);
              });
            },
            othersController: _pastMedicalOthersCtrl,
            extraFields: [
              _ExtraField(
                label: 'Previous surgery / hospitalization',
                controller: _previousSurgeryCtrl,
              ),
              _ExtraField(
                label: 'Allergies — details',
                controller: _allergiesCtrl,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ChecklistSection(
            title: 'Family history',
            options: kFamilyHistoryConditions,
            selected: _draft.familyHistoryConditions,
            onChanged: (next) {
              setState(() {
                _draft =
                    _draft.copyWith(familyHistoryConditions: next);
              });
            },
            othersController: _familyHistoryOthersCtrl,
          ),
          const SizedBox(height: 16),
          _SocialHistorySection(
            draft: _draft,
            packYearsCtrl: _smokerPackYearsCtrl,
            othersCtrl: _socialOthersCtrl,
            onSmokerToggle: (smoker) {
              setState(() {
                _draft = _draft.copyWith(
                  smokerPackYears: smoker ? (_draft.smokerPackYears ?? 0) : null,
                );
                if (!smoker) _smokerPackYearsCtrl.text = '';
              });
            },
            onProhibitedDrugsChanged: (v) {
              setState(() => _draft = _draft.copyWith(usesProhibitedDrugs: v));
            },
            onAlcoholChanged: (v) {
              setState(() => _draft = _draft.copyWith(isAlcoholDrinker: v));
            },
          ),
          const SizedBox(height: 16),
          _FreeTextSection(
            title: 'Current medications',
            hint: 'List anything you take regularly — prescription, OTC, '
                'supplements. One per line is fine.',
            controller: _currentMedicationsCtrl,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSaving ? null : _onSave,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Section widgets
// ============================================

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Everything is optional. Your dermatologist sees this only '
              'after you turn on "Share with my dermatologist" on your '
              'profile.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemographicsSection extends StatelessWidget {
  const _DemographicsSection({
    required this.draft,
    required this.fullNameCtrl,
    required this.addressCtrl,
    required this.occupationCtrl,
    required this.contactNoCtrl,
    required this.onPickBirthday,
    required this.onSexChanged,
  });

  final PatientHistory draft;
  final TextEditingController fullNameCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController occupationCtrl;
  final TextEditingController contactNoCtrl;
  final VoidCallback onPickBirthday;
  final ValueChanged<String?> onSexChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'About you',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabelledField(
            label: 'Full name',
            child: TextField(
              controller: fullNameCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Surname, Given Name M.I.',
              ),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 12),
          _LabelledField(
            label: 'Address',
            child: TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LabelledField(
                  label: 'Birthday',
                  child: OutlinedButton(
                    onPressed: onPickBirthday,
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    child: Text(
                      draft.birthday == null
                          ? 'Pick a date'
                          : '${draft.birthday!.year}-${_2(draft.birthday!.month)}-${_2(draft.birthday!.day)}',
                      style: TextStyle(
                        color: draft.birthday == null
                            ? AppTheme.textSecondary(context)
                            : AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LabelledField(
                  label: 'Sex',
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.sex,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final entry in kSexOptions.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: onSexChanged,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LabelledField(
            label: 'Occupation',
            child: TextField(
              controller: occupationCtrl,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 12),
          _LabelledField(
            label: 'Contact number',
            child: TextField(
              controller: contactNoCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              textInputAction: TextInputAction.done,
            ),
          ),
        ],
      ),
    );
  }

  static String _2(int n) => n.toString().padLeft(2, '0');
}

class _ExtraField {
  const _ExtraField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;
}

class _ChecklistSection extends StatelessWidget {
  const _ChecklistSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.othersController,
    this.extraFields = const [],
  });

  final String title;
  final Map<String, String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final TextEditingController othersController;
  final List<_ExtraField> extraFields;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in options.entries)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(entry.value),
              value: selected.contains(entry.key),
              onChanged: (v) {
                final next = List<String>.from(selected);
                if (v == true) {
                  if (!next.contains(entry.key)) next.add(entry.key);
                } else {
                  next.remove(entry.key);
                }
                onChanged(next);
              },
            ),
          const SizedBox(height: 8),
          _LabelledField(
            label: 'Others',
            child: TextField(
              controller: othersController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Add anything not listed above.',
              ),
            ),
          ),
          for (final f in extraFields) ...[
            const SizedBox(height: 12),
            _LabelledField(
              label: f.label,
              child: TextField(
                controller: f.controller,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SocialHistorySection extends StatelessWidget {
  const _SocialHistorySection({
    required this.draft,
    required this.packYearsCtrl,
    required this.othersCtrl,
    required this.onSmokerToggle,
    required this.onProhibitedDrugsChanged,
    required this.onAlcoholChanged,
  });

  final PatientHistory draft;
  final TextEditingController packYearsCtrl;
  final TextEditingController othersCtrl;
  final ValueChanged<bool> onSmokerToggle;
  final ValueChanged<bool> onProhibitedDrugsChanged;
  final ValueChanged<bool> onAlcoholChanged;

  @override
  Widget build(BuildContext context) {
    final isSmoker = draft.smokerPackYears != null;
    return _SectionCard(
      title: 'Personal and social history',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Smoker'),
            value: isSmoker,
            onChanged: (v) => onSmokerToggle(v == true),
          ),
          if (isSmoker) ...[
            const SizedBox(height: 4),
            _LabelledField(
              label: 'Pack-years',
              child: TextField(
                controller: packYearsCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 5',
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Prohibited drugs'),
            value: draft.usesProhibitedDrugs,
            onChanged: (v) => onProhibitedDrugsChanged(v == true),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Alcoholic beverage drinker'),
            value: draft.isAlcoholDrinker,
            onChanged: (v) => onAlcoholChanged(v == true),
          ),
          const SizedBox(height: 8),
          _LabelledField(
            label: 'Others',
            child: TextField(
              controller: othersCtrl,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeTextSection extends StatelessWidget {
  const _FreeTextSection({
    required this.title,
    required this.hint,
    required this.controller,
  });

  final String title;
  final String hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      child: TextField(
        controller: controller,
        maxLines: 5,
        minLines: 3,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: hint,
        ),
      ),
    );
  }
}

// ============================================
// Layout helpers
// ============================================

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabelledField extends StatelessWidget {
  const _LabelledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
