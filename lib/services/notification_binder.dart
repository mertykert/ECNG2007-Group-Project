import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'notification_service.dart';

class NotificationBinder {
  /// Schedules reminder (Once/Daily/Weekly) and optional expiry-7d warning.
  /// Returns ids map: {'reminder': int, 'expiry': int?}
  static Future<Map<String, int>> scheduleForMed({
    required String name,
    required String dosage,
    required String repeat,        // 'Once' | 'Daily' | 'Weekly'
    required TimeOfDay timeOfDay,  // UI time
    required DateTime anchorDate,  // yyyy-MM-dd date anchor (start)
    String? expiryDateText,        // 'yyyy-MM-dd' or empty
  }) async {
    final ids = <String, int>{};

    final firstTrigger = DateTime(
      anchorDate.year, anchorDate.month, anchorDate.day,
      timeOfDay.hour, timeOfDay.minute,
    );

    final title = "Time to take $name";
    final body  = "Dosage: $dosage";

    if (repeat == 'Once') {
      final now = DateTime.now();
      final when = firstTrigger.isAfter(now) ? firstTrigger : firstTrigger.add(const Duration(days: 1));
      final id = await NotificationService.scheduleOnce(when, title, body);
      ids['reminder'] = id;
    } else if (repeat == 'Daily') {
      final id = await NotificationService.scheduleDaily(firstTrigger, title, body);
      ids['reminder'] = id;
    } else if (repeat == 'Weekly') {
      final id = await NotificationService.scheduleWeekly(firstTrigger, title, body);
      ids['reminder'] = id;
    }

    if ((expiryDateText ?? '').isNotEmpty) {
      final expiry = DateTime.tryParse(expiryDateText!);
      if (expiry != null) {
        final warnDate = expiry.subtract(const Duration(days: 7));
        if (warnDate.isAfter(DateTime.now())) {
          final id = await NotificationService.scheduleOnce(
            warnDate,
            "Medication Expiry Warning",
            "Your $name will expire soon.",
          );
          ids['expiry'] = id;
        }
      }
    }

    return ids;
  }

  /// Best-effort cancel of existing local notifications
  static Future<void> cancelForMed(Map<String, dynamic>? notificationIds) async {
    if (notificationIds == null) return;
    final reminder = notificationIds['reminder'];
    final expiry   = notificationIds['expiry'];
    if (reminder is int) await NotificationService.cancel(reminder);
    if (expiry is int)   await NotificationService.cancel(expiry);
  }
}