import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:medi_care/widgets/show_message.dart'; // import modern message helper
import 'dart:math';

import '../../../../widgets/back_button_overlay.dart';


class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agree = false;

  void _openTermsPage() {
    debugPrint("Terms & Privacy tapped");
  }

  String _generatePartnerCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _signUp() async {
    FocusScope.of(context).unfocus();

    if (_formKey.currentState!.validate()) {
      if (!_agree) {
        await showMessage(
          context,
          message: 'You must agree to the Terms & Privacy Policy',
          icon: Icons.warning_amber_rounded,
          color: Colors.orangeAccent,
        );
        return;
      }

      await showMessage(
        context,
        message: 'Creating account...',
        icon: Icons.person_add_alt_1_rounded,
        color: Colors.blueAccent,
      );

      String partnerCode = ''; //  Declare once here

      try {
        //  Create Firebase Auth account
        UserCredential userCredential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        User? user = userCredential.user;

        if (user != null) {
          await user.sendEmailVerification();

          //  Generate unique partner code
          partnerCode = _generatePartnerCode();

          //  Save to Firestore
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'name': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'partnerCode': partnerCode,
            'linkedPartner': null,
            'createdAt': FieldValue.serverTimestamp(),
          });

          if (!context.mounted) return;

          await showMessage(
            context,
            message: 'Account created! Verify your email before signing in.',
            icon: Icons.mark_email_read_outlined,
            color: Colors.greenAccent,
          );

          //  Show dialog with partner code
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text(
                "Your Partner Code",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2d59f0),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Share this code with your partner to link accounts:",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2d59f0).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      partnerCode,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Color(0xFF2d59f0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Ask your caregiver or care receiver to enter this code on their home screen.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: partnerCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Partner code copied to clipboard"),
                        backgroundColor: Color(0xFF2d59f0),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, color: Color(0xFF2d59f0)),
                  label: const Text(
                    "Copy Code",
                    style: TextStyle(
                      color: Color(0xFF2d59f0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/profileSelect');
                  },
                  child: const Text(
                    "Continue",
                    style: TextStyle(
                      color: Color(0xFF2d59f0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      } on FirebaseAuthException catch (e) {
        if (!context.mounted) return;

        String message;
        switch (e.code) {
          case 'email-already-in-use':
            message = 'This email is already registered.';
            break;
          case 'invalid-email':
            message = 'Invalid email format.';
            break;
          case 'weak-password':
            message = 'Password too weak.';
            break;
          case 'network-request-failed':
            message = 'No internet connection.';
            break;
          default:
            message = 'Sign-up failed. Please try again.';
        }

        await showMessage(
          context,
          message: message,
          icon: Icons.error_outline,
          color: Colors.redAccent,
        );
      } catch (e) {
        if (!context.mounted) return;
        await showMessage(
          context,
          message: 'Unexpected error: $e',
          icon: Icons.error_outline,
          color: Colors.redAccent,
        );
      }
    } else {
      await showMessage(
        context,
        message: 'Please fill out all required fields',
        icon: Icons.info_outline,
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
          // Top gradient image
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

          // Bottom gradient image
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

          // Scrollable form content
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
                  "Create your account",
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Start your journey with us",
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 30),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: "Full Name",
                          prefixIcon: const Icon(Icons.person_outline),
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
                        value == null || value.isEmpty ? "Enter your name" : null,
                      ),
                      const SizedBox(height: 20),

                      // Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Email Address",
                          prefixIcon: const Icon(Icons.email_outlined),
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
                        value == null || value.isEmpty ? "Enter your email" : null,
                      ),
                      const SizedBox(height: 10),

                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
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
                        value == null || value.isEmpty ? "Enter your password" : null,
                      ),
                      const SizedBox(height: 20),

                      // Confirm Password
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: "Confirm Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword = !_obscureConfirmPassword;
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
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Confirm your password";
                          } else if (value != _passwordController.text) {
                            return "Passwords do not match";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),

                      // Terms & Privacy
                      Row(
                        children: [
                          Checkbox(
                            value: _agree,
                            activeColor: const Color(0xFF2d59f0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _agree = value ?? false;
                              });
                            },
                          ),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: "I agree to the ",
                                style: const TextStyle(fontSize: 14),
                                children: [
                                  TextSpan(
                                    text: "Terms & Privacy Policy",
                                    style: const TextStyle(
                                      color: Color(0xFF2d59f0),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = _openTermsPage,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Sign Up Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2d59f0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text("Sign Up"),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Already have account
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Already have an account? "),
                          TextButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/signin');
                            },
                            child: const Text(
                              "Sign In Here",
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
            top: MediaQuery.of(context).padding.top + 25, //
            child: const BackButtonOverlay(),
          ),
        ],
      ),
    );
  }
}
