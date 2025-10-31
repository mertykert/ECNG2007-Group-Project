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

  // Keys (consistent everywhere)
  static String todayMedsKey(String ownerId, String date) => 'todayMeds:$ownerId:$date';
  static String todayProgressKey(String ownerId, String date) => 'todayProgress:$ownerId:$date';
  static String weekProgressKey(String ownerId, String weekStartIso) => 'weekProgress:$ownerId:$weekStartIso';

  // ----------------- Writes -----------------
  static Future<void> saveTodayMeds(String ownerId, String date, List<Map<String, dynamic>> meds) async {
    final b = _meds;
    if (b == null) return; // avoid HiveError before init
    // store as plain List<Map> (mutable on load)
    await b.put(todayMedsKey(ownerId, date), meds.map((m) => Map<String, dynamic>.from(m)).toList());
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

  // ----------------- Reads -----------------
  static List<Map<String, dynamic>> loadTodayMeds(String ownerId, String date) {
    final b = _meds;
    if (b == null) return const [];
    final raw = b.get(todayMedsKey(ownerId, date));
    if (raw is List) {
      // materialize to a mutable list of mutable maps
      return raw
          .where((e) => e is Map)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
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
      return raw.where((e) => e is num).map((e) => (e as num).toDouble()).toList();
    }
    return null;
  }

  // ----------------- Local mutations -----------------

  /// Upsert by id if present, otherwise by (name,time,date) composite.
  static Future<void> upsertTodayMed(
      String ownerId,
      String date,
      Map<String, dynamic> med,
      ) async {
    final b = _meds;
    if (b == null) return;

    final list = loadTodayMeds(ownerId, date); // mutable copy
    final id = (med['id'] as String?)?.trim();

    int idx = -1;
    if (id != null && id.isNotEmpty) {
      idx = list.indexWhere((m) => (m['id'] as String?) == id);
    } else {
      idx = list.indexWhere((m) =>
      (m['name'] ?? '') == (med['name'] ?? '') &&
          (m['time'] ?? '') == (med['time'] ?? '') &&
          (m['date'] ?? '') == (med['date'] ?? ''));
    }

    if (idx >= 0) {
      list[idx] = {...list[idx], ...med};
    } else {
      list.add(Map<String, dynamic>.from(med));
    }

    await b.put(todayMedsKey(ownerId, date), list);
  }

  /// Delete by Firestore medId (preferred). Falls back to (name,time,date) if id missing.
  static Future<void> deleteTodayMedById(String ownerId, String dayIso, String medId, {Map<String, dynamic>? fallbackMed}) async {
    final b = _meds;
    if (b == null) return;

    final key = todayMedsKey(ownerId, dayIso);
    final list = loadTodayMeds(ownerId, dayIso); // mutable copy

    int before = list.length;
    list.removeWhere((m) => (m['id'] as String?) == medId);

    // If nothing removed and we have fallback fields, try composite
    if (list.length == before && fallbackMed != null) {
      final name = (fallbackMed['name'] ?? '') as String;
      final time = (fallbackMed['time'] ?? '') as String;
      final date = (fallbackMed['date'] ?? '') as String;
      list.removeWhere((m) =>
      (m['name'] ?? '') == name &&
          (m['time'] ?? '') == time &&
          (m['date'] ?? '') == date);
    }

    await b.put(key, list);
  }
}
