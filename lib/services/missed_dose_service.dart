// ============================================================================
// lib/background/missed_dose_service.dart
// ============================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class MissedDoseService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<void> checkMissedDosesFor(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastRun = prefs.getString('lastMissedCheck_$uid');
      if (lastRun == todayIso) return; // once per day

      // We evaluate *yesterday* across schedules
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yIso = DateFormat('yyyy-MM-dd').format(yesterday);

      // 🔧 IMPORTANT: do NOT filter by 'date' == yIso; that drops Daily/Weekly meds
      final medsSnap = await _firestore
          .collection('users').doc(uid)
          .collection('medications')
          .get();

      final missedList = <Map<String, dynamic>>[];

      for (final doc in medsSnap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? '').toString();

        // 1) Was this med scheduled for yesterday?
        final repeat = (data['repeat'] ?? 'Once').toString().trim().toLowerCase();
        final dateStr = (data['date'] ?? '').toString().trim();
        final scheduled = _isScheduledForDay(repeat: repeat, dateStr: dateStr, day: yesterday);
        if (!scheduled) continue;

        // 2) Did the user mark it taken yesterday? (by map/list/lastTakenDate)
        final byDate = (data['takenByDate'] as Map?)?.cast<String, dynamic>();
        final takenByMap  = byDate != null && (byDate[yIso] == true || byDate[yIso] == 1);
        final takenByLast = (data['lastTakenDate'] as String?) == yIso;
        final takenByList = ((data['takenDates'] as List?) ?? const []).contains(yIso);
        final taken = takenByMap || takenByLast || takenByList;

        if (!taken) {
          missedList.add({
            'name': name.isEmpty ? 'Unknown' : name,
            'time': data['time'],
            'date': yIso,
            'at': FieldValue.serverTimestamp(),
          });
        }
      }

      // Write summary doc (empty list clears UI if you read it)
      await _firestore
          .collection('users').doc(uid)
          .collection('missed')
          .doc(yIso)
          .set({'meds': missedList});

      // Notify only if there are misses
      if (missedList.isNotEmpty) {
        await NotificationService.showNow(
          "Missed Dose Summary",
          "You missed ${missedList.length} medication${missedList.length > 1 ? 's' : ''} yesterday.",
        );
      }

      // Daily cleanup: clear sticky scalar & 'adjustedFor' rollover
      final meds = await _firestore.collection('users').doc(uid).collection('medications').get();
      final batch = _firestore.batch();
      for (final d in meds.docs) {
        final data = d.data();
        final updates = <String, dynamic>{'taken': false};
        if ((data['adjustedFor'] as String?) == todayIso) {
          updates['adjustedFor'] = FieldValue.delete();
        }
        batch.update(d.reference, updates);
      }
      await batch.commit();

      await prefs.setString('lastMissedCheck_$uid', todayIso);
    } catch (e) {
      print("⚠️ MissedDoseService failed: $e");
    }
  }

  // Minimal schedule check matching your app semantics
  static bool _isScheduledForDay({
    required String repeat,
    required String dateStr,
    required DateTime day,
  }) {
    final r = repeat.toLowerCase();
    if (r == 'daily') return true;
    if (r == 'weekly') {
      final base = DateTime.tryParse(dateStr) ?? _tryYmd(dateStr);
      if (base == null) return false;
      return base.weekday == day.weekday;
    }
    // once:
    final dt = DateTime.tryParse(dateStr) ?? _tryYmd(dateStr);
    if (dt == null) return false;
    return dt.year == day.year && dt.month == day.month && dt.day == day.day;
  }

  static DateTime? _tryYmd(String s) {
    if (s.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(s);
    } catch (_) {
      return null;
    }
  }
}