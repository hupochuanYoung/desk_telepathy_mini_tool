import 'package:desk_telepathy/src/core/config/env.dart';
import 'package:desk_telepathy/src/core/config/window_size.dart';
import 'package:desk_telepathy/src/core/utils/platform_utils.dart';
import 'package:desk_telepathy/src/core/utils/window_helper.dart';
import 'package:desk_telepathy/src/feature/home/presentation/screen/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();

  if (isDesktop) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: WindowSize.pet,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(Colors.transparent);
      await WindowHelper.anchorBottomRight(WindowSize.pet);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const DeskTelepathyApp());
}

class DeskTelepathyApp extends StatelessWidget {
  const DeskTelepathyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pinkAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
