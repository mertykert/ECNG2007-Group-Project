import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LinkPartnerDialog extends StatefulWidget {
  const LinkPartnerDialog({super.key});

  @override
  State<LinkPartnerDialog> createState() => _LinkPartnerDialogState();
}

class _LinkPartnerDialogState extends State<LinkPartnerDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  Future<void> linkWithPartnerCode(String enteredCode) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
    final userDoc = await userRef.get();

    // 🔍 Look up the entered partner code
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('partnerCode', isEqualTo: enteredCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Invalid partner code.');
    }

    final partnerDoc = query.docs.first;
    final partnerId = partnerDoc.id;

    // 🚫 Prevent linking to self
    if (partnerId == currentUser.uid) {
      throw Exception('You cannot link with your own code.');
    }

    // 🔁 Check if already linked
    if (userDoc['linkedPartner'] == partnerId) {
      throw Exception('You are already linked with this partner.');
    }

    // 🔗 Link both accounts symmetrically
    WriteBatch batch = FirebaseFirestore.instance.batch();
    batch.update(userRef, {'linkedPartner': partnerId});
    batch.update(
      FirebaseFirestore.instance.collection('users').doc(partnerId),
      {'linkedPartner': currentUser.uid},
    );
    await batch.commit();
  }

  /// 🔹 Handles button press
  Future<void> _linkPartner() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorText = null;
      _isLoading = true;
    });

    try {
      final enteredCode = _codeController.text.trim().toUpperCase();
      if (enteredCode.isEmpty) {
        setState(() {
          _errorText = 'Please enter a partner code.';
          _isLoading = false;
        });
        return;
      }

      await linkWithPartnerCode(enteredCode);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Partner linked successfully!"),
          backgroundColor: const Color(0xFF2d59f0),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString().replaceAll('Exception: ', '');
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_errorText!),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Link Partner",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Color(0xFF2d59f0),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: "Enter Partner Code",
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                errorText: _errorText,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _linkPartner,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2d59f0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Link Now"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
