import 'package:firebase_analytics/firebase_analytics.dart';

class AppAnalytics {
  AppAnalytics._();
  static final FirebaseAnalytics _a = FirebaseAnalytics.instance;

  static Future<void> setAnalyticsEnabled(bool enabled) =>
      _a.setAnalyticsCollectionEnabled(enabled);

  static Future<void> identifyUser({required String uid, String? role}) async {
    await _a.setUserId(id: uid);
    if (role != null && role.isNotEmpty) {
      await _a.setUserProperty(name: 'role', value: role);
    }
  }

  /// Ensure GA4 param types are String or num.
  static Map<String, Object> params(Map<String, Object?> raw) {
    final out = <String, Object>{};
    raw.forEach((k, v) {
      if (v == null) return;
      if (v is bool) {
        out[k] = v ? 1 : 0;
      } else if (v is num || v is String) {
        out[k] = v as Object;
      } else {
        out[k] = v.toString();
      }
    });
    return out;
  }

  static Future<void> setUserPropsFromEnv({
    required String tzName,
    required int tzOffsetMinutes,
    required String locale,
    required String platform,
    String? appCountry, // NEW
  }) async {
    await Future.wait([
      _a.setUserProperty(name: 'tz', value: tzName),
      _a.setUserProperty(name: 'tz_offset_minutes', value: '$tzOffsetMinutes'),
      _a.setUserProperty(name: 'locale', value: locale),
      _a.setUserProperty(name: 'platform', value: platform),
      if (appCountry != null && appCountry.isNotEmpty)
        _a.setUserProperty(name: 'app_country', value: appCountry),
    ]);
  }

  static Future<void> logSignIn({String? method}) =>
      _a.logLogin(loginMethod: method ?? 'password');

  static Future<void> logSignUp({String? method}) =>
      _a.logSignUp(signUpMethod: method ?? 'password');

  static Future<void> logPartnerLinked({required String receiverUid}) =>
      _a.logEvent(name: 'partner_linked', parameters: params({
        'receiver_uid_hash': _hash(receiverUid),
      }));

  static Future<void> logPartnerUnlinked({required String partnerUid}) =>
      _a.logEvent(name: 'partner_unlinked', parameters: params({
        'partner_uid_hash': _hash(partnerUid),
      }));

  static Future<void> logReceiverSwitched({required String receiverUid}) =>
      _a.logEvent(name: 'receiver_switched', parameters: params({
        'receiver_uid_hash': _hash(receiverUid),
      }));

  static Future<void> logMedicationAdded({
    required String ownerUid,
    required String repeat,
  }) =>
      _a.logEvent(name: 'med_added', parameters: params({
        'owner_uid_hash': _hash(ownerUid),
        'repeat': repeat,
      }));

  static Future<void> logMedicationTaken({
    required String ownerUid,
    required String medId,
    required bool taken,
  }) =>
      _a.logEvent(name: 'med_taken', parameters: params({
        'owner_uid_hash': _hash(ownerUid),
        'med_id_hash': _hash(medId),
        'taken': taken,
      }));

  static String _hash(String v) {
    return v.codeUnits
        .fold<int>(0, (a, b) => (a * 131 + b) & 0x7fffffff)
        .toRadixString(16);
  }
}
