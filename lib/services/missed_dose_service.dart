import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class MissedDoseService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<void> checkMissedDosesFor(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastRun = prefs.getString('lastMissedCheck_$uid');

      // ✅ Only run once per day
      if (lastRun == today) {
        return;
      }

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final dateStr = DateFormat('yyyy-MM-dd').format(yesterday);

      final medsSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('medications')
          .where('date', isEqualTo: dateStr)
          .get();

      final missedList = <Map<String, dynamic>>[];

      for (final doc in medsSnapshot.docs) {
        final data = doc.data();
        final taken = data['taken'] == true;
        if (!taken) {
          missedList.add({
            'name': data['name'] ?? 'Unknown',
            'time': data['time'],
            'date': dateStr,
            'at': FieldValue.serverTimestamp(),
          });
        }
      }

      // ✅ Write summary
      if (missedList.isNotEmpty) {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('missed')
            .doc(dateStr)
            .set({'meds': missedList});

        await NotificationService.showNow(
          "Missed Dose Summary",
          "You missed ${missedList.length} medication${missedList.length > 1 ? 's' : ''} yesterday.",
        );
      }

      await prefs.setString('lastMissedCheck_$uid', today);
    } catch (e) {
      print("⚠️ MissedDoseService failed: $e");
    }
  }
}
