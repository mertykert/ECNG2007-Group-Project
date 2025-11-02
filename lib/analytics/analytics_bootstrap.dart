import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'analytics_service.dart';



class AnalyticsBootstrap {
  static bool _tzReady = false;
  static bool _auditSent = false;

  static Future<void> init() async {
    await _ensureTz();

    final tzName = _currentTzName();
    final tzOffset = _currentTzOffsetMinutes();
    final localeTag = _currentLocale();      // e.g., "en-TT"
    final platform = _platformString();
    final appCountry = _countryFromLocale(); // e.g., "TT"

    await AppAnalytics.setUserPropsFromEnv(
      tzName: tzName,
      tzOffsetMinutes: tzOffset,
      locale: localeTag,
      platform: platform,
      appCountry: appCountry,
    );

    if (kDebugMode) {
      unawaited(_sendOneTimeDiagnosticsEvent());
    }
  }

  static Future<void> _ensureTz() async {
    if (_tzReady) return;
    try { tzdata.initializeTimeZones(); } catch (_) {}
    try {
      final dynamic tzResult = await FlutterTimezone.getLocalTimezone();
      String currentZone;
      if (tzResult is String) {
        currentZone = tzResult;
      } else if (tzResult.toString().contains('(')) {
        final match = RegExp(r'\(([^,]+),').firstMatch(tzResult.toString());
        currentZone = match != null ? match.group(1)! : 'UTC';
      } else if (tzResult is Map && tzResult['name'] != null) {
        currentZone = tzResult['name'].toString();
      } else {
        currentZone = 'UTC';
      }
      final location = _safeGetLocation(currentZone) ?? tz.getLocation('UTC');
      tz.setLocalLocation(location);
      if (kDebugMode) {
        // ignore: avoid_print
        print('🌍 Timezone initialized: $currentZone');
      }
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    _tzReady = true;
  }

  static tz.Location? _safeGetLocation(String zone) {
    try { return tz.getLocation(zone); } catch (_) { return null; }
  }

  static String _currentTzName() {
    try {
      final loc = tz.local;
      return loc.name.isNotEmpty ? loc.name : 'UTC';
    } catch (_) {
      return 'UTC';
    }
  }

  static int _currentTzOffsetMinutes() {
    try { return tz.TZDateTime.now(tz.local).timeZoneOffset.inMinutes; } catch (_) { return 0; }
  }

  static String _currentLocale() {
    try { return ui.PlatformDispatcher.instance.locale.toLanguageTag(); }
    catch (_) { return Intl.getCurrentLocale(); }
  }

  static String? _countryFromLocale() {
    try {
      final c = ui.PlatformDispatcher.instance.locale.countryCode;
      return (c == null || c.isEmpty) ? null : c.toUpperCase();
    } catch (_) {
      return null;
    }
  }

  static String _platformString() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static Future<void> _sendOneTimeDiagnosticsEvent() async {
    if (_auditSent) return;
    _auditSent = true;

    final params = AppAnalytics.params({
      'tz': _currentTzName(),
      'tz_offset_minutes': _currentTzOffsetMinutes(),
      'locale': _currentLocale(),
      'platform': _platformString(),
      'debug_build': kDebugMode ? 1 : 0,
    });

    await FirebaseAnalytics.instance.logEvent(
      name: 'diagnostic_env',
      parameters: params,
    );
  }
}
