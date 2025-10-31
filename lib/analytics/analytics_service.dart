import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppAnalytics {
  AppAnalytics._();
  static final FirebaseAnalytics _a = FirebaseAnalytics.instance;

  Future<void> setAnalyticsEnabled(bool enabled) async {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
  }

  static Future<void> identifyUser({required String uid, String? role}) async {
    await _a.setUserId(id: uid);
    if (role != null && role.isNotEmpty) {
      await _a.setUserProperty(name: 'role', value: role); // caregiver|receiver
    }
  }

  static Future<void> logSignIn({String? method}) =>
      _a.logLogin(loginMethod: method ?? 'password');

  static Future<void> logSignUp({String? method}) =>
      _a.logSignUp(signUpMethod: method ?? 'password');

  static Future<void> logPartnerLinked({required String receiverUid}) =>
      _a.logEvent(name: 'partner_linked', parameters: {'receiver_uid_hash': _hash(receiverUid)});

  static Future<void> logPartnerUnlinked({required String partnerUid}) =>
      _a.logEvent(name: 'partner_unlinked', parameters: {'partner_uid_hash': _hash(partnerUid)});

  static Future<void> logReceiverSwitched({required String receiverUid}) =>
      _a.logEvent(name: 'receiver_switched', parameters: {'receiver_uid_hash': _hash(receiverUid)});

  static Future<void> logMedicationAdded({
    required String ownerUid,
    required String repeat,            // Daily|Weekly|Once
  }) => _a.logEvent(name: 'med_added', parameters: {
    'owner_uid_hash': _hash(ownerUid),
    'repeat': repeat,
  });

  static Future<void> logMedicationTaken({
    required String ownerUid,
    required String medId,
    required bool taken,
  }) => _a.logEvent(name: 'med_taken', parameters: {
    'owner_uid_hash': _hash(ownerUid),
    'med_id_hash': _hash(medId),
    'taken': taken,
  });

  static String _hash(String v) {
    // Very light pseudo-hash to avoid sending raw IDs; replace with a real hash if desired.
    return v.codeUnits.fold<int>(0, (a, b) => (a * 131 + b) & 0x7fffffff).toRadixString(16);
  }
}

