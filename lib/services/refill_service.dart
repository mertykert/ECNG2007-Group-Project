import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class RefillService {
  static final _db = FirebaseFirestore.instance;

  /// Compute threshold + needsRefill from the provided fields.
  /// - If `refillThreshold` is absent/<=0, use 20% of total (min 1 if total>0).
  /// - Clears `lowStockNotified` when no longer low.
  static Map<String, dynamic> computeRefillPatch(Map<String, dynamic> data) {
    final int total     = (data['totalPills']     ?? 0) as int;
    final int remaining = (data['remainingPills'] ?? 0) as int;

    int threshold = (data['refillThreshold'] ?? 0) as int;
    if (threshold <= 0) {
      threshold = total > 0 ? (total * 0.20).round().clamp(1, total) : 1;
    }

    final bool needsRefill = remaining <= threshold;

    return <String, dynamic>{
      'refillThreshold': threshold,
      'needsRefill': needsRefill,
      if (!needsRefill) 'lowStockNotified': false,
      'refillUpdatedAt': FieldValue.serverTimestamp(),
    };
  }

  ///  Checks *all* medications for this user — used by midnight background job
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
      print("⚠️ RefillService.checkAll failed: $e");
    }
  }

  ///  Check a single med — used by mark-as-taken flow
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

  ///  Called when a dose is marked “taken”
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


  ///  Core logic — decides if a notification or state change is needed
  static Future<void> _checkOne(String uid, String medId, Map<String, dynamic> data) async {
    try {
      final name     = (data['name'] ?? '').toString();
      final total    = (data['totalPills'] ?? 0) as int;
      final perDose  = (data['perDose'] ?? 1) as int;
      int remaining  = (data['remainingPills'] ?? 0) as int;

      if (name.isEmpty || total <= 0 || perDose <= 0) return;

      // Bootstrap remaining if missing
      if (remaining <= 0) {
        remaining = total;
        await _db.collection('users').doc(uid)
            .collection('medications').doc(medId)
            .set({'remainingPills': remaining}, SetOptions(merge: true));
      }

      // Recompute refill fields and persist
      final refillPatch = computeRefillPatch({
        'totalPills': total,
        'remainingPills': remaining,
        'refillThreshold': data['refillThreshold'],
      });
      await _db.collection('users').doc(uid)
          .collection('medications').doc(medId)
          .set(refillPatch, SetOptions(merge: true));

      final bool needsRefill     = (refillPatch['needsRefill'] as bool?) ?? false;
      final bool lowNotified     = (data['lowStockNotified'] == true);
      final int  threshold       = (refillPatch['refillThreshold'] as int?) ?? 5;

      // Notify exactly when crossing below/equal threshold AND not notified yet
      if (needsRefill && !lowNotified) {
        await NotificationService.showNow(
          "Refill Needed",
          "$name is running low — only $remaining pill(s) left.",
        );
        await _db.collection('users').doc(uid)
            .collection('medications').doc(medId)
            .set({'lowStockNotified': true}, SetOptions(merge: true));
      }

      // If user refilled above threshold, clear the notification latch (handled by computeRefillPatch too)
      if (!needsRefill && lowNotified) {
        await _db.collection('users').doc(uid)
            .collection('medications').doc(medId)
            .set({'lowStockNotified': false}, SetOptions(merge: true));
      }

      // Predict runout (unchanged logic; uses remaining/perDose)
      final repeat = (data['repeat'] ?? 'Once').toString();
      final dosesPerDay = repeat == 'Daily'
          ? 1.0
          : repeat == 'Weekly'
          ? (1.0 / 7.0)
          : 0.0;

      if (dosesPerDay > 0) {
        final dosesLeft = remaining / perDose;
        final daysLeft  = dosesLeft / dosesPerDay;
        final warnDate  = DateTime.now().add(Duration(days: daysLeft.ceil() - 3));

        if (warnDate.isAfter(DateTime.now())) {
          final last = (data['refillWarnScheduledAt'] as Timestamp?)?.toDate();
          final shouldSchedule = last == null || warnDate.difference(last).inDays.abs() >= 1;

          if (shouldSchedule) {
            await NotificationService.scrubByMed(uid, medId);
            await NotificationService.scheduleAt(
              warnDate,
              "Upcoming Refill Reminder",
              "$name may run out in about ${daysLeft.ceil()} days.",
            );
            await _db.collection('users').doc(uid)
                .collection('medications').doc(medId)
                .set({'refillWarnScheduledAt': Timestamp.fromDate(warnDate)}, SetOptions(merge: true));
          }
        }
      }
    } catch (e) {
      print("⚠️ _checkOne failed: $e");
    }
  }
}

