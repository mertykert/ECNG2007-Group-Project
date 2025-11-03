// lib/services/med_reminder_scheduler.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:hive/hive.dart';
import 'package:medi_care/services/refill_service.dart';
import 'notification_service.dart';



class MedReminderScheduler {
  static final _db = FirebaseFirestore.instance;

  // Only kept for API completeness; we no longer start local fallbacks.
  static final Map<String, Timer> _fallbackTimers = {};

  // ---------- Helpers ----------
  static TimeOfDay? _parseUiTimeLoose(String raw) {
    final s = raw.replaceAll('\u202F', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return null;
    // "5:00 PM"
    try {
      final dt = DateFormat.jm().parse(s);
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {
      // "17:05"
      try {
        final p = s.split(':');
        final h = int.parse(p[0]);
        final m = p.length > 1 ? int.parse(p[1]) : 0;
        if (h >= 0 && h < 24 && m >= 0 && m < 60) return TimeOfDay(hour: h, minute: m);
      } catch (_) {}
    }
    return null;
  }

  static Future<void> _updateNotifIdsIfDocExists(
      String uid,
      String medId,
      Map<String, dynamic> ids,
      ) async {
    final ref = _db.collection('users').doc(uid).collection('medications').doc(medId);
    final snap = await ref.get();
    if (!snap.exists) return;         // ← do NOT recreate deleted meds
    await ref.update({'notificationIds': ids});
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
    bool fromRestore = false, // pass true on boot restore
  }) async {
    try {
      final name    = (medData['name'] ?? '').toString().trim();
      final timeStr = (medData['time'] ?? '').toString().trim();
      final time24  = (medData['time24'] ?? '').toString().trim();
      final repeat  = (medData['repeat'] ?? 'Once').toString().trim();
      final dateStr = (medData['date'] ?? '').toString().trim();
      final expiry  = (medData['expiryDate'] ?? '').toString().trim();

      final rawTime = (time24.isNotEmpty ? time24 : timeStr);
      final hasName = name.isNotEmpty;
      final hasTime = rawTime.isNotEmpty;
      // For one-shot meds, require a date to avoid scheduling nonsense
      final hasValidDateForOnce = repeat != 'Once' || dateStr.isNotEmpty;

      if (!hasName || !hasTime || !hasValidDateForOnce) {
        if (kDebugMode) {
          print("⛔ scheduleForMed skip $medId "
              "name='$name' time='$rawTime' repeat='$repeat' date='$dateStr'");
        }
        return;
      }

      // Prefer canonical 24h time, fallback to UI time (handles U+202F)
      TimeOfDay? tod = time24.isNotEmpty ? _parseUiTimeLoose(time24) : _parseUiTimeLoose(timeStr);
      if (tod == null) {
        if (kDebugMode) {
          print("⛔ scheduleForMed skip $medId: cannot parse time '$timeStr' / '$time24'");
        }
        return;
      }

      // Anchor date (for Once/Weekly semantics)
      DateTime anchorDate = DateTime.now();
      if (dateStr.isNotEmpty) {
        anchorDate = DateTime.tryParse(dateStr) ?? anchorDate;
      }

      // Compute when + repeat component
      final now = DateTime.now();
      final firstAt = _buildAt(anchorDate, tod);
      DateTime when;
      DateTimeComponents? repeatComp;

      if (repeat == 'Daily') {
        var todayAt = _todayAt(tod);
        if (!todayAt.isAfter(now)) todayAt = todayAt.add(const Duration(days: 1));
        when = todayAt;
        repeatComp = DateTimeComponents.time;
      } else if (repeat == 'Weekly') {
        final weekdayWanted = anchorDate.weekday; // keep original weekday
        var base = _todayAt(tod);
        int diff = (weekdayWanted - base.weekday) % 7;
        var next = base.add(Duration(days: diff));
        if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
        when = next;
        repeatComp = DateTimeComponents.dayOfWeekAndTime;
      } else {
        // Once: do NOT fabricate "next minute" on restore; just skip past events
        if (!firstAt.isAfter(now)) {
          if (kDebugMode) print("⏭️ skip past one-shot $medId (${firstAt.toLocal()})");
          // We still may schedule expiry warning below even if one-shot reminder is skipped.
          when = firstAt; // unused, but set for clarity
          repeatComp = null;
        } else {
          when = firstAt;
          repeatComp = null;
        }
      }

      // Schedule reminder (only if we actually computed a future moment, or it’s daily/weekly)
      int? reminderId;
      if (repeat == 'Daily' || repeat == 'Weekly' || (repeat == 'Once' && firstAt.isAfter(now))) {
        await NotificationService.scrubByMed(uid, medId);
        reminderId = await NotificationService.scheduleAt(
          when,
          'Time to take $name',
          'Please take your medication.',
          repeat: repeatComp,
          id: NotificationService.stableIdFor(uid, medId, kind: 'reminder'),
          payload: 'med:$uid:$medId:reminder',
        );
      }

      // Schedule expiry warning:
      // - If expiry <= today → fire in +60s so user sees it (0d or past)
      // - Else → 7 days before expiry; if that’s also in the past, also +60s.
      int? expiryId;
      if (expiry.isNotEmpty) {
        DateTime? exp;
        exp = DateTime.tryParse(expiry) ??
            (() {
              try {
                return DateFormat('yyyy-MM-dd').parse(expiry);
              } catch (_) {
                return null;
              }
            })();

        if (exp != null) {
          DateTime warn;
          final today = DateTime.now();
          final expDateOnly = DateTime(exp.year, exp.month, exp.day);
          final todayDateOnly = DateTime(today.year, today.month, today.day);

          if (!expDateOnly.isAfter(todayDateOnly)) {
            warn = DateTime.now().add(const Duration(seconds: 60)); // 0d/past → show soon
          } else {
            warn = expDateOnly.subtract(const Duration(days: 7));
            if (!warn.isAfter(DateTime.now())) {
              warn = DateTime.now().add(const Duration(seconds: 60));
            }
          }

          expiryId = await NotificationService.scheduleOnce(
            warn,
            'Medication Expiry Warning',
            '$name will expire soon. Please replace it.',
            id: NotificationService.stableIdFor(uid, medId, kind: 'expiry'),
            payload: 'med:$uid:$medId:expiry',
          );
        }
      }

      // Persist ids (Firestore + Hive)
      await _updateNotifIdsIfDocExists(uid, medId, {
        if (reminderId != null) 'reminder': reminderId,
        if (expiryId != null) 'expiry':   expiryId,
      });

      // ===== Refill co-schedule (daily at med time while stock is low) =====
      try {
        // Load live stock from Firestore for this med
        final docSnap = await _db.collection('users').doc(uid)
            .collection('medications').doc(medId).get();
        if (docSnap.exists) {
          final d = docSnap.data()!;
          final String medName = (d['name'] ?? name).toString();

          // robust ints
          final int total     = ((d['totalPills'] ?? 0) as num).toInt();
          final int remaining = ((d['remainingPills'] ?? total) as num).toInt();
          int threshold       = ((d['refillThreshold'] ?? 0) as num).toInt();
          if (threshold <= 0) {
            threshold = total > 0 ? (total * 0.20).round().clamp(1, total) : 1;
          }
          final bool needsRefill = total > 0 && remaining <= threshold;

          // Always cancel existing refill alarm; re-add only if low
          final int fid = NotificationService.stableIdFor(uid, medId, kind: 'refill');
          await NotificationService.cancel(fid);

          if (kDebugMode) {
            print("🧮 refill: med=$medId needsRefill=$needsRefill total=$total remaining=$remaining thr=$threshold");
          }

          if (needsRefill) {
            // Use same time as the med reminder (time24); fallback to +60s
            DateTime firstAt;
            final String t24 = (time24).toString().trim();
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
              "$medName is running low — please refill.",
              id: fid,
              payload: 'med:$uid:$medId:refill',
              repeat: DateTimeComponents.time, // daily at med time
            );
          }
        }
      } catch (e) {
        if (kDebugMode) print("⚠️ Refill co-schedule failed for $medId: $e");
      }

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
        final whenTxt = (repeat == 'Once' && !firstAt.isAfter(now)) ? '(skipped past once)' : '$when';
        print(
            " scheduled $medId →${reminderId != null ? ' reminderId=$reminderId' : ''}"
                "${expiryId != null ? ' expiryId=$expiryId' : ''} at $whenTxt ($repeat)"
        );
      }
    } catch (e, st) {
      print('⚠️ MedReminderScheduler.scheduleForMed error: $e\n$st');
    }
  }

  /// Silent cancel for EDIT flow (no popup, no SnackBar).
  static Future<void> cancelTimersForMed(String uid, String medId) async {
    try {
      _fallbackTimers.remove(medId)?.cancel();

      // Cancel whatever is pending for this med (by stable IDs & payload)
      await NotificationService.scrubByMed(uid, medId);

      // Remove stored ids + local cache
      final docRef = _db.collection('users').doc(uid).collection('medications').doc(medId);
      final exists = (await docRef.get()).exists;
      if (exists) {
        await docRef.update({'notificationIds': FieldValue.delete()});
      }
      await Hive.box('scheduled_reminders').delete(medId);

      if (kDebugMode) print("🛑 Canceled all notifications for $medId (silent)");
    } catch (e) {
      if (kDebugMode) print('⚠️ cancelTimersForMed error: $e');
    }
  }

  /// Full cancel used on DELETE (shows a “deleted” banner).
  static Future<void> cancelForMed(String uid, String medId) async {
    try {
      // 1️⃣ Cancel both reminder + expiry notifications using stable IDs
      final reminderId = NotificationService.stableIdFor(uid, medId, kind: 'reminder');
      final expiryId   = NotificationService.stableIdFor(uid, medId, kind: 'expiry');
      await NotificationService.cancel(reminderId);
      await NotificationService.cancel(expiryId);
      final refillId   = NotificationService.stableIdFor(uid, medId, kind: 'refill');
      await NotificationService.cancel(refillId);

      // 2️⃣ Double-check for any older random IDs saved in Firestore
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications')
          .doc(medId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final ids = (data['notificationIds'] as Map?)?.cast<String, dynamic>();

        if (ids != null) {
          for (final entry in ids.entries) {
            final idVal = entry.value;
            if (idVal is int) {
              await NotificationService.cancel(idVal);
            } else if (idVal is num) {
              await NotificationService.cancel(idVal.toInt());
            }
          }
        }

        // Also cancel any single stored reminder id
        if (data['reminderNotificationId'] is int) {
          await NotificationService.cancel(data['reminderNotificationId'] as int);
        } else if (data['reminderNotificationId'] is num) {
          await NotificationService.cancel((data['reminderNotificationId'] as num).toInt());
        }
      }

      // 3️⃣ Remove from Hive cache too
      await Hive.box('scheduled_reminders').delete(medId);

      print('🗑️ Fully canceled all reminders and expiry warnings for med $medId');
    } catch (e) {
      print('⚠️ cancelForMed error: $e');
    }
  }
}
