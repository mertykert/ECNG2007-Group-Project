import 'package:flutter/material.dart';

class BackButtonOverlay extends StatelessWidget {
  const BackButtonOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 25,
      left: 16,
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus(); // close keyboard if open
          Navigator.maybePop(context); // ✅ only pop within the current stack
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF2d59f0),
            size: 20,
          ),
        ),
      ),
    );
  }
}
