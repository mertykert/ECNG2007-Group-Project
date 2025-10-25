// ============================================================================
// lib/features/Medication/add_medication.dart
// Wraps the form in ADD mode (keeps your route/component name).
// ============================================================================
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'medication_form.dart';

class AddMedicationScreen extends StatelessWidget {
  final DateTime? initialDate;
  const AddMedicationScreen({super.key, this.initialDate});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return MedicationForm(
      mode: MedicationFormMode.add,
      ownerId: uid,
      initialDate: initialDate,
    );
  }
}
