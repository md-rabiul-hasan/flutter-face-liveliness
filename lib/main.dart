import 'package:flutter/material.dart';
import 'face_liveness_detection.dart'; // Import the new file

void main() async {
  // Ensure that plugin services are initialized so that availableCameras()
  // can be called before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Liveness Detection',
      theme: ThemeData(primarySwatch: Colors.blue),
      // Set the home to a simple Scaffold that contains your widget
      home: Scaffold(
        appBar: AppBar(title: const Text('Face Liveness Detection')),
        body: FaceLivenessDetection(),
      ),
    );
  }
}
