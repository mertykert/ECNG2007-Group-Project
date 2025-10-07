import 'package:flutter/material.dart';
import '../../../models/user_models/user_role.dart';

class ProfileCard extends StatelessWidget {
  final UserRole role;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const ProfileCard({
    super.key,
    required this.role,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 180,
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          // Consistent translucent white background using ARGB
          color: const Color.fromARGB(38, 255, 255, 255), // 15% opacity
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(51, 0, 0, 0), // 20% opacity black
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
              backgroundColor: role.color,
              child: Icon(role.icon, size: 50, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              role.name,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20, color: Colors.white),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}
