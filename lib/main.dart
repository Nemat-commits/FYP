import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/app_config.dart';
import 'ui/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.initializeMapbox();
  runApp(const ProviderScope(child: TerrastepApp()));
}

class TerrastepApp extends StatefulWidget {
  const TerrastepApp({super.key});

  @override
  State<TerrastepApp> createState() => _TerrastepAppState();
}

class _TerrastepAppState extends State<TerrastepApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terrastep 30% Milestone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF059669),
        brightness: Brightness.dark,
      ),
      home: const HomeShell(),
    );
  }
}
