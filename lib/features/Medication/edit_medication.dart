// ============================================================================
// lib/features/Medication/edit_medication.dart
// New screen that reuses the same form in EDIT mode.
// ============================================================================
import 'package:flutter/material.dart';
import 'medication_form.dart';

class EditMedicationScreen extends StatelessWidget {
  final String ownerId;
  final String medId;
  const EditMedicationScreen({
    super.key,
    required this.ownerId,
    required this.medId,
  });

  @override
  Widget build(BuildContext context) {
    return MedicationForm(
      mode: MedicationFormMode.edit,
      ownerId: ownerId,
      medId: medId,
    );
  }
}
