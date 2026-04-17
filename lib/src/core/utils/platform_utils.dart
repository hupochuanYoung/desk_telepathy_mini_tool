import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

bool get isMobile => Platform.isIOS || Platform.isAndroid;

/// 设备唯一标识，格式: "mac:MacBook Pro" / "win:DESKTOP-ABC" / "ios:iPhone 15"
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
    _cached = name;
    return name;
  }
}
