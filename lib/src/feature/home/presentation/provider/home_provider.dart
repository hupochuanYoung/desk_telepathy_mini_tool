import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/config/env.dart';
import '../../../../core/service/interaction_store.dart';
import '../../../../core/service/location_service.dart';
import '../../../../core/service/mqtt_service.dart';
import '../../../../core/service/app_logger.dart';
import '../widgets/flower_bloom.dart';
import '../widgets/particle_background.dart';
import '../widgets/status_indicator.dart';

const _presenceTag = 'Presence';

/// 丢花互动：每种互动对应一种花，点击即向对方"丢"一朵过去
enum TelepathyAction {
  tulip('tulip', '丢郁金香', FlowerKind.tulip, ParticleType.hearts),
  daisy('daisy', '丢雏菊', FlowerKind.daisy, ParticleType.stars),
  lily('lily', '丢百合', FlowerKind.lily, ParticleType.firefly),
  rose('rose', '丢玫瑰', FlowerKind.rose, ParticleType.hearts),
  sunflower('sunflower', '丢向日葵', FlowerKind.sunflower, ParticleType.firefly);

  final String code;
  final String label;
  final FlowerKind flower;
  final ParticleType particle;

  const TelepathyAction(this.code, this.label, this.flower, this.particle);

  Color get color => flower.accent;

  static TelepathyAction? fromCode(String code) {
    try {
      return TelepathyAction.values.firstWhere((a) => a.code == code);
    } catch (_) {
      return null;
    }
  }
}

/// 一次"收到对方互动"的事件 —— Provider 只负责通知 UI，
/// 播动画 / 在花园里抽一朵花的细节仍留给 HomeScreen 这种 TickerProvider 宿主完成。
class ReceivedActionEvent {
  final TelepathyAction action;
  final int seq;
  const ReceivedActionEvent(this.action, this.seq);
}

/// 应用的主状态中心：
/// * MQTT 连接、位置拉取、互动统计这些"会话级"状态都集中在这里，
///   避免 HomeScreen 自己 StatefulWidget 重建时丢失（切换 pet/tool 模式、切宽高都可能触发）。
/// * 动画相关（粒子/水滴波纹/横幅淡入）和窗口控制（置顶/拖拽）依旧留在 Widget 内部。
class HomeProvider extends ChangeNotifier {
  HomeProvider();

  // ───────── 服务 ─────────
  late final MqttService _mqtt = MqttService(uid: Env.bemfaUid, topic: Env.bemfaTopic);
  final InteractionStore _store = InteractionStore();

  MqttService get mqtt => _mqtt;

  InteractionStore get store => _store;

  StreamSubscription<TelepathyMessage>? _msgSub;

  // ───────── 连接 / 状态 ─────────
  bool _connected = false;

  bool get connected => _connected;

  /// 自己刚刚连上 MQTT 的时间。3 秒内收到的 retained 状态当作"冷启动快照"，
  /// 不触发欢迎横幅，避免一开机就刷屏。
  DateTime? _connectedSince;

  DateTime? get connectedSince => _connectedSince;

  PeerStatus _myStatus = PeerStatus.online;

  PeerStatus get myStatus => _myStatus;

  PeerStatus _peerStatus = PeerStatus.offline;

  PeerStatus get peerStatus => _peerStatus;

  // ───────── 位置 ─────────
  LocationInfo? _myLocation;

  LocationInfo? get myLocation => _myLocation;

  LocationInfo? _peerLocation;

  LocationInfo? get peerLocation => _peerLocation;

  /// 中心地球当前聚焦到的经纬度 —— 跟随最近一次互动。
  /// null 时球只是安静地自转，不显示干涉纹。
  LocationInfo? _focalLocation;

  LocationInfo? get focalLocation => _focalLocation;

  Timer? _peerLocationTimer;
  static const Duration _peerLocTimeout = Duration(seconds: 6);

  // ───────── 互动视觉 ─────────
  double _heatIntensity = 0.0;

  double get heatIntensity => _heatIntensity;

  ParticleType _bgParticle = ParticleType.stars;

  ParticleType get bgParticle => _bgParticle;

  Color _bgParticleColor = Colors.white;

  Color get bgParticleColor => _bgParticleColor;

  /// 上线欢迎横幅文本，null 表示不显示
  String? _greeting;

  String? get greeting => _greeting;

  Timer? _greetingTimer;

  // ───────── 回声 / 对方活跃度事件 ─────────

  /// 自己刚刚发出去的 action code → 发出时间。用来把 broker 偶发的原样回放吞掉。
  final Map<String, DateTime> _recentSelfSends = {};
  static const _selfEchoWindow = Duration(seconds: 4);

  /// 对外事件流：有对方的互动到达时，HomeScreen 据此播动画、抽花。
  final _receivedActionController = StreamController<ReceivedActionEvent>.broadcast();

  Stream<ReceivedActionEvent> get onReceivedAction => _receivedActionController.stream;

  /// 对外事件流：对方任何消息（action/status/…）到达时 fire 一次，
  /// HomeScreen 用来"拉满活跃度"驱动莫尔条纹。
  final _peerBumpController = StreamController<void>.broadcast();

  Stream<void> get onPeerActivityBump => _peerBumpController.stream;

  int _receivedSeq = 0;

  // ───────── 生命周期 ─────────

  bool _disposed = false;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _store.init();
    _heatIntensity = _store.intensity;
    _safeNotify();
    unawaited(_fetchLocation());
    await _connectMqtt();
  }

  Future<void> _fetchLocation() async {
    final info = await LocationService.fetch();
    if (info == null) {
      _safeNotify();
      return;
    }
    _myLocation = info;
    // 首次拿到自己的坐标时给地球一个默认焦点，避免它一直对着 (0,0)
    _focalLocation ??= info;
    _safeNotify();
  }

  Future<void> _connectMqtt() async {
    final ok = await _mqtt.connect();
    if (ok) _connectedSince = DateTime.now();
    _connected = ok;
    if (ok) _sendHelloFlowOnConnect();
    _safeNotify();
    _msgSub = _mqtt.messages.listen(_handleMessage);
  }

  void _handleMessage(TelepathyMessage msg) {
    // 先判回声 —— 自己刚发的 action 被 broker 回放，静默吞掉
    if (msg.type == MsgType.action && _isSelfEcho(msg.data)) return;

    // 对方只要来了任何一条消息，都拉满活跃度
    if (!_peerBumpController.isClosed) _peerBumpController.add(null);

    switch (msg.type) {
      case MsgType.action:
        final action = TelepathyAction.fromCode(msg.data);
        if (action != null) {
          _store.recordReceived(action.code);
          _heatIntensity = _store.intensity;
          _bgParticle = action.particle;
          _bgParticleColor = action.color;
          // 收到对方动作 → 把地球转到 TA 那里
          if (_peerLocation != null) _focalLocation = _peerLocation;
          _receivedSeq++;
          if (!_receivedActionController.isClosed) {
            _receivedActionController.add(ReceivedActionEvent(action, _receivedSeq));
          }
          _safeNotify();
          // 3s 后把背景粒子还原回默认
          Timer(const Duration(seconds: 3), () {
            _bgParticle = ParticleType.stars;
            _bgParticleColor = Colors.white;
            _safeNotify();
          });
        }
      case MsgType.status:
        final next = PeerStatus.fromCode(msg.data);
        final wasOffline = _peerStatus == PeerStatus.offline;
        _peerStatus = next;
        _onPeerStatusChanged(wasOffline: wasOffline, next: next);
        _safeNotify();
      case MsgType.ambient:
        _applyAmbient(msg.data);
      case MsgType.hello:
        final wasOffline = _peerStatus == PeerStatus.offline;
        AppLogger.d(_presenceTag, '收到 hello: ${msg.data}');
        if (wasOffline) {
          _peerStatus = PeerStatus.online;
          _onPeerStatusChanged(wasOffline: true, next: PeerStatus.online);
          _safeNotify();
        }
        // 对方 hello 后立即回传自己的当前状态 + 位置（不发花，避免互相连锁刷屏）
        _replyMyPresence();
      case MsgType.location:
        final loc = LocationInfo.decode(msg.data);
        if (loc != null) {
          _peerLocation = loc;
          _peerLocationTimer?.cancel();
          AppLogger.i('Location', '收到对方位置: ${loc.display}');
          _safeNotify();
        } else {
          AppLogger.w('Location', '收到 location 但解析失败: ${msg.data}');
        }
      case MsgType.vase:
        break;
    }
  }

  void _onPeerStatusChanged({required bool wasOffline, required PeerStatus next}) {
    if (next == PeerStatus.offline) {
      // 对方离线 —— 位置缓存作废，loading 也停掉
      _peerLocation = null;
      _peerLocationTimer?.cancel();
      return;
    }

    // 刚变成在线：若还没有位置，开一个有限时长的"定位中"窗口
    if (_peerLocation == null) {
      _peerLocationTimer?.cancel();
      _peerLocationTimer = Timer(_peerLocTimeout, () {
        if (_peerLocation == null) {
          AppLogger.w('Location', '对方 ${_peerLocTimeout.inSeconds}s 内未发送位置，停止等待');
          _safeNotify();
        }
      });
    }

    if (wasOffline) _showPeerOnlineGreeting();
  }

  /// 本端连上 MQTT（首次 / 自动重连）后的固定握手：
  /// - 发 hello
  /// - 发自己当前 status
  /// - 发自己位置（若已拿到）
  /// - 主动送一朵雏菊（即使对方当下不在线，broker 也会正常处理当前消息）
  void _sendHelloFlowOnConnect() {
    if (!_connected) return;
    _mqtt.send(TelepathyMessage(type: MsgType.hello, data: 'hi'));
    _mqtt.sendStatus(_myStatus.name);
    final mine = _myLocation;
    if (mine != null) _mqtt.sendLocation(mine.encode());
    _mqtt.sendAction(TelepathyAction.daisy.code);
    _store.recordSent(TelepathyAction.daisy.code);
    _markSelfSend(TelepathyAction.daisy.code);
  }

  /// 响应对方 hello：回传我当前状态和位置，不发 action，避免双端回声升级。
  void _replyMyPresence() {
    if (!_connected) return;
    _mqtt.sendStatus(_myStatus.name);
    final mine = _myLocation;
    if (mine != null) {
      _mqtt.sendLocation(mine.encode());
    } else {
      AppLogger.w('Location', '回复 hello 时本端位置为空，稍后拿到位置会自动补发');
    }
  }

  /// 对方从离线切到在线时，仅做 UI 提示，不再承担网络握手职责。
  void _showPeerOnlineGreeting() {
    final since = _connectedSince;
    final isColdStart =
        since != null && DateTime.now().difference(since).inMilliseconds < 3000;
    if (isColdStart) return;

    const greetings = [
      'TA 上线啦',
      '对面的人来啦',
      '收到心跳，接上线了',
      'TA 回来了，点一朵花说声嗨',
    ];
    final text = greetings[math.Random().nextInt(greetings.length)];
    _greetingTimer?.cancel();
    _greeting = text;
    _safeNotify();
    _greetingTimer = Timer(const Duration(seconds: 4), () {
      _greeting = null;
      _safeNotify();
    });
  }

  void _applyAmbient(String data) {
    switch (data) {
      case 'snow':
        _bgParticle = ParticleType.snow;
        _bgParticleColor = Colors.lightBlueAccent;
      case 'warm':
        _bgParticle = ParticleType.firefly;
        _bgParticleColor = Colors.amber;
      case 'night':
        _bgParticle = ParticleType.stars;
        _bgParticleColor = Colors.white;
      default:
        _bgParticle = ParticleType.stars;
        _bgParticleColor = Colors.white;
    }
    _safeNotify();
  }

  // ───────── 外部操作 ─────────

  bool _cooldown = false;

  bool get cooldown => _cooldown;

  void sendAction(TelepathyAction action) {
    if (_cooldown || !_connected) return;
    _mqtt.sendAction(action.code);
    _store.recordSent(action.code);
    _markSelfSend(action.code);
    _cooldown = true;
    _heatIntensity = _store.intensity;
    _safeNotify();
    Timer(const Duration(milliseconds: 800), () {
      _cooldown = false;
      _safeNotify();
    });
  }

  void cycleMyStatus() {
    const statuses = [PeerStatus.online, PeerStatus.busy, PeerStatus.focus];
    final idx = statuses.indexOf(_myStatus);
    final next = statuses[(idx + 1) % statuses.length];
    _myStatus = next;
    _safeNotify();
    _mqtt.sendStatus(next.name);
  }

  /// 用户手势转动了地球 —— 释放焦点，让球跟随手指而不是被自动回到某个城市
  void clearFocalForManualRotation() {
    if (_focalLocation == null) return;
    _focalLocation = null;
    _safeNotify();
  }

  // ───────── 回声帮手 ─────────
  void _markSelfSend(String code) {
    final now = DateTime.now();
    _recentSelfSends[code] = now;
    final cutoff = now.subtract(_selfEchoWindow);
    _recentSelfSends.removeWhere((_, t) => t.isBefore(cutoff));
  }

  bool _isSelfEcho(String code) {
    final sentAt = _recentSelfSends[code];
    if (sentAt == null) return false;
    if (DateTime.now().difference(sentAt) > _selfEchoWindow) {
      _recentSelfSends.remove(code);
      return false;
    }
    _recentSelfSends.remove(code);
    return true;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _msgSub?.cancel();
    _greetingTimer?.cancel();
    _peerLocationTimer?.cancel();
    _receivedActionController.close();
    _peerBumpController.close();
    _mqtt.dispose();
    super.dispose();
  }
}
