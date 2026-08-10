import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const ISONowApp());
}

class ISONowApp extends StatelessWidget {
  const ISONowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ISONow',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginScreen(),
    );
  }
}