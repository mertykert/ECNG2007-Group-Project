import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2d59f0), // Blue background
      body: Stack(
        children: [
          // Background circle
          Positioned(
            left: 31,
            top: 284,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                color: const Color(0xFF2B3A96).withValues(alpha: 0.28),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // DNA Image
          Positioned(
            left: -210,
            top: 60,
            child: Transform.rotate(
              angle: 26.763 * 3.1416 / 180, // rotation in radians
              child: Image.asset(
                "assets/images/dna.png", // <-- put your dna.png here
                width: 700.6,
                height: 880.3,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Logo (cross)
          Positioned(
            left: 20,
            top: 40,
            child: Image.asset(
              "assets/images/medcross.png", // <-- put your cross logo here
              width: 60,
              height: 60,
            ),
          ),

          // "MediaCare"
          const Positioned(
            left: 80,
            top: 48,
            child: Text(
              "MediCare",
              style: TextStyle(
                fontFamily: "Inter",
                fontWeight: FontWeight.bold,
                fontSize: 30,
                color: Colors.white,
              ),
            ),
          ),

          // Title
          const Positioned(
            left: 170,
            top: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Improving",
                  style: TextStyle(
                    fontFamily: "Inter",
                    fontWeight: FontWeight.w600,
                    fontSize: 40,
                    color: Colors.white,
                  ),
                ),
                Text(
                  "Health Care",
                  style: TextStyle(
                    fontFamily: "Inter",
                    fontWeight: FontWeight.w600,
                    fontSize: 40,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Sign In Button
          Positioned(
            left: 30,
            bottom: 40,
            child: _roundedButton(
              text: "Sign In ",
              color: Colors.white,
              textColor: Colors.black,
              iconColor: Colors.black,
              onTap: () {
                Navigator.pushNamed(context, "/signin");
              },
            ),
          ),


          // Sign Up Button
          Positioned(
            right: 30,
            bottom: 40,
            child: _roundedButton(
              text: "Sign Up  ",
              color: Colors.white,
              textColor: Colors.black,
              iconColor: Colors.black,
              onTap: () {
                Navigator.pushNamed(context, "/signup");
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundedButton({
    required String text,
    required Color color,
    required Color textColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 169,
        height: 68,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Text
            Center(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: "Inter",
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),

            // Circle icon container
            Positioned(
              right: 10,
              top: 10,
              bottom: 10,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconColor == Colors.blue ? Colors.blue : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_outward,
                  color: iconColor,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
