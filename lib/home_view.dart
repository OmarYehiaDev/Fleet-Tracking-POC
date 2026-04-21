import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ai_mobile_screen.dart';
import 'ai_web_screen.dart';
// import 'mobile/mobile_home_widget.dart';
// import 'web/web_home_widget.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: kIsWeb ? const WebScreen() : const MobileScreen(),
      // Scaffold(
      //   appBar: AppBar(
      //     backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      //     title: Text(kIsWeb ? 'Fleet Monitoring POC' : 'Fleet Tracking POC'),
      //   ),
      //   body: kIsWeb ? const WebHomeWidget() : const MobileHomeWidget(),
      // ),
    );
  }
}
