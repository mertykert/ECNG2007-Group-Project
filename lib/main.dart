import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'features/authentication/screens/signup/signup.dart';
import 'features/authentication/screens/welcome/welcome.dart';
import 'features/authentication/screens/signin/signin.dart';
import 'features/Calendar/calendar.dart'; //importing calendar page
import 'features/role_based_account_selection/profiles/profile_selection.dart';
import 'features/Home/home_screen.dart';


// ------- Entry point of Flutter App -------
Future<void> main() async
{
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Todo: Add Widgets Binding
  // Todo: Init Local Storage
  // Todo: Await Native Splash
  // Todo: Initialize Firebase
  // Todo: Initialize Authentication
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Medi_Care",
      initialRoute: "/",
      //for testing purposes changing the initialRoute to schedule to open schedule page first
      routes: {
        "/": (context) => const WelcomeScreen(), // Default screen
        "/signup": (context) => const SignUpScreen(), // SignUp Screen
        "/signin": (context) => const SignInScreen(), // SignIn Screen
        '/profileSelect': (context) => const ProfileSelectionScreen(),
        '/HomeScreen': (context) => const HomeScreen(),
        '/schedule': (context) => const SchedulePage(),
      },
    );
  }
}
/// Automatically decides whether to show Sign In or Home
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user is logged in and verified, go to home
        if (snapshot.hasData && snapshot.data!.emailVerified) {
          return const HomeScreen();
        }

        // Otherwise, go to sign-in page
        return const SignInScreen();
      },
    );
  }
}

//Calling Calendar page
@override
Widget build(BuildContext context) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Medication Scheduler',
    theme: ThemeData(
      primarySwatch: Colors.blue,
    ),
    home: const SchedulePage(), // calling my screen
  );
}

