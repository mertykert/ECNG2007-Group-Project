import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_size_text/auto_size_text.dart';


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
  final _titleGroup = AutoSizeGroup();

  bool _busy = false;

  Future<bool> _hasNetwork() async {
    final r = await Connectivity().checkConnectivity();
    return r.contains(ConnectivityResult.mobile) || r.contains(ConnectivityResult.wifi);
  }

  Future<void> _openOfflineIfPossible() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('No offline session found. Connect once to sign in.');
      return;
    }
    try {
      // warm from cache (no throw if offline)
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .get(const GetOptions(source: Source.cache));
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/HomeScreen');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _handleWelcomeSignInPressed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final online = await _hasNetwork();

      // IMPORTANT: do NOT call currentUser.reload() when offline.
      // (This was causing your exception in the stack trace.)
      if (!online) {
        await _openOfflineIfPossible();
        return;
      }

      // If online, navigate to the real Sign In screen
      if (!mounted) return;
      Navigator.pushNamed(context, '/signin');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


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
              top: size.height * 0.02,
              child: Image.asset(
                "assets/images/medcross.png",
                width: size.width * 0.15,
                height: size.width * 0.15,
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
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: size.width * 0.62),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AutoSizeText(
                        "Improving",
                        maxLines: 1,
                        minFontSize: 16,
                        stepGranularity: 0.5,
                        group: _titleGroup,
                        style: TextStyle(
                          fontFamily: "Inter",
                          fontWeight: FontWeight.w600,
                          fontSize: size.width * 0.095, // acts as the upper bound
                          color: Colors.white,
                        ),
                      ),
                      AutoSizeText(
                        "Health Care",
                        maxLines: 1,
                        minFontSize: 16,
                        stepGranularity: 0.5,
                        group: _titleGroup,
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
                              final wasLoggedInOnce = prefs.getBool('isLoggedInOnce') ?? false;
                              final user = FirebaseAuth.instance.currentUser;

                              // Detect connectivity
                              final conn = await Connectivity().checkConnectivity();
                              final online = conn.contains(ConnectivityResult.mobile) || conn.contains(ConnectivityResult.wifi);

                              if (!online) {
                                // OFFLINE: allow entry only if there is a cached session
                                if (user != null && wasLoggedInOnce) {
                                  // Warm cache (no network)
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('users').doc(user.uid)
                                        .get(const GetOptions(source: Source.cache));
                                  } catch (_) {}
                                  if (!context.mounted) return;
                                  Navigator.pushReplacementNamed(context, '/HomeScreen');
                                } else {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('No offline session found. Connect to the internet to sign in once.')),
                                  );
                                }
                                return;
                              }

                              // ONLINE: keep your original logic, but guard reload with try/catch
                              try {
                                await user?.reload();
                              } catch (_) {
                                // ignore transient reload errors
                              }
                              final refreshedUser = FirebaseAuth.instance.currentUser;

                              if (refreshedUser != null && (refreshedUser.emailVerified)) {
                                final doc = await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(refreshedUser.uid)
                                    .get(const GetOptions(source: Source.serverAndCache));

                                if (!context.mounted) return;
                                final role = (doc.data()?['role'] as String?)?.toLowerCase();
                                if (role == 'caregiver' || role == 'receiver') {
                                  Navigator.pushReplacementNamed(context, '/HomeScreen');
                                } else {
                                  Navigator.pushReplacementNamed(context, '/profileSelect');
                                }
                                return;
                              }

                              // No current user or not verified → go to Sign In screen online
                              if (!context.mounted) return;
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
