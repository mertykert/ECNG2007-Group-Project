import 'package:flutter/material.dart';

class CarereceiverScreen extends StatelessWidget {
  const CarereceiverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Care Receiver Section")),
      body: const Center(child: Text("Welcome Care Receiver!")),
    );
  }
}