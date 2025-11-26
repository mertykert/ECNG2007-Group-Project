// lib/services/exact_alarm_prime.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ExactAlarmPrime {
  // Native bridge for AlarmClock priming
  static const MethodChannel _ch = MethodChannel('medicare/alarmclock');

  // One-time flags
  static const String _kPrimedAlarmClock  = 'primed_alarmclock_v1';
  static const String _kNudgedExactAlarms = 'nudged_exact_alarms_v3';

  /// Public entrypoint:
  /// 1) silently prime AlarmClock once so Samsung lists the app,
  /// 2) open the "Exact Alarms" page only if NOT allowed (once).
  /// Safe to call from main **or** NotificationService.init(); guards prevent repeats.
  static Future<void> ensureListedAndNudgeIfNeeded() async {
    if (!Platform.isAndroid) return;
    await _primeOnceSilently();                 // background, no UI
    await _openIfNotAllowedOnce();              // UI only if not allowed
  }

  /// Schedule one AlarmClock alarm a few minutes ahead to "prime" the OS.
  static Future<void> primeOnce({int minutesAhead = 2}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('primeAlarmClock', {'minutes': minutesAhead});
    } catch (_) {
      // best-effort only
    }
  }

  // --------- Internals ---------

  static Future<void> _primeOnceSilently() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrimedAlarmClock) == true) return;
    await primeOnce(minutesAhead: 2); // no UI
    await prefs.setBool(_kPrimedAlarmClock, true);
  }

  static Future<void> _openIfNotAllowedOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kNudgedExactAlarms) == true) return;

    final allowed = await Permission.scheduleExactAlarm.isGranted;
    if (allowed) {
      await prefs.setBool(_kNudgedExactAlarms, true); // ✅ do nothing; no popup
      return;
    }

    // Avoid OEM blocking during cold start
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final pkg = (await PackageInfo.fromPlatform()).packageName;
    // Primary: per-app exact alarms page (must use data: 'package:<id>')
    try {
      await AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        data: 'package:$pkg',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (_) {
      // Fallbacks (OEM dependent)
      try {
        await AndroidIntent(
          action: 'android.settings.MANAGE_SCHEDULED_TASKS',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
      } catch (_) {
        await AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:$pkg',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
      }
    }

    await prefs.setBool(_kNudgedExactAlarms, true);
  }

  /// QA helper to re-run both flows (clears flags). Do not ship enabled.
  static Future<void> resetFlagsForQA() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrimedAlarmClock);
    await prefs.remove(_kNudgedExactAlarms);
  }
}
