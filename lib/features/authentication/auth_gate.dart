import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medi_care/features/authentication/screens/welcome/welcome.dart';

import '../Home/home_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  User? _user;

  @override
  void initState() {
    super.initState();
    _checkLocalUser();
  }

  Future<void> _checkLocalUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      // Check that the account still exists and is verified
      if (refreshedUser != null && refreshedUser.emailVerified) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(refreshedUser.uid)
            .get();

        if (doc.exists) {
          setState(() {
            _user = refreshedUser;
          });
        } else {
          // account deleted or missing
          await FirebaseAuth.instance.signOut();
        }
      } else {
        // not verified or invalid
        await FirebaseAuth.instance.signOut();
      }
    }

    setState(() {
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF2d59f0),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_user != null) {
      return const HomeScreen();
    } else {
      return const WelcomeScreen();
    }
  }
}
