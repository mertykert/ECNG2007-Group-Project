// lib/services/offline_service.dart
import 'package:hive_flutter/hive_flutter.dart';

/// Offline cache with safe, no-crash Hive access.
class OfflineService {
  static const String _medsBox = 'meds';
  static const String _takenLogBox = 'taken_log';

  /// Call once at app start (before using this service).
  static Future<void> init() async {
    if (!Hive.isBoxOpen(_medsBox) || !Hive.isBoxOpen(_takenLogBox)) {
      await Hive.initFlutter();
    }
    await _openIfNeeded(_medsBox);
    await _openIfNeeded(_takenLogBox);
  }

  static Future<Box> _openIfNeeded(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name);
  }

  // Nullable getters; callers must guard.
  static Box<dynamic>? get _meds => Hive.isBoxOpen(_medsBox) ? Hive.box(_medsBox) : null;

  // Keys
  static String todayMedsKey(String ownerId, String date) => 'todayMeds:$ownerId:$date';
  static String todayProgressKey(String ownerId, String date) => 'todayProgress:$ownerId:$date';
  static String weekProgressKey(String ownerId, String weekStartIso) => 'weekProgress:$ownerId:$weekStartIso';

  // Writes (no-ops if box closed)
  static Future<void> saveTodayMeds(String ownerId, String date, List<Map<String, dynamic>> meds) async {
    final b = _meds;
    if (b == null) return; // why: avoid HiveError before init
    await b.put(todayMedsKey(ownerId, date), meds);
  }

  static Future<void> saveTodayProgress(String ownerId, String date, double progress) async {
    final b = _meds;
    if (b == null) return;
    await b.put(todayProgressKey(ownerId, date), progress);
  }

  static Future<void> saveWeekProgress(String ownerId, String weekStartIso, List<double> ratios) async {
    final b = _meds;
    if (b == null) return;
    await b.put(weekProgressKey(ownerId, weekStartIso), ratios);
  }

  // Reads (return defaults if box closed/missing)
  static List<Map<String, dynamic>> loadTodayMeds(String ownerId, String date) {
    final b = _meds;
    if (b == null) return const [];
    final raw = b.get(todayMedsKey(ownerId, date));
    if (raw is List) {
      return raw.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  static double? loadTodayProgress(String ownerId, String date) {
    final b = _meds;
    if (b == null) return null;
    final v = b.get(todayProgressKey(ownerId, date));
    if (v is num) return v.toDouble();
    return null;
  }

  static List<double>? loadWeekProgress(String ownerId, String weekStartIso) {
    final b = _meds;
    if (b == null) return null;
    final raw = b.get(weekProgressKey(ownerId, weekStartIso));
    if (raw is List) {
      return raw.map((e) => (e as num).toDouble()).toList();
    }
    return null;
  }

  // Local mutations (safe if box closed)
  static Future<void> upsertTodayMed(
      String ownerId,
      String date,
      Map<String, dynamic> med,
      ) async {
    final b = _meds;
    if (b == null) return;
    final list = loadTodayMeds(ownerId, date);
    final idx = list.indexWhere((m) =>
    (m['name'] ?? '') == (med['name'] ?? '') &&
        (m['time'] ?? '') == (med['time'] ?? '') &&
        (m['date'] ?? '') == (med['date'] ?? ''));
    if (idx >= 0) {
      list[idx] = {...list[idx], ...med};
    } else {
      list.add(med);
    }
    await b.put(todayMedsKey(ownerId, date), list);
  }

  static Future<void> deleteTodayMedById(String ownerUid, String dayIso, String medId) async {
    final box = Hive.box('scheduled_reminders'); // or your meds cache box if different
    final key = 'today_$ownerUid\_$dayIso';

    final raw = box.get(key);
    // Always materialize to a mutable List<Map>
    final List<Map<String, dynamic>> list = (raw is List)
        ? raw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    list.removeWhere((m) => (m['id'] as String?) == medId);

    await box.put(key, list);
  }
}
