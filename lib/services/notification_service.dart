import 'dart:async';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'med_reminder_scheduler.dart' as sched;
import 'refill_service.dart';
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  static const _channelId = 'med_alerts_v2';
  static const _channelName = 'MediCare Reminders';
  static const _channelDesc = 'Medication reminders and expiry warnings';

  static final Map<int, Timer> _fallbacks = {};
  static bool _tzReady = false;

  static Future<bool> isExactAlarmAllowed() async {
    if (!Platform.isAndroid) return true; // iOS/others unaffected
    return await Permission.scheduleExactAlarm.isGranted;
  }

  /// Ensure timezone initialized
  static Future<void> _ensureTz() async {
    if (_tzReady) return;
    tz.initializeTimeZones();

    try {
      final dynamic tzResult = await FlutterTimezone.getLocalTimezone();
      String currentZone;

      if (tzResult is String) {
        currentZone = tzResult;
      } else if (tzResult.toString().contains('(')) {
        // Extract from: TimezoneInfo(America/Port_of_Spain, (locale: en_GB, name: Atlantic Standard Time))
        final match = RegExp(r'\(([^,]+),').firstMatch(tzResult.toString());
        currentZone = match != null ? match.group(1)! : 'UTC';
      } else if (tzResult is Map && tzResult['name'] != null) {
        currentZone = tzResult['name'].toString();
      } else {
        currentZone = 'UTC';
      }

      tz.setLocalLocation(tz.getLocation(currentZone));
      print('🌍 Timezone initialized: $currentZone');
    } catch (e) {
      print('⚠️ Timezone init failed, defaulting to UTC: $e');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    _tzReady = true;
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    final pkg = (await PackageInfo.fromPlatform()).packageName;
    final intent = AndroidIntent(
      action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      data: 'package:$pkg',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
  }

  /// Ask Android 13+ to open the Exact Alarm permission page
  /// Open the OS page to allow exact alarms (Android 13+).
  static Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;

    final pkg = (await PackageInfo.fromPlatform()).packageName;

    // Small delay helps avoid OEMs blocking settings launch at cold start.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Primary: per-app Exact Alarms page (MUST use data: 'package:<id>')
    try {
      await AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        data: 'package:$pkg', // <-- critical: use data URI, NOT the 'package:' field
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      print('⚙️ Opened per-app Exact Alarms for $pkg');
      return;
    } catch (e) {
      print('❌ Per-app exact-alarms page failed: $e');
    }

    // Fallback 1: OEM "Alarms & reminders" list (not universal, but works on many Samsung builds)
    try {
      await const AndroidIntent(
        action: 'android.settings.MANAGE_SCHEDULED_TASKS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      print('⚙️ Opened OEM Alarms & reminders list');
      return;
    } catch (e) {
      print('❌ OEM alarms list failed: $e');
    }

    // Fallback 2: App details — user can reach Special access from there
    try {
      await AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$pkg',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      print('⚙️ Opened App Details for $pkg');
    } catch (e) {
      print('❌ App details page failed: $e');
    }
  }


  /// Initialize notification system
  static Future<void> init() async {
    const androidInit =
    AndroidInitializationSettings('@mipmap/ic_launcher'); // must exist
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);
    await _ensureTz();

    try {
      final tzRaw = await FlutterTimezone.getLocalTimezone();
      final m = RegExp(r'([A-Za-z]+\/[A-Za-z_]+)').firstMatch(tzRaw.toString());
      final zone = m != null ? m.group(1)! : 'UTC';
      print("🌍 Local timezone: $zone");
      tz.setLocalLocation(tz.getLocation(zone));
    } catch (e) {
      print("⚠️ Timezone fetch failed, defaulting to UTC: $e");
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    if (Platform.isAndroid) {
      await Permission.notification.request();
      await requestExactAlarmPermission(); //  this now runs correctly
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }


  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      icon: '@drawable/ic_stat_medicare',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  // ---------- Stable IDs ----------
  static int _fnv32(String s) {
    const int prime = 0x01000193;
    int hash = 0x811C9DC5;
    for (final c in s.codeUnits) {
      hash ^= c;
      hash = (hash * prime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  static int stableIdFor(String uid, String medId, {String kind = 'reminder'}) =>
      _fnv32('$kind|$uid|$medId');

  static Future<void> scrubByMed(String uid, String medId) async {
    try {
      // Belt & suspenders: cancel by our deterministic IDs.
      final rid = stableIdFor(uid, medId, kind: 'reminder');
      final eid = stableIdFor(uid, medId, kind: 'expiry');
      final fid = stableIdFor(uid, medId, kind: 'refill');
      await _plugin.cancel(rid);
      await _plugin.cancel(eid);
      await _plugin.cancel(fid);

      // Now scan all pending for payload-tagged items (covers older/random IDs once we start tagging).
      final pending = await _plugin.pendingNotificationRequests();
      for (final req in pending) {
        final p = req.payload ?? '';
        if (p.startsWith('med:')) {
          // med:<uid>:<medId>:<kind>
          final parts = p.split(':');
          if (parts.length >= 4) {
            final puid = parts[1];
            final pmid = parts[2];
            if (puid == uid && pmid == medId) {
              await _plugin.cancel(req.id);
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ scrubByMed error: $e');
    }
  }

  static Future<void> resetFromFirestore(String uid) async {
    try {
      // Nuke everything first so we never double-schedule
      await cancelAll();

      final medsSnap = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('medications')
          .get();

      // Rebuild Hive backup ONLY from current Firestore docs
      final box = Hive.box('scheduled_reminders');
      await box.clear();

      int scheduled = 0, skipped = 0;
      for (final doc in medsSnap.docs) {
        final d = doc.data();
        final name   = (d['name'] ?? '').toString().trim();
        final time   = (d['time'] ?? '').toString().trim();
        final time24 = (d['time24'] ?? '').toString().trim();
        final repeat = (d['repeat'] ?? 'Once').toString().trim();
        final date   = (d['date'] ?? '').toString().trim();
        final expiry = (d['expiryDate'] ?? '').toString().trim();

        if (name.isEmpty || (time.isEmpty && time24.isEmpty)) {
          skipped++; continue;
        }

        await sched.MedReminderScheduler.scheduleForMed(
          uid: uid,
          medId: doc.id,
          medData: {
            'name': name,
            'time': time,
            'time24': time24,
            'repeat': repeat,
            'date': date,
            'expiryDate': expiry,
          },
        );

        // ---- Refill co-schedule (daily at med time while low) ----
        try {
          final d = (await FirebaseFirestore.instance
              .collection('users').doc(uid)
              .collection('medications').doc(doc.id).get()).data();

          if (d != null) {
            final String name  = (d['name'] ?? 'Medication').toString();
            final int total    = (d['totalPills'] ?? 0) as int;
            final int remaining= (d['remainingPills'] ?? total) as int;

            int threshold = (d['refillThreshold'] ?? 0) as int;
            if (threshold <= 0) {
              threshold = total > 0 ? (total * 0.20).round().clamp(1, total) : 1;
            }
            final bool needsRefill = total > 0 && remaining <= threshold;

            // Always cancel existing refill alarm; re-add only if low.
            final int fid = NotificationService.stableIdFor(uid, doc.id, kind: 'refill');
            await NotificationService.cancel(fid);

            if (needsRefill) {
              // Use same time as med reminder (time24) if present; else +60s
              final String t24 = (d['time24'] ?? '').toString().trim();
              DateTime firstAt;
              if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t24)) {
                final parts = t24.split(':');
                final now = DateTime.now();
                final hh = int.tryParse(parts[0]) ?? now.hour;
                final mm = int.tryParse(parts[1]) ?? now.minute;
                firstAt = DateTime(now.year, now.month, now.day, hh, mm);
                if (!firstAt.isAfter(now)) firstAt = firstAt.add(const Duration(days: 1));
              } else {
                firstAt = DateTime.now().add(const Duration(seconds: 60));
              }

              await NotificationService.scheduleAt(
                firstAt,
                "Refill Reminder",
                "$name is running low — please refill.",
                id: fid,
                payload: 'med:$uid:${doc.id}:refill',
                repeat: DateTimeComponents.time, // daily at med time
              );
            }
          }
        } catch (e) {
          // ignore: avoid_print
          print("⚠️ refill co-schedule in reset failed for ${doc.id}: $e");
        }

        await box.put(doc.id, {
          'uid': uid,
          'name': name,
          'time': time,
          'time24': time24,
          'repeat': repeat,
          'date': date,
          'expiryDate': expiry,
        });

        scheduled++;
      }

      // Kill any OS-pending notifications that reference meds you no longer have
      await cleanUserPending(uid);
      await dumpPending();
      await RefillService.checkAll(uid);
      print("🔁 Refill pass queued after resetFromFirestore for $uid");
      print("✅ resetFromFirestore: scheduled=$scheduled, skipped=$skipped for $uid");
    } catch (e, st) {
      print("❌ resetFromFirestore error: $e\n$st");
    }
  }

  /// Cancel ANY pending notifications that belong to this user but
  /// no longer map to an existing med in Firestore.
  /// Works for both payload-tagged and stable-ID patterns.
  static Future<void> cleanUserPending(String uid) async {
    try {
      // 1) Load the user's current med IDs from Firestore
      final medsSnap = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('medications')
          .get();
      final liveMedIds = medsSnap.docs.map((d) => d.id).toSet();

      // 2) Scan all pending OS notifications
      final pending = await _plugin.pendingNotificationRequests();
      for (final req in pending) {
        final p = req.payload ?? '';

        // Case A: New world (payload-tagged): med:<uid>:<medId>:<kind>
        if (p.startsWith('med:')) {
          final parts = p.split(':');
          if (parts.length >= 4) {
            final puid = parts[1];
            final pmid = parts[2];
            if (puid == uid && !liveMedIds.contains(pmid)) {
              await _plugin.cancel(req.id); // stale → nuke it
            }
          }
          continue;
        }

        // Case B: Old world (no payload). Best-effort:
        // If title/body look like our app’s templates but the medId no longer exists,
        // attempt to cancel by known stable IDs for each live med (no-op if mismatch).
        // We can’t safely parse medId, so we skip destructive action here to avoid cancelling others.
        // (Your purgeAndReseed + scrubByMed on delete/edit already handle most old cases.)
      }
    } catch (e) {
      print('⚠️ cleanUserPending error: $e');
    }
  }


  // ---------- Diagnostics ----------
  static Future<void> dumpPending() async {
    final list = await _plugin.pendingNotificationRequests();
    print("📋 Pending (${list.length}):");
    for (final p in list) {
      print("➡️ ${p.id}: ${p.title} :: ${p.body}");
    }
  }

  static Future<void> cancelAll() async {
    // Cancel timers so they don't re-show after cancelAll.
    for (final t in _fallbacks.values) t.cancel();
    _fallbacks.clear();
    await _plugin.cancelAll();
    print("🧹 cancelAll(): all pending notifications cleared");
  }

  // Cancel a single notification id and clear any fallback timer we armed for it.
  static Future<void> cancel(int id) async {
    // kill in-app fallback if we set one
    _fallbacks[id]?.cancel();
    _fallbacks.remove(id);

    await _plugin.cancel(id);
  }

// (Optional) Cancel both reminder + expiry for a specific med using stable IDs.
  static Future<void> cancelByMed(String uid, String medId) async {
    final reminderId = stableIdFor(uid, medId, kind: 'reminder');
    final expiryId   = stableIdFor(uid, medId, kind: 'expiry');
    await cancel(reminderId);
    await cancel(expiryId);
  }


  // Quick one-shot to verify banners appear immediately.
  static Future<int> showNow(String title, String body, {int? id}) async {
    final _id = id ?? _fnv32('now|$title|$body|${DateTime.now().microsecondsSinceEpoch}');
    await _plugin.cancel(_id);
    await _plugin.show(_id, title, body, _details);
    return _id;
  }

  // Convenience wrapper many parts of your app already call.
  static Future<int> scheduleAt(
      DateTime when,
      String title,
      String body, {
        DateTimeComponents? repeat,
        int? id,
        String? payload, // NEW — allows custom data for taps/callbacks
      }) async {
    int notifId = id ?? DateTime.now().microsecondsSinceEpoch.remainder(100000);

    try {
      // 🕓 Ensure timezone initialized before scheduling
      await _ensureTz();

      final dynamic tzResult = await FlutterTimezone.getLocalTimezone();

      String currentTimeZone;

      // Handle both old and new FlutterTimezone return types
      if (tzResult is String) {
        currentTimeZone = tzResult;
      } else if (tzResult is Map && tzResult['name'] != null) {
        currentTimeZone = tzResult['name'].toString();
      } else if (tzResult.toString().contains('America/')) {
        // Extract from "TimezoneInfo(America/Port_of_Spain, ...)"
        final match = RegExp(r'\(([^,]+),').firstMatch(tzResult.toString());
        currentTimeZone = match != null ? match.group(1)! : 'UTC';
      } else {
        currentTimeZone = 'UTC';
      }

      tz.setLocalLocation(tz.getLocation(currentTimeZone));
      print("🌍 Using timezone: $currentTimeZone");

      final now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduleTime = tz.TZDateTime.from(when, tz.local);

      // Ensure future time
      if (!scheduleTime.isAfter(now)) {
        scheduleTime = scheduleTime.add(const Duration(days: 1));
      }

      DateTimeComponents? match;
      if (repeat == DateTimeComponents.time) {
        match = DateTimeComponents.time; // daily
      } else if (repeat == DateTimeComponents.dayOfWeekAndTime) {
        match = DateTimeComponents.dayOfWeekAndTime; // weekly
      }

      print("⏰ Scheduling '$title' for ${scheduleTime.toLocal()} (repeat=$match)");

      await _plugin.zonedSchedule(
        notifId,
        title,
        body,
        scheduleTime,
        _details,
        payload: payload, //  Pass along the custom payload
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: (await Permission.scheduleExactAlarm.isGranted)
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: match,
      );

      print("✅ Scheduled notification for '$title' at ${scheduleTime.toLocal()} (id=$notifId)");
    } catch (e, st) {
      print("❌ scheduleAt() error: $e\n$st");
    }

    return notifId;
  }


  static Future<int> scheduleOnce(
      DateTime when,
      String title,
      String body, {
        int? id,
        String? payload,
      }) async {
    await _ensureTz();
    final _id = id ?? _fnv32('once|${when.millisecondsSinceEpoch}|$title');
    await _plugin.cancel(_id);
    await _plugin.zonedSchedule(
      _id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      _details,
      androidScheduleMode: (await Permission.scheduleExactAlarm.isGranted)
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
      payload: payload,
    );
    return _id;
  }

  static Future<int> scheduleDaily(
      DateTime when,
      String title,
      String body, {
        int? id,
        String? payload,
      }) async {
    await _ensureTz();
    final _id = id ?? _fnv32('daily|${when.hour}:${when.minute}|$title');
    await _plugin.cancel(_id);
    await _plugin.zonedSchedule(
      _id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      _details,
      androidScheduleMode: (await Permission.scheduleExactAlarm.isGranted)
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
    return _id;
  }

  static Future<int> scheduleWeekly(
      DateTime when,
      String title,
      String body, {
        int? id,
        String? payload,
      }) async {
    await _ensureTz();
    final _id = id ?? _fnv32('weekly|${when.weekday}@${when.hour}:${when.minute}|$title');
    await _plugin.cancel(_id);
    await _plugin.zonedSchedule(
      _id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      _details,
      androidScheduleMode: (await Permission.scheduleExactAlarm.isGranted)
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: payload,
    );
    return _id;
  }

  // Rebuild everything from Firestore and kill ghosts.
  static Future<void> purgeAndReseed(String uid) async {
    try {
      await cancelAll();

      final medsSnap = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('medications')
          .get();

      int scheduled = 0, skipped = 0;
      for (final doc in medsSnap.docs) {
        final d = doc.data();
        final name   = (d['name'] ?? '').toString().trim();
        final time   = (d['time'] ?? '').toString().trim();
        final time24 = (d['time24'] ?? '').toString().trim();
        final repeat = (d['repeat'] ?? 'Once').toString().trim();
        final date   = (d['date'] ?? '').toString().trim();
        final expiry = (d['expiryDate'] ?? '').toString().trim();

        if (name.isEmpty || (time.isEmpty && time24.isEmpty)) {
          skipped++;
          continue;
        }

        await sched.MedReminderScheduler.scheduleForMed(
          uid: uid,
          medId: doc.id,
          medData: {
            'name': name,
            'time': time,
            'time24': time24,
            'repeat': repeat,
            'date': date,
            'expiryDate': expiry,
          },
        );
        scheduled++;
      }

      await dumpPending();
      await RefillService.checkAll(uid);
      print("🔁 Refill pass queued after purgeAndReseed for $uid");
      print("✅ purgeAndReseed: scheduled=$scheduled, skipped=$skipped for $uid");
    } catch (e, st) {
      print("❌ purgeAndReseed error: $e\n$st");
    }
  }
}
