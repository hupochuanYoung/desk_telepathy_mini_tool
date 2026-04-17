import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

bool get isMobile => Platform.isIOS || Platform.isAndroid;

/// 设备唯一标识，格式: "mac:MacBook Pro" / "win:DESKTOP-ABC" / "ios:iPhone 15"
///
/// 结果一定是 ASCII 可打印字符 —— mqtt_client 包不支持扩展 UTF，
/// 而系统返回的机器名常含智能引号 (’) 或中文，会直接导致
/// `MQTTEncoding: The input string has extended UTF characters` 连接失败。
class DeviceId {
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
    _cached = _toAscii(name);
    return _cached!;
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
