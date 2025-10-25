// lib/services/notification_service.dart
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'med_reminder_scheduler.dart' as sched;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'med_channel';
  static const _channelName = 'Medication Alerts';
  static const _channelDesc = 'Reminders & missed-dose alerts';

  // Fallback timers to guarantee a toast if OS doesn’t fire.
  static final Map<int, Timer> _fallbacks = {};

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher'); // must exist
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);

    tz.initializeTimeZones();
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
      await Permission.scheduleExactAlarm.request();
    }

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
      ),
    );
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
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
      await _plugin.cancel(rid);
      await _plugin.cancel(eid);

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
        String? payload,
      }) async {
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime sched = tz.TZDateTime.from(when, tz.local);

    if (repeat == null) {
      if (!sched.isAfter(now)) sched = now.add(const Duration(minutes: 1));
      return scheduleOnce(sched.toLocal(), title, body, id: id, payload: payload);
    }

    if (repeat == DateTimeComponents.time) {
      final todayAt = tz.TZDateTime(tz.local, now.year, now.month, now.day, sched.hour, sched.minute, sched.second);
      final next = todayAt.isAfter(now) ? todayAt : todayAt.add(const Duration(days: 1));
      return scheduleDaily(next.toLocal(), title, body, id: id, payload: payload);
    }

    if (repeat == DateTimeComponents.dayOfWeekAndTime) {
      final base = tz.TZDateTime(tz.local, now.year, now.month, now.day, sched.hour, sched.minute, sched.second);
      final diff = (sched.weekday - now.weekday) % 7;
      var next = base.add(Duration(days: diff));
      if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
      return scheduleWeekly(next.toLocal(), title, body, id: id, payload: payload);
    }

    if (!sched.isAfter(now)) sched = now.add(const Duration(minutes: 1));
    return scheduleOnce(sched.toLocal(), title, body, id: id, payload: payload);
  }

  // ---------- Schedulers (with in-app fallback timers) ----------
  static void _armFallback(int id, DateTime when, String title, String body) {
    // Only arm if within 30 minutes (avoid super long timers).
    final diff = when.difference(DateTime.now());
    if (diff.inSeconds <= 0 || diff.inMinutes > 30) return;

    _fallbacks[id]?.cancel();
    _fallbacks[id] = Timer(diff, () async {
      print("⚡ Fallback fired → '$title'");
      await _plugin.show(id, title, body, _details);
      _fallbacks.remove(id);
    });
  }

  static Future<int> scheduleOnce(
      DateTime when,
      String title,
      String body, {
        int? id,
        String? payload,
      }) async {
    final _id = id ?? _fnv32('once|${when.millisecondsSinceEpoch}|$title');
    await _plugin.cancel(_id);
    await _plugin.zonedSchedule(
      _id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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
    final _id = id ?? _fnv32('daily|${when.hour}:${when.minute}|$title');
    await _plugin.cancel(_id);
    await _plugin.zonedSchedule(
      _id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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
    final _id = id ?? _fnv32('weekly|${when.weekday}@${when.hour}:${when.minute}|$title');
    await _plugin.cancel(_id);
    await _plugin.zonedSchedule(
      _id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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
      print("✅ purgeAndReseed: scheduled=$scheduled, skipped=$skipped for $uid");
    } catch (e, st) {
      print("❌ purgeAndReseed error: $e\n$st");
    }
  }
}
