import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'asset_library.dart';
import 'draw_screen.dart';
import 'home_screen.dart';
import 'mascot.dart';
import 'sound_manager.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Landscape only. A drawing is wider than it is tall, the tool column
  // needs the width, and a tablet propped on a table is landscape anyway
  // — letting it rotate would mean a second layout that is worse at
  // everything.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const KidsDreamLandApp());
}

class KidsDreamLandApp extends StatelessWidget {
  const KidsDreamLandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'King Kids Dream Land',
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      home: const _Boot(),
    );
  }
}

/// Loads the art and warms the audio players before the menu appears.
///
/// Both are fast, but the first tap on a category tile is the first thing
/// anyone does, and it should not be the tap that pays for parsing ten
/// drawings.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<AssetLibrary> _loading = _start();

  Future<AssetLibrary> _start() async {
    final library = await AssetLibrary.load();
    // Audio is best-effort: a device that cannot play sound still gets a
    // drawing app.
    await SoundManager.instance.init();
    return library;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetLibrary>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // The only thing that reaches here is a broken bundled asset,
          // which is a build problem rather than something a child can
          // cause — but it must not be a grey crash screen.
          return const Scaffold(
            body: Center(
              child: Mascot(size: 200, mood: MascotMood.watching),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: Mascot(size: 200)),
          );
        }
        return ImmersiveScope(child: HomeScreen(library: snapshot.data!));
      },
    );
  }
}
