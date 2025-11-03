// lib/services/refill_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';

class RefillService {
  static final _db = FirebaseFirestore.instance;

  /// Computes threshold/needsRefill. Clears low flag when stock recovers.
  static Map<String, dynamic> computeRefillPatch(Map<String, dynamic> data) {
    final int total     = ((data['totalPills']     ?? 0) as num).toInt();
    final int remaining = ((data['remainingPills'] ?? 0) as num).toInt();
    final int inThresh  = ((data['refillThreshold'] ?? 0) as num).toInt();

    int? outThreshold;
    if (inThresh > 0) {
      // Respect explicit threshold from caller/doc
      outThreshold = inThresh;
    } else if (total > 0) {
      // Only auto-derive when total is known and > 0
      outThreshold = (total * 0.20).round().clamp(1, total);
    } else {
      // Total unknown → do NOT write threshold (prevents forcing 1)
      outThreshold = null;
    }

    bool? needsRefill;
    if (total > 0 && outThreshold != null) {
      needsRefill = remaining <= outThreshold;
    } else {
      // Unknown total → do not evaluate/overwrite needsRefill
      needsRefill = null;
    }

    return <String, dynamic>{
      if (outThreshold != null) 'refillThreshold': outThreshold,
      if (needsRefill != null) 'needsRefill': needsRefill,
      if (needsRefill == false) 'lowStockNotified': false, // clear latch only when known not-low
    };
  }


  /// Checks all meds (midnight/background).
  static Future<void> checkAll(String uid) async {
    try {
      final meds = await _db
          .collection('users')
          .doc(uid)
          .collection('medications')
          .get();

      for (final doc in meds.docs) {
        await _checkOne(uid, doc.id, doc.data());
      }
    } catch (e) {
      // WHY: keep background resilient
      // ignore: avoid_print
      print("⚠️ RefillService.checkAll failed: $e");
    }
  }

  /// Check a single med by id.
  static Future<void> checkOne(String uid, String medId) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('medications')
        .doc(medId)
        .get();
    if (!snap.exists) return;
    await _checkOne(uid, medId, snap.data()!);
  }

  /// Called when a dose is marked taken (keeps math symmetric with undo).
  static Future<void> onDoseTaken(String uid, String medId, {int? perDose}) async {
    final ref = _db.collection('users').doc(uid).collection('medications').doc(medId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final dose = perDose ?? (data['perDose'] ?? 1) as int;
    final currentRemaining = (data['remainingPills'] ?? data['totalPills'] ?? 0) as int;
    final newRemaining = (currentRemaining - dose).clamp(0, 100000);

    final patch = computeRefillPatch({
      'totalPills': (data['totalPills'] ?? 0) as int,
      'remainingPills': newRemaining,
      'refillThreshold': data['refillThreshold'],
    });

    await ref.set({
      'remainingPills': newRemaining,
      ...patch,
    }, SetOptions(merge: true));

    await _checkOne(uid, medId, {...data, 'remainingPills': newRemaining, ...patch});
  }

  /// Core logic — decides notifications & schedules.
  static Future<void> _checkOne(String uid, String medId, Map<String, dynamic> data) async {
    try {
      final name     = (data['name'] ?? '').toString();
      final total    = (data['totalPills'] ?? 0) as int;
      final perDose  = (data['perDose'] ?? 1) as int;
      int   remaining= (data['remainingPills'] ?? 0) as int;
      if (name.isEmpty || perDose <= 0) return;

      // Bootstrap remaining if missing.
      if (remaining <= 0) {
        remaining = total;
        await _db.collection('users').doc(uid)
            .collection('medications').doc(medId)
            .set({'remainingPills': remaining}, SetOptions(merge: true));
      }

      // Recompute/persist refill fields (threshold + needsRefill).
      final refillPatch = computeRefillPatch({
        'totalPills': total,
        'remainingPills': remaining,
        'refillThreshold': data['refillThreshold'],
      });
      await _db.collection('users').doc(uid)
          .collection('medications').doc(medId)
          .set(refillPatch, SetOptions(merge: true));

      final bool needsRefill = (refillPatch['needsRefill'] as bool?) ?? false;
      final bool lowNotified = (data['lowStockNotified'] == true);

      // One-shot banner exactly on threshold crossing.
      if (needsRefill && !lowNotified) {
        await NotificationService.showNow(
          "Refill Needed",
          "$name is running low — only $remaining pill(s) left.",
        );
        await _db.collection('users').doc(uid)
            .collection('medications').doc(medId)
            .set({'lowStockNotified': true}, SetOptions(merge: true));
      }

      // === Daily-when-low core ===
      final int fid = NotificationService.stableIdFor(uid, medId, kind: 'refill');

      // If no longer low: clear latch (if set) and cancel daily refill alarm.
      if (!needsRefill) {
        if (lowNotified) {
          await _db.collection('users').doc(uid)
              .collection('medications').doc(medId)
              .set({'lowStockNotified': false}, SetOptions(merge: true));
        }
        await NotificationService.cancel(fid);
        return; // nothing more to schedule
      }

      // Still low: schedule a DAILY reminder at the med's time.
      final String t24 = (data['time24'] ?? '').toString().trim();
      DateTime firstAt;
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t24)) {
        final parts = t24.split(':');
        final now = DateTime.now();
        final hh = int.tryParse(parts[0]) ?? now.hour;
        final mm = int.tryParse(parts[1]) ?? now.minute;
        firstAt = DateTime(now.year, now.month, now.day, hh, mm);
        if (!firstAt.isAfter(now)) firstAt = firstAt.add(const Duration(days: 1));
      } else {
        // WHY: ensure a valid anchor even if time24 missing
        firstAt = DateTime.now().add(const Duration(seconds: 60));
      }

      await NotificationService.cancel(fid); // replace any prior refill schedule
      await NotificationService.scheduleAt(
        firstAt,
        "Refill Reminder",
        "$name is running low — please refill.",
        id: fid,
        payload: 'med:$uid:$medId:refill',
        repeat: DateTimeComponents.time, // daily at medication time
      );

      await _db.collection('users').doc(uid)
          .collection('medications').doc(medId)
          .set({'refillWarnScheduledAt': Timestamp.fromDate(firstAt)}, SetOptions(merge: true));

    } catch (e) {
      // keep background resilient
      // ignore: avoid_print
      print("⚠️ _checkOne failed: $e");
    }
  }
}
