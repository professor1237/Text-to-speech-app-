import 'package:flutter/material.dart';

// This annotation is REQUIRED so Android can start this as a separate entry point.
@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MiniPlayerOverlay(),
    ),
  );
}

class MiniPlayerOverlay extends StatelessWidget {
  const MiniPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Icon(Icons.play_arrow, color: Colors.white, size: 40),
            Text(
              'T2S Reader',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            Icon(Icons.stop, color: Colors.white, size: 40),
          ],
        ),
      ),
    );
  }
}
