/// Standalone entry point for the data-layer debug screen:
/// `flutter run -t lib/main_debug.dart` (any platform, including `-d chrome`).
library;

import 'package:flutter/material.dart';

import 'data/bootstrap.dart';
import 'ui/debug/debug_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DebugApp());
}

class DebugApp extends StatefulWidget {
  const DebugApp({super.key});
  @override
  State<DebugApp> createState() => _DebugAppState();
}

class _DebugAppState extends State<DebugApp> {
  final Future<AppData> _app = openAppData();

  @override
  void dispose() {
    _app.then((a) => a.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tosk data debug',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: FutureBuilder<AppData>(
        future: _app,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(body: Center(child: Text('Failed to open data: ${snap.error}')));
          }
          if (!snap.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return DebugScreen(app: snap.data!);
        },
      ),
    );
  }
}
