// lib/background/missed_dose_worker.dart
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final uid = user.uid;
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final medsSnapshot = await userRef.collection('medications').get();
      final missedMeds = <Map<String, dynamic>>[];

      for (final doc in medsSnapshot.docs) {
        final data = doc.data();

        // Only process meds for today
        if (data['date'] != todayStr) continue;

        // Skip if already taken
        if (data['taken'] == true) continue;

        final medTimeStr = (data['time'] as String?)?.trim();
        if (medTimeStr == null || medTimeStr.isEmpty) continue;

        // Parse time (e.g., "8:00 AM")
        DateTime medTime;
        try {
          final parsed = DateFormat.jm().parse(medTimeStr);
          medTime = DateTime(now.year, now.month, now.day, parsed.hour, parsed.minute);
        } catch (_) {
          continue;
        }

        // Mark as missed if 1 hour past scheduled time
        if (now.isAfter(medTime.add(const Duration(minutes: 60)))) {
          missedMeds.add({'name': data['name'], 'time': medTimeStr});
        }
      }

      // Save missed meds summary for today
      if (missedMeds.isNotEmpty) {
        await userRef.collection('missed').doc(todayStr).set({'meds': missedMeds});

        // Notify user once for all missed meds
        final missedNames = missedMeds.map((m) => m['name']).join(', ');
        await NotificationService.showNow(
          "Missed Dose Alert",
          "You missed: $missedNames",
        );
      }

      return true;
    } catch (e) {
      print("⚠️ WorkManager missed dose task failed: $e");
      return false;
    }
  });
}
