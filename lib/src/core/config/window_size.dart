import 'package:flutter/material.dart';

/// 桌面 frameless 窗口的两种形态：
/// - pet: 常态的小挂件（300×380），停靠在屏幕右下角；
///        尺寸要足够大，容纳"莫尔干涉盘 + 动物跨屏飞行空间 + 花瓶 5 槽"
/// - tool: 展开后的工具抽屉（420×580），用于查看日志 / 位置 / 设置
class WindowSize {
  static const Size pet = Size(300, 380);
  static const Size tool = Size(420, 580);

  /// 贴边留白：距离屏幕右下角
  static const double margin = 20.0;

  /// macOS Dock / Windows 任务栏预留
  static const double bottomInset = 70.0;
}
