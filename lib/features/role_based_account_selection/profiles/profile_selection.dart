import 'package:flutter/material.dart';
import 'care_giver_1st.dart';
import 'care_receiver_1st.dart';
import 'edit_profile.dart';

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  // Profile names
  String caregiverName = "Care Giver";
  String careReceiverName = "Care Receiver";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6A11CB),
              Color(0xFF2575FC),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Select Your Profile',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildProfileCard(
                  context,
                  label: caregiverName,
                  color: Colors.blueAccent,
                  icon: Icons.person,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CaregiverScreen(),
                      ),
                    );
                  },
                  onEdit: () async {
                    String? newName = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            EditProfileScreen(currentName: caregiverName),
                      ),
                    );
                    if (newName != null && newName.isNotEmpty) {
                      setState(() {
                        caregiverName = newName;
                      });
                    }
                  },
                ),
                const SizedBox(width: 40),
                _buildProfileCard(
                  context,
                  label: careReceiverName,
                  color: Colors.cyanAccent,
                  icon: Icons.person,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CarereceiverScreen(),
                      ),
                    );
                  },
                  onEdit: () async {
                    String? newName = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            EditProfileScreen(currentName: careReceiverName),
                      ),
                    );
                    if (newName != null && newName.isNotEmpty) {
                      setState(() {
                        careReceiverName = newName;
                      });
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(
      BuildContext context, {
        required String label,
        required Color color,
        required IconData icon,
        required VoidCallback onTap,
        required VoidCallback onEdit,
      }) {
    // Create a translucent background using Color.fromRGBO
    Color translucentColor = Color.fromRGBO(
      color.red,
      color.green,
      color.blue,
      0.3, // 30% opacity
    );

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 140,
            height: 180,
            decoration: BoxDecoration(
              color: translucentColor, // translucent bubble
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: color,
                  child: Icon(icon, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 15),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit, size: 18),
          label: const Text("Edit Profile"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromRGBO(255, 255, 255, 0.1), // translucent white
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      ],
    );
  }
}
