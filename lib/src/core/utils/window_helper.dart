import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../config/window_size.dart';

/// 窗口尺寸 / 位置辅助方法
class WindowHelper {
  /// 把窗口尺寸改为 [size]，并保持贴着屏幕右下角
  static Future<void> resizeAnchoredBottomRight(Size size) async {
    await windowManager.setSize(size, animate: true);
    await anchorBottomRight(size);
  }

  /// 把给定尺寸的窗口贴到主屏幕右下角（考虑 Dock / 任务栏留白）
  static Future<void> anchorBottomRight(Size size) async {
    final display = PlatformDispatcher.instance.displays.first;
    final screenSize = display.size / display.devicePixelRatio;
    final x = screenSize.width - size.width - WindowSize.margin;
    final y = screenSize.height - size.height - WindowSize.margin - WindowSize.bottomInset;
    await windowManager.setPosition(Offset(x, y), animate: true);
  }
}
