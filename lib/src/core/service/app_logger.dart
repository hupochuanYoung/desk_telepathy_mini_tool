import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  const LogEntry(this.time, this.level, this.tag, this.message);

  String get formattedTime {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  String toString() => '[$formattedTime][${level.name.toUpperCase()}][$tag] $message';
}

/// 进程内日志中心：
/// - 环形缓冲，最多保留 [maxEntries] 条，避免内存膨胀
/// - 同时广播到 [stream]，UI 可订阅实时刷新
/// - debug 模式下也打到 stdout，便于 `flutter run` 观察
class AppLogger {
  static const int maxEntries = 300;

  static final Queue<LogEntry> _buffer = Queue<LogEntry>();
  static final StreamController<LogEntry> _controller = StreamController<LogEntry>.broadcast();

  static List<LogEntry> get history => List.unmodifiable(_buffer);

  static Stream<LogEntry> get stream => _controller.stream;

  static void log(LogLevel level, String tag, String message) {
    final entry = LogEntry(DateTime.now(), level, tag, message);
    _buffer.addLast(entry);
    while (_buffer.length > maxEntries) {
      _buffer.removeFirst();
    }
    if (!_controller.isClosed) _controller.add(entry);
    if (kDebugMode) {
      debugPrint(entry.toString());
    }
  }

  static void d(String tag, String message) => log(LogLevel.debug, tag, message);
  static void i(String tag, String message) => log(LogLevel.info, tag, message);
  static void w(String tag, String message) => log(LogLevel.warn, tag, message);
  static void e(String tag, String message) => log(LogLevel.error, tag, message);

  static void clear() => _buffer.clear();
}
