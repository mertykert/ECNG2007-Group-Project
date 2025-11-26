// lib/services/exact_alarm_prime.dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

class ExactAlarmPrime {
  static const String _kBootstrapDone = 'exact_alarm_bootstrap_done_v1';
  static bool _running = false;

  /// First-run only: open the Exact Alarms page once, then never again.
  /// No permission/state checks. No background polling.
  static Future<void> bootstrapOnce() async {
    if (!Platform.isAndroid || _running) return;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kBootstrapDone) == true) return;

      await prefs.setBool(_kBootstrapDone, true); // mark BEFORE opening

      // Short delay lets first frame render; helps avoid visible flash
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final pkg = (await PackageInfo.fromPlatform()).packageName;

      // Primary: per-app Exact Alarms page (must use data: 'package:<id>')
      try {
        await AndroidIntent(
          action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
          data: 'package:$pkg',
          flags: <int>[
            Flag.FLAG_ACTIVITY_NEW_TASK,
            Flag.FLAG_ACTIVITY_NO_ANIMATION,
          ],
        ).launch();
        return;
      } catch (_) {}

      // Fallback: OEM list (some devices)
      try {
        await AndroidIntent(
          action: 'android.settings.MANAGE_SCHEDULED_TASKS',
          flags: <int>[
            Flag.FLAG_ACTIVITY_NEW_TASK,
            Flag.FLAG_ACTIVITY_NO_ANIMATION,
          ],
        ).launch();
        return;
      } catch (_) {}

      // Last resort: app details
      await AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$pkg',
        flags: <int>[
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_NO_ANIMATION,
        ],
      ).launch();
    } finally {
      _running = false;
    }
  }

  /// QA-only: clear the one-shot flag to replay the flow (do not ship).
  static Future<void> _resetForQA() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBootstrapDone);
  }
}
