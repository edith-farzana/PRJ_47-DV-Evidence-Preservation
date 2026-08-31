import 'package:flutter/material.dart';

import '../features/auth/presentation/pin_page.dart';
import '../features/home/home_page.dart';

class SecureEvidenceApp extends StatefulWidget {
  const SecureEvidenceApp({super.key});

  @override
  State<SecureEvidenceApp> createState() => _SecureEvidenceAppState();
}

class _SecureEvidenceAppState extends State<SecureEvidenceApp> {
  bool _unlocked = false;

  void _unlock() {
    setState(() {
      _unlocked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secure Evidence',

      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090B10),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B7BFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),

      home: _unlocked ? const HomePage() : PinPage(onSuccess: _unlock),
    );
  }
}
