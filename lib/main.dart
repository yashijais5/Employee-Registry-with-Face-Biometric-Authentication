import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/ml_service.dart';

void main() async {
  // Ensure Flutter framework binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive Local Database
  await DatabaseService.init();

  // Initialize and Pre-load ML Models (ML Kit Face Detector and FaceNet TFLite)
  await MLService.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Employee Registry',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo,
          secondary: Colors.indigoAccent,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}
