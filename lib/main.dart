import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_version.dart';
import 'firebase_options.dart';
import 'home_view.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppVersion.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kIsWeb ? 'Fleet Monitoring POC' : 'Fleet Tracking POC',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.amber, brightness: Brightness.dark),
        textTheme: TextTheme.of(context).apply(fontFamily: 'monospace'),
      ),
      home: HomeView(),
    );
  }
}
