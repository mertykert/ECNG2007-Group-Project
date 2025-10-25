// lib/screens/profile_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;

  Future<void> _setRole(String role) async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'role': role},
        SetOptions(merge: true),
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pushReplacementNamed(context, '/HomeScreen');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Center(
          child: Stack(
            children: [
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2D59F0)),
                ),
              if (!_isLoading)
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        const Text(
                          "Select Your Profile",
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D59F0),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Choose your role to personalize your MediCare experience.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.black54,
                          ),
                        ),

                        const SizedBox(height: 40),

                        // FIX: Row -> Wrap to avoid horizontal overflow on 360dp screens.
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 24,
                          runSpacing: 24,
                          children: [
                            _buildProfileCard(
                              icon: Icons.volunteer_activism_rounded,
                              label: "Care Giver",
                              description: "Manage and monitor medications.",
                              color: const Color(0xFF2D59F0),
                              onTap: () => _setRole('caregiver'),
                            ),
                            _buildProfileCard(
                              icon: Icons.favorite_rounded,
                              label: "Care Receiver",
                              description: "Stay on top of your schedule.",
                              color: const Color(0xFF00B0FF),
                              onTap: () => _setRole('receiver'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: 150, // Intentional fixed width; Wrap will move to next line if needed.
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material( // Needed for InkWell ripple
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          splashColor: color.withOpacity(0.1),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 65,
                  height: 65,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.1),
                  ),
                  child: Icon(icon, color: color, size: 34),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.black54,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
