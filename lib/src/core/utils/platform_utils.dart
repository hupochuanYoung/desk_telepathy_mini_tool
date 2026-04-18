import 'dart:io' show Platform;
import 'dart:math' show Random;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

bool get isMobile => Platform.isIOS || Platform.isAndroid;

/// 设备唯一标识，格式: `"mac:MacBook Pro#a9k2x7qs"` 之类。
///
/// 组成：
///   1. 平台前缀 + 机器名（人类可读，方便在日志里区分）
///   2. `#` + 一段持久化在 SharedPreferences 里的 8 字符随机串
///
/// 为什么要带 #xxx —— 两台同型号电脑（比如都叫 DESKTOP-XXXX）或者同一台
/// 机器上跑两个调试实例，机器名完全一样的话 from 字段相同，MQTT 侧的
/// "过滤掉自己发的消息" 就会误伤 / 漏伤。加上一段与安装绑定的随机后缀，
/// 保证 from 在每个安装实例里都是独一份。
///
/// 结果一定是 ASCII 可打印字符 —— mqtt_client 包不支持扩展 UTF，
/// 而系统返回的机器名常含智能引号 (’) 或中文，会直接导致
/// `MQTTEncoding: The input string has extended UTF characters` 连接失败。
class DeviceId {
  static const _prefsKey = 'device_instance_id';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    final info = DeviceInfoPlugin();
    String name;
    if (Platform.isMacOS) {
      final mac = await info.macOsInfo;
      name = 'mac:${mac.computerName}';
    } else if (Platform.isWindows) {
      final win = await info.windowsInfo;
      name = 'win:${win.computerName}';
    } else if (Platform.isLinux) {
      final linux = await info.linuxInfo;
      name = 'linux:${linux.prettyName}';
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      name = 'ios:${ios.name}';
    } else if (Platform.isAndroid) {
      final android = await info.androidInfo;
      name = 'android:${android.model}';
    } else {
      name = 'unknown';
    }
    final suffix = await _instanceSuffix();
    _cached = '${_toAscii(name)}#$suffix';
    return _cached!;
  }

  static Future<String> _instanceSuffix() async {
    final prefs = await SharedPreferences.getInstance();
    var s = prefs.getString(_prefsKey);
    if (s != null && s.isNotEmpty) return s;
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    s = List.generate(8, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
    await prefs.setString(_prefsKey, s);
    return s;
  }

  /// 先把常见的智能标点换成 ASCII 近似，再去掉所有非 ASCII 字符。
  /// 如果清理后字符串为空（例如全中文），回退到 `device-{hash}`，
  /// 保证始终返回一个稳定、可在 MQTT 传输的标识。
  static String _toAscii(String raw) {
    const smartToPlain = {
      '\u2018': "'", '\u2019': "'", // ‘ ’
      '\u201C': '"', '\u201D': '"', // “ ”
      '\u2013': '-', '\u2014': '-', // – —
      '\u00A0': ' ', // nbsp
    };
    var s = raw;
    smartToPlain.forEach((k, v) => s = s.replaceAll(k, v));
    // 仅保留可打印 ASCII
    s = s.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    if (s.isEmpty || s == ':') {
      s = 'device-${raw.hashCode.toUnsigned(32).toRadixString(16)}';
    }
    return s;
  }
}
