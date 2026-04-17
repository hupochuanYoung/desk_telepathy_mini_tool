import 'dart:ui';

import 'package:desk_telepathy/src/core/config/env.dart';
import 'package:desk_telepathy/src/core/utils/platform_utils.dart';
import 'package:desk_telepathy/src/feature/home/presentation/screen/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const _petSize = Size(220, 260);
const _margin = 20.0; // 距离屏幕边缘

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();

  if (isDesktop) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: _petSize,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(Colors.transparent);

      // 定位到屏幕右下角
      await _positionBottomRight();

      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const DeskTelepathyApp());
}

/// 把窗口放到屏幕右下角（留出任务栏/Dock 的空间）
Future<void> _positionBottomRight() async {
  // 获取主屏幕尺寸
  final screen = PlatformDispatcher.instance.displays.first;
  final screenSize = screen.size / screen.devicePixelRatio;

  final x = screenSize.width - _petSize.width - _margin;
  // macOS 的 Dock 大约 70px，Windows 任务栏大约 48px
  final y = screenSize.height - _petSize.height - _margin - 70;

  await windowManager.setPosition(Offset(x, y));
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
