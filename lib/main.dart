import 'package:flutter/material.dart';
import 'screens/library_screen.dart';

void main() => runApp(const T2SApp());

class T2SApp extends StatelessWidget {
  const T2SApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'T2S Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const LibraryScreen(),
    );
  }
}
