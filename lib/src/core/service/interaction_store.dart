import 'package:shared_preferences/shared_preferences.dart';

/// 本地互动记录 — 互动热力图的数据基础
class InteractionStore {
  static const _keyTotalSent = 'total_sent';
  static const _keyTotalReceived = 'total_received';
  static const _keyPrefix = 'action_';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  int get totalSent => _prefs.getInt(_keyTotalSent) ?? 0;
  int get totalReceived => _prefs.getInt(_keyTotalReceived) ?? 0;
  int get totalInteractions => totalSent + totalReceived;

  /// 记录发送
  Future<void> recordSent(String action) async {
    await _prefs.setInt(_keyTotalSent, totalSent + 1);
    final key = '${_keyPrefix}sent_$action';
    await _prefs.setInt(key, (_prefs.getInt(key) ?? 0) + 1);
  }

  /// 记录接收
  Future<void> recordReceived(String action) async {
    await _prefs.setInt(_keyTotalReceived, totalReceived + 1);
    final key = '${_keyPrefix}recv_$action';
    await _prefs.setInt(key, (_prefs.getInt(key) ?? 0) + 1);
  }

  /// 获取某个动作的发送次数
  int sentCount(String action) =>
      _prefs.getInt('${_keyPrefix}sent_$action') ?? 0;

  /// 获取某个动作的接收次数
  int recvCount(String action) =>
      _prefs.getInt('${_keyPrefix}recv_$action') ?? 0;

  /// 互动强度 0.0 ~ 1.0，用于热力图渲染
  double get intensity {
    final total = totalInteractions;
    if (total == 0) return 0.0;
    // 500 次互动达到满强度
    return (total / 500).clamp(0.0, 1.0);
  }
}
