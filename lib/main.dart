import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: TerrastepApp()));
}

class TerrastepApp extends StatelessWidget {
  const TerrastepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terrastep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
      ),
      home: const HomeShell(),
    );
  }
}
