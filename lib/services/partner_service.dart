import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Unlinks the current user from their partner.
/// Clears the link for both users and generates
/// a new unique partner code for the current user.
Future<void> unlinkPartnerAndRegenerateCode() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final userSnap = await userRef.get();
  final data = userSnap.data();

  if (data == null) return;

  final partnerId = data['linkedPartner'];

  // 🔹 Generate a new unique 6-character partner code
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rand = DateTime.now().millisecondsSinceEpoch.remainder(999999);
  final newCode = List.generate(
    6,
        (i) => chars[(rand + i * 37) % chars.length],
  ).join();


  // 🔹 Reset both users atomically using a Firestore batch
  final batch = FirebaseFirestore.instance.batch();

  // Current user: remove link and assign new code
  batch.update(userRef, {
  'linkedPartner': null,
  'partnerCode': newCode,
  });

  // Partner (if exists): remove link too
  if (partnerId != null) {
  final partnerRef =
  FirebaseFirestore.instance.collection('users').doc(partnerId);
  batch.update(partnerRef, {'linkedPartner': null});
  }

  await batch.commit();
}
