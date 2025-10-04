
import 'package:flutter/material.dart';
import 'package:medi_care/features/authentication/screens/login/login.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medi Care',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginScreen(), // Directly show login after native splash
      debugShowCheckedModeBanner: false,
    );
  }
}