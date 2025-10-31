import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medi_care/widgets/back_button_overlay.dart';
import 'package:medi_care/widgets/show_message.dart'; //  import modern toast helper
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../analytics/analytics_service.dart';


class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  Future<bool> _hasNetwork() async {
    final r = await Connectivity().checkConnectivity();
    return r.contains(ConnectivityResult.mobile) || r.contains(ConnectivityResult.wifi);
  }

  Future<bool> _hasOfflineSession() async {
    final prefs = await SharedPreferences.getInstance();
    final wasLoggedInOnce = prefs.getBool('isLoggedInOnce') ?? false;
    return FirebaseAuth.instance.currentUser != null && wasLoggedInOnce;
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    await showMessage(
      context,
      message: "Signing in...",
      icon: Icons.login_rounded,
      color: Colors.blueAccent,
    );

    final online = await _hasNetwork();

    // =========================
    // OFFLINE PATH (no network)
    // =========================
    if (!online) {
      if (await _hasOfflineSession()) {
        // Do NOT call reload() or any online calls here.
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/HomeScreen');
      } else {
        await showMessage(
          context,
          message: "No offline session found. Connect to the internet to sign in once.",
          icon: Icons.offline_bolt_rounded,
          color: Colors.orangeAccent,
        );
      }
      return;
    }

    // =========================
    // ONLINE PATH
    // =========================
    try {
      // Sign in the user
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final currentUser = cred.user;

      // Email verification (only enforce online)
      if (currentUser != null && !currentUser.emailVerified) {
        await FirebaseAuth.instance.signOut();
        await showMessage(
          context,
          message: "Please verify your email before logging in.",
          icon: Icons.warning_amber_rounded,
          color: Colors.orangeAccent,
        );
        return;
      }

      // Fetch role (server+cache so it works even if network hiccups now)
      String? role;
      if (currentUser != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get(const GetOptions(source: Source.serverAndCache));
        role = (doc.data()?['role'] as String?)?.toLowerCase();
      }

      // Navigate
      if (!mounted) return;
      if (role == 'caregiver' || role == 'receiver') {
        Navigator.pushReplacementNamed(context, '/HomeScreen');
      } else {
        Navigator.pushReplacementNamed(context, '/profileSelect');
      }

      // Success toast
      await showMessage(
        context,
        message: "Login successful!",
        icon: Icons.check_circle_outline,
        color: Colors.greenAccent,
      );

      // Analytics (online)
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      final roleForAnalytics = (snap.data()?['role'] as String?)?.toLowerCase();
      await AppAnalytics.identifyUser(uid: uid, role: roleForAnalytics);
      await AppAnalytics.logSignIn(method: 'password');

      // Mark that the device has logged in at least once (enables offline open)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedInOnce', true);

    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found for this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          message = 'Invalid email format.';
          break;
        case 'network-request-failed':
          message = 'Network error. Check your connection and try again.';
          break;
        default:
          message = 'Login failed. Please try again.';
      }
      await showMessage(
        context,
        message: message,
        icon: Icons.error_outline,
        color: Colors.redAccent,
      );
    } catch (e) {
      await showMessage(
        context,
        message: "Unexpected error: $e",
        icon: Icons.error_outline,
        color: Colors.redAccent,
      );
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      await showMessage(
        context,
        message: "Please enter your email first.",
        icon: Icons.info_outline,
        color: Colors.redAccent,
      );
      return;
    }

    await showMessage(
      context,
      message: "Sending password reset email...",
      icon: Icons.email_outlined,
      color: Colors.blueAccent,
    );

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!context.mounted) return;

      await showMessage(
        context,
        message: "Password reset email sent to $email",
        icon: Icons.mark_email_read_outlined,
        color: Colors.greenAccent,
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      String message;

      switch (e.code) {
        case 'user-not-found':
          message = 'No account found for that email.';
          break;
        case 'invalid-email':
          message = 'Invalid email format.';
          break;
        case 'network-request-failed':
          message = 'No internet connection.';
          break;
        default:
          message = 'Error sending reset email.';
      }

      await showMessage(
        context,
        message: message,
        icon: Icons.error_outline,
        color: Colors.redAccent,
      );
    } catch (e) {
      await showMessage(
        context,
        message: "Unexpected error: $e",
        icon: Icons.error_outline,
        color: Colors.redAccent,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              "assets/images/topblue.png",
              fit: BoxFit.cover,
              height: size.height * 0.25,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              "assets/images/bottomblue.png",
              fit: BoxFit.cover,
              height: size.height * 0.15,
            ),
          ),

          // Main form
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Image.asset(
                    "assets/images/medcross.png",
                    width: 60,
                    height: 60,
                  ),
                ),
                const SizedBox(height: 40),

                const Text(
                  "Welcome Back",
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Login to continue your journey",
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 80),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Email Address",
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          // Border when NOT focused
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.grey, // <- normal border color
                              width: 1.0,
                            ),
                          ),

                          // Border when FOCUSED
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Color(0xFF2d59f0), // <- focused border color
                              width: 2.0,
                            ),
                          ),
                        ),
                        validator: (value) =>
                        value!.isEmpty ? "Enter your email" : null,
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          //  Border when NOT focused
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Colors.grey, // <- normal border color
                              width: 1.0,
                            ),
                          ),

                          //  Border when FOCUSED
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Color(0xFF2d59f0), // <- focused border color
                              width: 2.0,
                            ),
                          ),
                        ),
                        validator: (value) =>
                        value!.isEmpty ? "Enter your password" : null,
                      ),
                      const SizedBox(height: 10),

                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: const Text(
                            "Forgot Password?",
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 150),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2d59f0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text("Sign In"),
                        ),
                      ),
                      const SizedBox(height: 40),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? "),
                          TextButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/signup');
                            },
                            child: const Text(
                              "Sign Up Here",
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: size.height * 0.25),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            // push it below the status bar + your extra offset
            top: MediaQuery.of(context).padding.top + 25, // <- tweak 56–96 to taste
            child: const BackButtonOverlay(),
          ),
        ],
      ),
    );
  }
}
