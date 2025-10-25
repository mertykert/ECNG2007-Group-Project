// lib/widgets/app_snackbars.dart
import 'package:flutter/material.dart';

SnackBar _buildSnack({
  required Color bg,
  required IconData icon,
  required String message,
}) {
  return SnackBar(
    content: Row(
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ],
    ),
    backgroundColor: bg,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 2),
    elevation: 3,
  );
}

// BLUE – used after add (keep for consistency)
void showMedicationAddedSuccess(BuildContext context, {String? name}) {
  final msg = (name == null || name.trim().isEmpty)
      ? 'Medication added successfully!'
      : 'Medication "$name" added successfully!';
  final m = ScaffoldMessenger.of(context)..clearSnackBars();
  m.showSnackBar(_buildSnack(
    bg: const Color(0xFF2d59f0),
    icon: Icons.check_circle_rounded,
    message: msg,
  ));
}

// RED – used after delete (final canonical signature)
void showMedicationDeletedSuccess(BuildContext context, {String? name}) {
  final msg = (name == null || name.trim().isEmpty)
      ? 'Medication deleted successfully!'
      : 'Medication "$name" deleted successfully!';
  final m = ScaffoldMessenger.of(context)..clearSnackBars();
  m.showSnackBar(_buildSnack(
    bg: const Color(0xFFE53935),
    icon: Icons.delete_forever_rounded,
    message: msg,
  ));
}
