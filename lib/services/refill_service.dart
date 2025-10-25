import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class RefillService {
  static final _db = FirebaseFirestore.instance;

  /// 🔹 Checks *all* medications for this user — used by midnight background job
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

  /// 🔹 Check a single med — used by mark-as-taken flow
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

  /// 🔹 Called when a dose is marked “taken”
  static Future<void> onDoseTaken(String uid, String medId,
      {int? perDose}) async {
    final ref =
    _db.collection('users').doc(uid).collection('medications').doc(medId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final dose = perDose ?? (data['perDose'] ?? 1) as int;
    final currentRemaining =
    (data['remainingPills'] ?? data['totalPills'] ?? 0) as int;
    final newRemaining = (currentRemaining - dose).clamp(0, 100000);

    await ref.update({'remainingPills': newRemaining});
    final merged = Map<String, dynamic>.from(data)
      ..['remainingPills'] = newRemaining;

    await _checkOne(uid, medId, merged);
  }

  /// 🔹 Core logic — decides if a notification or state change is needed
  static Future<void> _checkOne(
      String uid, String medId, Map<String, dynamic> data) async {
    try {
      final name = (data['name'] ?? '').toString();
      final total = (data['totalPills'] ?? 0) as int;
      final perDose = (data['perDose'] ?? 1) as int;
      int remaining = (data['remainingPills'] ?? 0) as int;

      if (name.isEmpty || total <= 0 || perDose <= 0) return;

      // Bootstrap missing remaining count
      if (remaining <= 0) {
        remaining = total;
        await _db
            .collection('users')
            .doc(uid)
            .collection('medications')
            .doc(medId)
            .set({'remainingPills': remaining}, SetOptions(merge: true));
      }

      // ✅ Trigger only when remaining <= 5 AND not already notified
      final lowNotified = data['lowStockNotified'] == true;
      if (remaining <= 5 && !lowNotified) {
        await NotificationService.showNow(
          "Refill Needed",
          "$name is running low — only $remaining pill(s) left.",
        );
        await _db
            .collection('users')
            .doc(uid)
            .collection('medications')
            .doc(medId)
            .set({'lowStockNotified': true}, SetOptions(merge: true));
      }

      // ✅ Reset notification flag once user refills above 5
      if (remaining > 5 && lowNotified) {
        await _db
            .collection('users')
            .doc(uid)
            .collection('medications')
            .doc(medId)
            .set({'lowStockNotified': false}, SetOptions(merge: true));
      }

      // ✅ Predict runout for daily/weekly schedules — schedule a reminder 3 days before
      final repeat = (data['repeat'] ?? 'Once').toString();
      final dosesPerDay = repeat == 'Daily'
          ? 1.0
          : repeat == 'Weekly'
          ? (1.0 / 7.0)
          : 0.0;

      if (dosesPerDay > 0) {
        final dosesLeft = remaining / perDose;
        final daysLeft = dosesLeft / dosesPerDay;
        final warnDate =
        DateTime.now().add(Duration(days: daysLeft.ceil() - 3));

        if (warnDate.isAfter(DateTime.now())) {
          final last = (data['refillWarnScheduledAt'] as Timestamp?)?.toDate();
          final shouldSchedule =
              last == null || warnDate.difference(last).inDays.abs() >= 1;

          if (shouldSchedule) {
            await NotificationService.scrubByMed(uid, medId);
            await NotificationService.scheduleAt(
              warnDate,
              "Upcoming Refill Reminder",
              "$name may run out in about ${daysLeft.ceil()} days.",
            );
            await _db
                .collection('users')
                .doc(uid)
                .collection('medications')
                .doc(medId)
                .set(
                {'refillWarnScheduledAt': Timestamp.fromDate(warnDate)},
                SetOptions(merge: true));
          }
        }
      }
    } catch (e) {
      print("⚠️ _checkOne failed: $e");
    }
  }
}
