// lib/services/exact_alarm_prime.dart
import 'dart:io';
import 'package:flutter/services.dart';

class ExactAlarmPrime {
  static const _ch = MethodChannel('medicare/alarmclock');

  /// Primes the OS with one AlarmClock alarm so Samsung shows your app under
  /// Settings → Apps → Special access → Alarms & reminders.
  static Future<void> primeOnce({int minutesAhead = 2}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('primeAlarmClock', {'minutes': minutesAhead});
    } catch (_) {
      // best-effort only
    }
  }
}
