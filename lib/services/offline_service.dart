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
    if (b == null) return <Map<String, dynamic>>[];

    final raw = b.get(todayMedsKey(ownerId, date));
    if (raw is List) {
      // deep copy + growable so callers can modify
      return raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: true);
    }
    return <Map<String, dynamic>>[];
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

    final key = todayMedsKey(ownerId, date);
    final raw = b.get(key);

    // Always work on a growable deep copy
    final List<Map<String, dynamic>> list = (raw is List)
        ? raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: true)
        : <Map<String, dynamic>>[];

    final idx = list.indexWhere((m) =>
    (m['id'] ?? '') == (med['id'] ?? '') || // prefer id if present
        ((m['name'] ?? '') == (med['name'] ?? '') &&
            (m['time'] ?? '') == (med['time'] ?? '') &&
            (m['date'] ?? '') == (med['date'] ?? '')));

    if (idx >= 0) {
      list[idx] = {...list[idx], ...med};
    } else {
      list.add(med);
    }

    await b.put(key, list);
  }

  /// Delete by Firestore medId (preferred). Falls back to (name,time,date) if id missing.
  static Future<void> deleteTodayMedById(String ownerUid, String dayIso, String medId) async {
    final b = _meds;
    if (b == null) return;

    final key = todayMedsKey(ownerUid, dayIso);
    final raw = b.get(key);

    final List<Map<String, dynamic>> list = (raw is List)
        ? raw
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: true)
        : <Map<String, dynamic>>[];

    list.removeWhere((m) => (m['id'] as String?) == medId);
    await b.put(key, list);
  }
}
