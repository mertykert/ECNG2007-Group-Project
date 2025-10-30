// ============================================================================
// lib/features/Medication/add_medication.dart  (FINAL – matches MedicationForm)
// ============================================================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'medication_form.dart';

class AddMedicationScreen extends StatelessWidget {
  const AddMedicationScreen({
    super.key,
    this.initialDate,
    this.ownerId, // optional override for caregivers
  });

  final DateTime? initialDate;
  final String? ownerId;

  @override
  Widget build(BuildContext context) {
    final String uid = ownerId ?? FirebaseAuth.instance.currentUser!.uid;
    // Single source of truth: reuse the shared form
    return MedicationForm(
      mode: MedicationFormMode.add,
      ownerId: uid,
      initialDate: initialDate,
    );
  }
}