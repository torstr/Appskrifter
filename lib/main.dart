import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'screens/app_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: AppskrifterApp()));
}

class AppskrifterApp extends StatelessWidget {
  const AppskrifterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Appskrifter',
      debugShowCheckedModeBanner: false,
      locale: const Locale('nb', 'NO'),
      supportedLocales: const [Locale('nb', 'NO')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green.shade700),
        useMaterial3: true,
      ),
      home: const AppGate(),
    );
  }
}
