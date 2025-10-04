import 'package:Medi_Care/utils/constants/colors.dart';
import 'package:Medi_Care/utils/theme/theme.dart';
import 'package:Medi_Care/features/authentication/screens/welcome/welcome.dart';
import 'package:Medi_Care/features/authentication/screens/signup/signup.dart';
import 'package:flutter/material.dart';
import 'app.dart';

// ------- Entry point of Flutter App -------
void main()
{
  WidgetsFlutterBinding.ensureInitialized();
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
      routes: {
        "/": (context) => const WelcomeScreen(), // Default screen
        "/signup": (context) => const SignUpScreen(), // SignUp Screen
        // You can add "/signin": (context) => const SignInScreen() later
      },
    );
  }
}
