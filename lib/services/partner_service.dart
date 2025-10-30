// ============================================================================
// lib/services/partner_service.dart
// Centralized partner link/switch/unlink logic using EXISTING partnerCode.
// Invites are just a mirror: /invites/{partnerCode} -> { receiverUid }.
// ============================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PartnerService {
  const PartnerService();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Caregiver links a receiver by the RECEIVER'S existing partnerCode.
  /// Reads /invites/{partnerCode} (doc GET) => receiverUid, then:
  /// - caregiver.linkedReceivers += receiverUid
  /// - caregiver.linkedPartner = receiverUid (if none)
  /// - receiver.linkedPartner = caregiverUid
  Future<String> linkReceiverByPartnerCode(String partnerCode) async {
    final me = _auth.currentUser;
    if (me == null) throw Exception('Not signed in');

    final code = partnerCode.trim().toUpperCase();
    final invite = await _db
        .collection('invites')
        .doc(code)
        .get(const GetOptions(source: Source.server));
    if (!invite.exists) {
      throw Exception('Invalid partner code');
    }
    final receiverUid = (invite.data()?['receiverUid'] as String?) ?? '';
    if (receiverUid.isEmpty) {
      throw Exception('Invalid partner code mapping');
    }

    final cgRef = _db.collection('users').doc(me.uid);
    final rxRef = _db.collection('users').doc(receiverUid);

    final cgSnap = await cgRef.get(const GetOptions(source: Source.server));
    final batch = _db.batch();
// Caregiver side
    batch.set(cgRef, {'role': 'caregiver'}, SetOptions(merge: true));
    batch.update(cgRef, {'linkedReceivers': FieldValue.arrayUnion([receiverUid])});
    batch.set(cgRef, {'linkedPartner': receiverUid}, SetOptions(merge: true)); // ← always active

    // Receiver side (mutual link)
    batch.set(rxRef, {'role': 'receiver', 'linkedPartner': me.uid}, SetOptions(merge: true));

    await batch.commit();
    return receiverUid;
  }

  /// Caregiver switches active receiver (mutual link).
  Future<void> switchActiveReceiver(String receiverUid) async {
    final me = _auth.currentUser;
    if (me == null) throw Exception('Not signed in');

    final cgRef = _db.collection('users').doc(me.uid);
    final rxRef = _db.collection('users').doc(receiverUid);

    final batch = _db.batch();
    batch.set(cgRef, {'role': 'caregiver', 'linkedPartner': receiverUid}, SetOptions(merge: true));
    batch.set(rxRef, {'role': 'receiver', 'linkedPartner': me.uid}, SetOptions(merge: true));
    await batch.commit();
  }

  /// Unlink the currently active partner for either role.
  /// Caregiver: also removes receiver from linkedReceivers[].
  /// Receiver: removes themselves from caregiver.linkedReceivers[].
  Future<String?> unlinkActivePartner() async {
    final me = _auth.currentUser;
    if (me == null) throw Exception('Not signed in');

    final meRef = _db.collection('users').doc(me.uid);
    final meSnap = await meRef.get(const GetOptions(source: Source.server));
    final data = meSnap.data() ?? {};

    final role = (data['role'] as String?)?.toLowerCase() ?? '';
    final partnerId = (data['linkedPartner'] as String?)?.trim() ?? '';
    if (partnerId.isEmpty) return null;

    final partnerRef = _db.collection('users').doc(partnerId);
    final pSnap = await partnerRef.get(const GetOptions(source: Source.server));
    final pData = pSnap.data() ?? {};
    final partnerPointsToMe = (pData['linkedPartner'] as String?)?.trim() == me.uid;

    final batch = _db.batch();

    // Always clear my active link
    batch.update(meRef, {'linkedPartner': FieldValue.delete()});

    // If they point back, clear theirs too
    if (partnerPointsToMe) {
      batch.update(partnerRef, {'linkedPartner': FieldValue.delete()});
    }

    // Maintain lists on BOTH sides
    if (role == 'caregiver') {
      // Remove receiver from caregiver list
      batch.update(meRef, {'linkedReceivers': FieldValue.arrayRemove([partnerId])});
    } else if (role == 'receiver') {
      // Remove receiver from caregiver list (caregiver is 'partnerId')
      batch.update(partnerRef, {'linkedReceivers': FieldValue.arrayRemove([me.uid])});
    }

    await batch.commit();
    return partnerId; // tell UI which uid was removed
  }


  /// Utility to resolve a display name from user doc.
  Future<String?> resolveDisplayName(String uid) async {
    final s = await _db.collection('users').doc(uid).get(const GetOptions(source: Source.serverAndCache));
    final d = s.data() ?? {};
    return (d['profile']?['name'] as String?) ??
        (d['name'] as String?) ??
        (d['email'] as String?);
  }

  /// Utility to read caregiver's linked list.
  Future<List<String>> getLinkedReceivers(String caregiverUid) async {
    final s = await _db.collection('users').doc(caregiverUid).get(const GetOptions(source: Source.serverAndCache));
    final d = s.data() ?? {};
    return (d['linkedReceivers'] as List?)?.cast<String>() ?? const <String>[];
  }
}

// ---------- Backwards-compatible top-level wrappers ----------
const PartnerService _ps = PartnerService();

/// Keep old name used by the dialog/UI.
Future<String> linkReceiverByCode(String partnerCode) =>
    _ps.linkReceiverByPartnerCode(partnerCode);

Future<void> switchActiveReceiver(String receiverUid) =>
    _ps.switchActiveReceiver(receiverUid);

Future<void> unlinkActivePartner() =>
    _ps.unlinkActivePartner();

Future<String?> resolveDisplayName(String uid) =>
    _ps.resolveDisplayName(uid);

Future<List<String>> getLinkedReceivers(String caregiverUid) =>
    _ps.getLinkedReceivers(caregiverUid);
