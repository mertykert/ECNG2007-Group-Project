// lib/screens/profile_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  bool _isLoading = false;

  Future<void> _setRole(String role) async {
    setState(() => _isLoading = true);
    try {
      final auth = FirebaseAuth.instance;
      final db = FirebaseFirestore.instance;
      final user = auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      final userRef = db.collection('users').doc(user.uid);

      // Save role first (why: rules & downstream UI depend on it).
      await userRef.set({'role': role}, SetOptions(merge: true));

      if (role == 'receiver') {
        // Reuse existing partnerCode or generate fallback.
        final snap = await userRef.get(const GetOptions(source: Source.serverAndCache));
        final data = snap.data() ?? {};
        String code = (data['partnerCode'] as String?)?.trim() ?? '';
        if (code.isEmpty) {
          code = user.uid.substring(0, 6).toUpperCase();
          await userRef.set({'partnerCode': code}, SetOptions(merge: true));
        }

        // Mirror to /invites/{partnerCode} -> { receiverUid } (no queries needed).
        await db.collection('invites').doc(code).set({
          'receiverUid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/HomeScreen');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF2D59F0);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Stack(
          children: [
            // Content
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 28),
                  const Text(
                    "Select Your Profile",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: brandBlue,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Choose your role to personalize your MediCare experience.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.25),
                  ),
                  const SizedBox(height: 36),

                  // Cards: use Wrap to avoid overflow on small screens.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 24,
                    runSpacing: 24,
                    children: [
                      _buildProfileCard(
                        icon: Icons.volunteer_activism_rounded,
                        label: "Care Giver",
                        description: "Manage and monitor medications for your receivers.",
                        color: brandBlue,
                        onTap: _isLoading ? null : () => _setRole('caregiver'),
                      ),
                      _buildProfileCard(
                        icon: Icons.favorite_rounded,
                        label: "Care Receiver",
                        description: "Stay on top of your own medication schedule.",
                        color: const Color(0xFF00B0FF),
                        onTap: _isLoading ? null : () => _setRole('receiver'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 60),
                ],
              ),
            ),

            // Busy overlay
            if (_isLoading)
              Container(
                color: Colors.white.withOpacity(0.6),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: brandBlue),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      // Let height grow if needed; keep a nice width range for responsiveness.
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 220, minHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black12.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          splashColor: color.withOpacity(0.08),
          highlightColor: color.withOpacity(0.04),
          onTap: onTap,
          child: Padding(
            // slightly tighter vertical padding to avoid overflow
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.10),
                  ),
                  child: Icon(icon, color: color, size: 30), // a tad smaller
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                // Make the description flexible so it never overflows.
                Flexible(
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black54,
                      height: 1.22,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Keep the chevron but don't force extra space via Spacer()
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.chevron_right_rounded, color: Colors.black26),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
