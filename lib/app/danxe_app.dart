import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../features/player/player_screen.dart';

class DanxeApp extends StatelessWidget {
  const DanxeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Danxe',
      debugShowCheckedModeBanner: false,
      theme: DanxeTheme.dark(),
      home: const PlayerScreen(),
    );
  }
}

