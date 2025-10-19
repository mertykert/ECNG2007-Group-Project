import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';

// Screens
import 'features/authentication/screens/signup/signup.dart';
import 'features/authentication/screens/welcome/welcome.dart';
import 'features/authentication/screens/signin/signin.dart';
import 'features/Calendar/calendar.dart';
import 'features/role_based_account_selection/profiles/profile_selection.dart';
import 'features/Home/home_screen.dart';

Future<void> main() async {
  // Keep splash visible until Firebase is ready
  WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.ensureInitialized());

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  } finally {
    //  Remove splash once setup is done
    FlutterNativeSplash.remove();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Medi_Care",
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WelcomeScreen(), // Always start here
      routes: {
        "/welcome": (context) => const WelcomeScreen(),
        "/signup": (context) => const SignUpScreen(),
        "/signin": (context) => const SignInScreen(),
        "/profileSelect": (context) => const ProfileSelectionScreen(),
        "/HomeScreen": (context) => const HomeScreen(),
        "/schedule": (context) => const SchedulePage(),
      },
    );
  }
}
