import 'dart:async';
import 'package:desk_telepathy/src/core/config/env.dart';
import 'package:desk_telepathy/src/core/config/window_size.dart';
import 'package:desk_telepathy/src/core/service/interaction_store.dart';
import 'package:desk_telepathy/src/core/service/location_service.dart';
import 'package:desk_telepathy/src/core/service/mqtt_service.dart';
import 'package:desk_telepathy/src/core/utils/platform_utils.dart';
import 'package:desk_telepathy/src/core/utils/window_helper.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/heatmap_glow.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/log_viewer.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/particle_background.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:window_manager/window_manager.dart';

/// 互动动作定义
enum TelepathyAction {
  knock('knock', '敲桌子', Icons.back_hand, Colors.orange, ParticleType.firefly),
  heart('heart', '发爱心', Icons.favorite, Colors.pinkAccent, ParticleType.hearts),
  wave('wave', '打招呼', Icons.waving_hand, Colors.amber, ParticleType.stars),
  poke('poke', '戳一下', Icons.touch_app, Colors.blueAccent, ParticleType.snow),
  hug('hug', '抱一下', Icons.self_improvement, Colors.purpleAccent, ParticleType.firefly);

  final String code;
  final String label;
  final IconData icon;
  final Color color;
  final ParticleType particle;

  const TelepathyAction(this.code, this.label, this.icon, this.color, this.particle);

  static TelepathyAction? fromCode(String code) {
    try {
      return TelepathyAction.values.firstWhere((a) => a.code == code);
    } catch (_) {
      return null;
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomePageState();
}

class _HomePageState extends State<HomeScreen> with TickerProviderStateMixin {
  final MqttService _mqtt = MqttService(uid: Env.bemfaUid, topic: Env.bemfaTopic);
  final InteractionStore _store = InteractionStore();

  StreamSubscription<TelepathyMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;
  bool _connected = false;

  // 收到的动画
  TelepathyAction? _receivedAction;
  bool _showReceived = false;

  // 粒子背景状态
  ParticleType _bgParticle = ParticleType.stars;
  Color _bgParticleColor = Colors.white;

  // 对方状态
  PeerStatus _peerStatus = PeerStatus.offline;

  // 自己的状态
  PeerStatus _myStatus = PeerStatus.online;

  // 互动强度
  double _heatIntensity = 0.0;

  // 发送冷却
  bool _cooldown = false;

  // 位置信息
  LocationInfo? _myLocation;
  LocationInfo? _peerLocation;

  // 工具抽屉（展开的设置 / 日志视图）
  bool _toolMode = false;

  // 窗口置顶状态
  bool _pinned = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _store.init();
    setState(() => _heatIntensity = _store.intensity);
    unawaited(_fetchLocation());
    await _connectMqtt();
  }

  Future<void> _fetchLocation() async {
    final info = await LocationService.fetch();
    if (info == null || !mounted) return;
    setState(() => _myLocation = info);
    // sendLocation 会先把 JSON 缓存到 MqttService._myLocation，
    // 再尝试立刻 publish；未连接时 publish 会 no-op，但后续 _onLinkUp() 会重播。
    _mqtt.sendLocation(info.encode());
  }

  Future<void> _connectMqtt() async {
    // 连接成功后，service 会自动用 _myStatus(默认 online) 做一次 retained 广播
    // + 发一条 hello，让对端回传自己的状态，详见 MqttService._onLinkUp()
    final ok = await _mqtt.connect();
    setState(() => _connected = ok);

    _connSub = _mqtt.connectionStream.listen((connected) {
      if (mounted) setState(() => _connected = connected);
    });

    _msgSub = _mqtt.messages.listen(_handleMessage);
  }

  void _handleMessage(TelepathyMessage msg) {
    switch (msg.type) {
      case MsgType.action:
        final action = TelepathyAction.fromCode(msg.data);
        if (action != null) {
          _store.recordReceived(action.code);
          _playReceivedAnimation(action);
        }
      case MsgType.status:
        if (mounted) setState(() => _peerStatus = PeerStatus.fromCode(msg.data));
      case MsgType.ambient:
        _applyAmbient(msg.data);
      case MsgType.hello:
        // service 层已自动回传自己的 status / location，这里无需额外处理；
        // 同时把对端视为在线（若还没收到他的 status 广播）
        if (mounted && _peerStatus == PeerStatus.offline) {
          setState(() => _peerStatus = PeerStatus.online);
        }
      case MsgType.location:
        final loc = LocationInfo.decode(msg.data);
        if (loc != null && mounted) setState(() => _peerLocation = loc);
    }
  }

  void _playReceivedAnimation(TelepathyAction action) {
    setState(() {
      _receivedAction = action;
      _showReceived = true;
      _bgParticle = action.particle;
      _bgParticleColor = action.color;
      _heatIntensity = _store.intensity;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showReceived = false;
          _bgParticle = ParticleType.stars;
          _bgParticleColor = Colors.white;
        });
      }
    });
  }

  void _applyAmbient(String data) {
    // 简单氛围：snow / warm / night
    setState(() {
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
    });
  }

  void _sendAction(TelepathyAction action) {
    if (_cooldown) return;
    _mqtt.sendAction(action.code);
    _store.recordSent(action.code);
    setState(() {
      _cooldown = true;
      _heatIntensity = _store.intensity;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _cooldown = false);
    });
  }

  void _cycleMyStatus() {
    final statuses = [PeerStatus.online, PeerStatus.busy, PeerStatus.focus];
    final idx = statuses.indexOf(_myStatus);
    final next = statuses[(idx + 1) % statuses.length];
    setState(() => _myStatus = next);
    _mqtt.sendStatus(next.name);
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    await windowManager.setAlwaysOnTop(next);
    if (mounted) setState(() => _pinned = next);
  }

  Future<void> _closeWindow() async {
    // 优雅退出：dispose 会把状态置为 offline 并断开连接
    await windowManager.close();
  }

  Future<void> _toggleToolMode() async {
    final next = !_toolMode;
    setState(() => _toolMode = next);
    if (isDesktop) {
      await WindowHelper.resizeAnchoredBottomRight(next ? WindowSize.tool : WindowSize.pet);
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isMobile) return _buildMobileLayout();
    return _buildDesktopFrame();
  }

  /// 桌面 frameless 工具：
  /// - 常态：220×260 的小挂件，互动主操作
  /// - 工具模式：420×520，展示日志 / 位置 / 设置
  Widget _buildDesktopFrame() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xE61A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: ParticleBackground(
                  key: ValueKey('$_bgParticle-$_toolMode'),
                  type: _bgParticle,
                  color: _bgParticleColor,
                  count: _toolMode ? 40 : 20,
                ),
              ),
              HeatmapGlow(intensity: _heatIntensity),
              _toolMode ? _buildToolBody() : _buildPetBody(),
            ],
          ),
        ),
      ),
    );
  }

  /// 小挂件形态 — 紧凑
  Widget _buildPetBody() {
    return Column(
      children: [
        _buildTitleBar(showChrome: true),
        Expanded(child: _buildBody()),
        _buildActionBar(),
        _buildStatsBar(),
      ],
    );
  }

  /// 工具抽屉形态 — 更宽裕，可以塞进设置 / 日志
  Widget _buildToolBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitleBar(showChrome: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildLocationCard(),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SizedBox(
            height: 80,
            child: Center(
              child: _showReceived && _receivedAction != null
                  ? _buildReceivedAnimation(_receivedAction!)
                  : _buildIdleState(),
            ),
          ),
        ),
        _buildActionBar(),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const LogViewer(),
          ),
        ),
        _buildStatsBar(),
      ],
    );
  }

  /// 移动端全屏布局
  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          Positioned.fill(
            child: ParticleBackground(
              key: ValueKey(_bgParticle),
              type: _bgParticle,
              color: _bgParticleColor,
              count: 25,
            ),
          ),
          HeatmapGlow(intensity: _heatIntensity),
          SafeArea(
            child: Column(
              children: [
                _buildTitleBar(showChrome: false),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildLocationCard(),
                ),
                Expanded(child: _buildBody()),
                _buildActionBar(),
                _buildStatsBar(),
              ],
            ),
          ),
          // 移动端查看日志：右上角悬浮按钮 → 底部弹层
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                icon: Icon(Icons.terminal, color: Colors.white.withValues(alpha: 0.5), size: 18),
                tooltip: '查看日志',
                onPressed: () => _showMobileLogs(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMobileLogs(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          child: const LogViewer(),
        ),
      ),
    );
  }

  Widget _buildTitleBar({required bool showChrome}) {
    final titleContent = Row(
      children: [
        GestureDetector(
          onTap: _cycleMyStatus,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _connected ? Colors.greenAccent : Colors.redAccent,
              boxShadow: _connected
                  ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.5), blurRadius: 6)]
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _toolMode ? '桌面心灵感应 · 工具' : '桌面心灵感应',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        GestureDetector(
          onTap: _cycleMyStatus,
          child: Tooltip(message: '点击切换我的状态', child: Icon(_myStatus.icon, size: 12, color: _myStatus.color)),
        ),
        const SizedBox(width: 6),
        StatusIndicator(status: _peerStatus),
        if (showChrome) ...[
          const SizedBox(width: 8),
          _ChromeBtn(
            icon: _toolMode ? Icons.close_fullscreen : Icons.open_in_full,
            tooltip: _toolMode ? '收起' : '展开工具',
            onTap: _toggleToolMode,
          ),
          if (isDesktop) ...[
            _ChromeBtn(
              icon: _pinned ? Icons.push_pin : Icons.push_pin_outlined,
              tooltip: _pinned ? '已置顶' : '取消置顶',
              active: _pinned,
              onTap: _togglePin,
            ),
            _ChromeBtn(icon: Icons.close, tooltip: '关闭', onTap: _closeWindow),
          ],
        ],
      ],
    );

    // 桌面端整条标题栏就是拖拽把手
    final bar = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: titleContent,
    );
    if (!isDesktop) return bar;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: bar,
    );
  }

  Widget _buildLocationCard() {
    Widget chip(String label, LocationInfo? loc, Color color) {
      final text = loc == null ? '定位中…' : loc.display;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.place, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$label $text',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10.5),
                ),
              ),
              if (loc == null)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.2, color: color.withValues(alpha: 0.8)),
                ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('我', _myLocation, Colors.tealAccent),
        const SizedBox(width: 6),
        chip('TA', _peerLocation, Colors.pinkAccent),
      ],
    );
  }

  Widget _buildBody() {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _showReceived && _receivedAction != null ? _buildReceivedAnimation(_receivedAction!) : _buildIdleState(),
      ),
    );
  }

  Widget _buildIdleState() {
    return Pulse(
      infinite: true,
      duration: const Duration(seconds: 2),
      child: Icon(Icons.favorite, size: 50, color: Colors.pinkAccent.withValues(alpha: 0.3 + _heatIntensity * 0.4)),
    );
  }

  Widget _buildReceivedAnimation(TelepathyAction action) {
    return Column(
      key: ValueKey('${action.code}_${DateTime.now().millisecondsSinceEpoch}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        BounceInDown(
          duration: const Duration(milliseconds: 800),
          child: Icon(action.icon, size: 70, color: action.color),
        ),
        const SizedBox(height: 6),
        FadeInUp(
          child: Text(
            action.label,
            style: TextStyle(
              color: action.color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: action.color.withValues(alpha: 0.5), blurRadius: 10)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: TelepathyAction.values.map((action) {
          return _ActionButton(action: action, enabled: !_cooldown && _connected, onTap: () => _sendAction(action));
        }).toList(),
      ),
    );
  }

  Widget _buildStatsBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        '💕 ${_store.totalInteractions} 次互动',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9),
      ),
    );
  }
}

class _ChromeBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _ChromeBtn({required this.icon, required this.tooltip, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 12,
            color: active ? Colors.amberAccent : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final TelepathyAction action;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({required this.action, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1.0 : 0.4,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: action.color.withValues(alpha: 0.12),
              border: Border.all(color: action.color.withValues(alpha: 0.2), width: 0.5),
            ),
            child: Icon(action.icon, color: action.color, size: 18),
          ),
        ),
      ),
    );
  }
}
