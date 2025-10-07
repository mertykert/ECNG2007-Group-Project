import 'package:flutter/material.dart';

class CaregiverScreen extends StatelessWidget {
  const CaregiverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Care Giver Section")),
      body: const Center(child: Text("Welcome Care Giver!")),
    );
  }
}