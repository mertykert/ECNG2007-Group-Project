// ============================================================================
// lib/services/med_reminder_scheduler.dart
// ============================================================================
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:hive/hive.dart';
import 'notification_service.dart';

class MedReminderScheduler {
  static final _db = FirebaseFirestore.instance;

  // ---------- Helpers ----------
  static TimeOfDay? _parseUiTimeLoose(String raw) {
    final s = raw.replaceAll('\u202F', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return null;
    try {
      final dt = DateFormat.jm().parseStrict(s); // "5:00 PM"
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {
      try {
        final p = s.split(':'); // "17:05"
        final h = int.parse(p[0]);
        final m = p.length > 1 ? int.parse(p[1]) : 0;
        if (h >= 0 && h < 24 && m >= 0 && m < 60) return TimeOfDay(hour: h, minute: m);
      } catch (_) {}
    }
    return null;
  }

  static DateTime? _parseYmd(String s) {
    if (s.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(s);
    } catch (_) {
      return null;
    }
  }

  static DateTime _todayAt(TimeOfDay t) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, t.hour, t.minute);
  }

  static DateTime _buildAt(DateTime day, TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  // ---------- Public API ----------
  static Future<void> scheduleForMed({
    required String uid,
    required String medId,
    required Map<String, dynamic> medData,
    bool fromRestore = false,
  }) async {
    try {
      final name    = (medData['name'] ?? '').toString().trim();
      final timeStr = (medData['time'] ?? '').toString().trim();
      final time24  = (medData['time24'] ?? '').toString().trim();
      final repeat  = (medData['repeat'] ?? 'Once').toString().trim(); // "Once" | "Daily" | "Weekly"
      final dateStr = (medData['date'] ?? '').toString().trim();
      final expiry  = (medData['expiryDate'] ?? '').toString().trim();

      if (name.isEmpty) return;
      final rawTime = time24.isNotEmpty ? time24 : timeStr;
      if (rawTime.isEmpty) return;

      // Prefer canonical 24h; fallback to UI time
      final tod = (time24.isNotEmpty) ? _parseUiTimeLoose(time24) : _parseUiTimeLoose(timeStr);
      if (tod == null) return;

      // ===== compute next fire time =====
      final now = DateTime.now();
      final userDate = _parseYmd(dateStr);
      DateTime when;
      DateTimeComponents? match;

      if (repeat == 'Daily') {
        var next = _todayAt(tod);
        if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
        when = next;
        match = DateTimeComponents.time; // Android exact daily at time
      } else if (repeat == 'Weekly') {
        // Anchor weekday from provided date if present; else use today's weekday
        final anchor = userDate ?? now;
        final want = anchor.weekday;
        var base = _todayAt(tod);
        final diff = (want - base.weekday) % 7;
        var next = base.add(Duration(days: diff));
        if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
        when = next;
        match = DateTimeComponents.dayOfWeekAndTime;
      } else {
        // Once
        if (userDate == null) {
          // If user forgot date for a one-shot, schedule today/tomorrow at time
          var next = _todayAt(tod);
          if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
          when = next;
          match = null;
        } else {
          final first = _buildAt(userDate, tod);
          if (!first.isAfter(now)) {
            if (kDebugMode) print("⏭️ skip past one-shot $medId ($first)");
            when = first; // not scheduled
            match = null;
          } else {
            when = first;
            match = null;
          }
        }
      }

      // ===== schedule =====
      await NotificationService.scrubByMed(uid, medId); // clear any old IDs/payloads

      int? reminderId;
      final doScheduleOnce = (repeat == 'Once' && userDate != null && _buildAt(userDate, tod).isAfter(now));
      if (repeat == 'Daily' || repeat == 'Weekly' || doScheduleOnce) {
        if (repeat == 'Daily') {
          reminderId = await NotificationService.scheduleDaily(
            when,
            'Time to take $name',
            'Please take your medication.',
            id: NotificationService.stableIdFor(uid, medId, kind: 'reminder'),
            payload: 'med:$uid:$medId:reminder',
          );
        } else if (repeat == 'Weekly') {
          reminderId = await NotificationService.scheduleWeekly(
            when,
            'Time to take $name',
            'Please take your medication.',
            id: NotificationService.stableIdFor(uid, medId, kind: 'reminder'),
            payload: 'med:$uid:$medId:reminder',
          );
        } else {
          reminderId = await NotificationService.scheduleAt(
            when,
            'Time to take $name',
            'Please take your medication.',
            id: NotificationService.stableIdFor(uid, medId, kind: 'reminder'),
            payload: 'med:$uid:$medId:reminder',
            repeat: match, // null for once
          );
        }
      }

      // ===== expiry warning =====
      if (expiry.isNotEmpty) {
        final exp = _parseYmd(expiry) ?? DateTime.tryParse(expiry);
        if (exp != null) {
          DateTime warn;
          final todayOnly = DateTime.now();
          final expOnly = DateTime(exp.year, exp.month, exp.day);
          final nowOnly = DateTime(todayOnly.year, todayOnly.month, todayOnly.day);
          if (!expOnly.isAfter(nowOnly)) {
            warn = DateTime.now().add(const Duration(seconds: 60));
          } else {
            warn = expOnly.subtract(const Duration(days: 7));
            if (!warn.isAfter(DateTime.now())) warn = DateTime.now().add(const Duration(seconds: 60));
          }
          await NotificationService.scheduleOnce(
            warn,
            'Medication Expiry Warning',
            '$name will expire soon. Please replace it.',
            id: NotificationService.stableIdFor(uid, medId, kind: 'expiry'),
            payload: 'med:$uid:$medId:expiry',
          );
        }
      }

      // ===== refill co-schedule (daily at med time when low) =====
      try {
        final doc = await _db.collection('users').doc(uid).collection('medications').doc(medId).get();
        if (doc.exists) {
          final d = doc.data()!;
          final medName = (d['name'] ?? name).toString();
          final total     = ((d['totalPills'] ?? 0) as num).toInt();
          final remaining = ((d['remainingPills'] ?? total) as num).toInt();
          int threshold   = ((d['refillThreshold'] ?? 0) as num).toInt();
          if (threshold <= 0) threshold = total > 0 ? (total * 0.20).round().clamp(1, total) : 1;
          final needsRefill = total > 0 && remaining <= threshold;

          final fid = NotificationService.stableIdFor(uid, medId, kind: 'refill');
          await NotificationService.cancel(fid);
          if (needsRefill) {
            var firstAt = _todayAt(tod);
            if (!firstAt.isAfter(now)) firstAt = firstAt.add(const Duration(days: 1));
            await NotificationService.scheduleDaily(
              firstAt,
              "Refill Reminder",
              "$medName is running low — please refill.",
              id: fid,
              payload: 'med:$uid:$medId:refill',
            );
          }
        }
      } catch (e) {
        if (kDebugMode) print("⚠️ refill co-schedule failed: $e");
      }

      // Cache
      await Hive.box('scheduled_reminders').put(medId, {
        'uid': uid,
        'name': name,
        'time': timeStr,
        'time24': time24,
        'repeat': repeat,
        'date': dateStr,
        'expiryDate': expiry,
      });

      if (kDebugMode) {
        print("✅ scheduled $medId ($repeat) "
            "${reminderId != null ? '→ id=$reminderId' : '(skipped past once)'}");
      }
    } catch (e, st) {
      print('⚠️ MedReminderScheduler.scheduleForMed error: $e\n$st');
    }
  }

  static Future<void> cancelTimersForMed(String uid, String medId) async {
    try {
      await NotificationService.scrubByMed(uid, medId);
      final docRef = _db.collection('users').doc(uid).collection('medications').doc(medId);
      if ((await docRef.get()).exists) {
        await docRef.update({'notificationIds': FieldValue.delete()});
      }
      await Hive.box('scheduled_reminders').delete(medId);
      if (kDebugMode) print("🛑 Canceled all notifications for $medId (silent)");
    } catch (e) {
      if (kDebugMode) print('⚠️ cancelTimersForMed error: $e');
    }
  }

  static Future<void> cancelForMed(String uid, String medId) async {
    try {
      final reminderId = NotificationService.stableIdFor(uid, medId, kind: 'reminder');
      final expiryId   = NotificationService.stableIdFor(uid, medId, kind: 'expiry');
      final refillId   = NotificationService.stableIdFor(uid, medId, kind: 'refill');
      await NotificationService.cancel(reminderId);
      await NotificationService.cancel(expiryId);
      await NotificationService.cancel(refillId);

      final doc = await _db.collection('users').doc(uid).collection('medications').doc(medId).get();
      if (doc.exists) {
        final data = doc.data()!;
        final ids = (data['notificationIds'] as Map?)?.cast<String, dynamic>();
        if (ids != null) {
          for (final e in ids.entries) {
            final v = e.value;
            if (v is int) await NotificationService.cancel(v);
            else if (v is num) await NotificationService.cancel(v.toInt());
          }
        }
        final rn = data['reminderNotificationId'];
        if (rn is int) await NotificationService.cancel(rn);
        else if (rn is num) await NotificationService.cancel(rn.toInt());
      }
      await Hive.box('scheduled_reminders').delete(medId);
      print('🗑️ Fully canceled all reminders and expiry warnings for med $medId');
    } catch (e) {
      print('⚠️ cancelForMed error: $e');
    }
  }
}