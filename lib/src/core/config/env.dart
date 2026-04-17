import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 环境变量访问器 —— 所有密钥 / 配置都从根目录的 .env 读取。
///
/// 需要在 main() 中 `await Env.load()` 后使用。
class Env {
  static const _fileName = '.env';

  static Future<void> load() => dotenv.load(fileName: _fileName);

  /// bemfa.com 的私钥 (uid)，同时充当 MQTT clientIdentifier 用于鉴权。
  static String get bemfaUid => _require('BEMFA_UID');

  /// bemfa 主题，couple 两端约定一致即可。
  static String get bemfaTopic => dotenv.env['BEMFA_TOPIC'] ?? 'desktop0001';

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        '缺少环境变量 $key。请在项目根目录的 .env 中配置，或参考 .env.example。',
      );
    }
    return value;
  }
}
