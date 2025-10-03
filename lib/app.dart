import 'package:Medi_Care/utils/theme/theme.dart';
import 'package:flutter/material.dart';

// -- Use this Class to setup themes, initial Bindings, any animations and much
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: ThemeMode.system,
      theme: TAppTheme.lightTheme,
      darkTheme: TAppTheme.darkTheme,
    );
  }
}