import 'package:flutter/material.dart';

import 'ui/app_shell.dart';
import 'ui/theme.dart';

/// Racine de l'application Carabin.
class CarabinApp extends StatelessWidget {
  const CarabinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carabin',
      debugShowCheckedModeBanner: false,
      theme: CarabinTheme.light(),
      darkTheme: CarabinTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}
