import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medi_care/features/authentication/screens/onboarding_screen.dart';
import 'package:medi_care/features/authentication/screens/welcome/welcome.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Home/home_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  User? _user;
  String? _role; // 'caregiver' | 'receiver' | null

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<bool> _seenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_done') == true;
  }

  Future<void> _bootstrap() async {
    // why: allow offline boot using cached user + cached profile
    final user = FirebaseAuth.instance.currentUser;
    _user = user;

    if (user == null) {
      setState(() => _checking = false);
      return;
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    DocumentSnapshot<Map<String, dynamic>> snap;

    try {
      snap = await docRef.get(const GetOptions(source: Source.cache));
      if (!snap.exists) {
        snap = await docRef.get(const GetOptions(source: Source.server));
      }
    } catch (_) {
      // fallback to cache only
      try {
        snap = await docRef.get(const GetOptions(source: Source.cache));
      } catch (_) {
        setState(() => _checking = false);
        return;
      }
    }

    _role = snap.data()?['role'] as String?;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _seenOnboarding(),
      builder: (context, snap) {
        if (!snap.hasData) {
          // keep your splash/loader to avoid UI flash
          return const SizedBox.shrink();
        }
        // If not seen → show onboarding screen first time only
        if (snap.data == false) {
          return const OnBoardingScreen();
        }

        if (_checking) {
          return const Scaffold(
            backgroundColor: Color(0xFF2d59f0),
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        if (_user == null) return const WelcomeScreen();

        // Signed in:
        // If role not set (new signup) → go pick role once. We reuse Home to push there.
        if (_role == null || (_role != 'caregiver' && _role != 'receiver')) {
          // Defer routing decision to HomeScreen; it already knows how to navigate.
          return const HomeScreen();
        }

        return const HomeScreen();
      },
    );
  }
}