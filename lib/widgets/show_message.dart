import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:another_flushbar/flushbar.dart';

Future<void> showMessage(
    BuildContext context, {
      required String message,
      IconData? icon,
      Color? color,
      int duration = 2,
    }) async {
  await Flushbar(
    margin: const EdgeInsets.all(16),
    borderRadius: BorderRadius.circular(16),
    flushbarPosition: FlushbarPosition.TOP,
    backgroundColor: (color ?? Colors.black).withOpacity(0.3), // translucent
    boxShadows: [
      BoxShadow(
        color: Colors.black26,
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ],
    messageText: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // glass blur effect
        child: Row(
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    duration: Duration(seconds: duration),
    animationDuration: const Duration(milliseconds: 400),
  ).show(context);
}
