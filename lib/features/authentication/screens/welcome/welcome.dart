import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _buttonController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Future<LottieComposition> _dnaComposition;

  @override
  void initState() {
    super.initState();

    _dnaComposition = AssetLottie('assets/animations/DNA Loader.json').load();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _buttonController,
      curve: Curves.easeOut,
    ));

    Future.delayed(const Duration(milliseconds: 600), () {
      _fadeController.forward();
      _buttonController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF2d59f0),
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Combined circle + DNA animation (auto-centered)
            Align(
              alignment: const Alignment(0, 0.15), // controls general vertical position on the screen
              child: SizedBox(
                width: size.width * 0.9,
                height: size.width * 0.9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B3A96).withOpacity(0.28),
                        shape: BoxShape.circle,
                      ),
                    ),

                    // DNA animation perfectly centered in the circle
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Transform.rotate(
                        angle: -0.4,
                        child: FractionallySizedBox(
                          widthFactor: 2.0,
                          heightFactor: 1.6,
                          child: FutureBuilder<LottieComposition>(
                            future: _dnaComposition,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const SizedBox.shrink();
                              return Lottie(
                                composition: snapshot.data!,
                                repeat: true,
                                animate: true,
                                fit: BoxFit.contain,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Logo
            Positioned(
              left: size.width * 0.05,
              top: size.height * 0.03,
              child: Image.asset(
                "assets/images/medcross.png",
                width: size.width * 0.12,
                height: size.width * 0.12,
              ),
            ),

            // App name
            Positioned(
              left: size.width * 0.20,
              top: size.height * 0.035,
              child: Text(
                "MediCare",
                style: TextStyle(
                  fontFamily: "Inter",
                  fontWeight: FontWeight.bold,
                  fontSize: size.width * 0.075,
                  color: Colors.white,
                ),
              ),
            ),

            // Title text
            Positioned(
              right: size.width * 0.08,
              top: size.height * 0.18,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Improving",
                      style: TextStyle(
                        fontFamily: "Inter",
                        fontWeight: FontWeight.w600,
                        fontSize: size.width * 0.095,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "Health Care",
                      style: TextStyle(
                        fontFamily: "Inter",
                        fontWeight: FontWeight.w600,
                        fontSize: size.width * 0.095,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Buttons
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.06,
                  vertical: size.height * 0.05,
                ),
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: size.width * 0.03),
                          child: _roundedButton(
                            size: size,
                            text: "Sign In",
                            color: Colors.white,
                            textColor: Colors.black,
                            iconColor: Colors.black,
                            onTap: () async {
                              final prefs = await SharedPreferences.getInstance();
                              final user = FirebaseAuth.instance.currentUser;
                              final wasLoggedInOnce = prefs.getBool('isLoggedInOnce') ?? false;

                              if (user != null && wasLoggedInOnce) {
                                await user.reload();
                                final refreshedUser = FirebaseAuth.instance.currentUser;

                                if (refreshedUser != null && refreshedUser.emailVerified) {
                                  final doc = await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(refreshedUser.uid)
                                      .get();

                                  if (doc.exists && doc.data()?['role'] == 'caregiver') {
                                    Navigator.pushReplacementNamed(context, '/HomeScreen');
                                  } else if (doc.exists && doc.data()?['role'] == 'receiver') {
                                    Navigator.pushReplacementNamed(context, '/HomeScreen');
                                  } else {
                                    Navigator.pushReplacementNamed(context, '/profileSelect');
                                  }
                                  return;
                                } else {
                                  await FirebaseAuth.instance.signOut();
                                }
                              }

                              Navigator.pushNamed(context, '/signin');
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: size.width * 0.03),
                          child: _roundedButton(
                            size: size,
                            text: "Sign Up",
                            color: Colors.white,
                            textColor: Colors.black,
                            iconColor: Colors.black,
                            onTap: () =>
                                Navigator.pushNamed(context, "/signup"),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundedButton({
    required Size size,
    required String text,
    required Color color,
    required Color textColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: size.height * 0.075,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size.height * 0.037),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: TextStyle(
                fontFamily: "Inter",
                fontSize: size.width * 0.045,
                color: textColor,
              ),
            ),
            SizedBox(width: size.width * 0.02),
            Icon(
              Icons.arrow_outward,
              color: iconColor,
              size: size.width * 0.055,
            ),
          ],
        ),
      ),
    );
  }
}
