import 'package:flutter/material.dart';
import 'app.dart';
import 'features/authentication/screens/signup/signup.dart';
import 'features/authentication/screens/welcome/welcome.dart';
import 'features/authentication/screens/signin/signin.dart';


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
        "/signin": (context) => const SignInScreen() // SignIn Screen
      },
    );
  }
}
