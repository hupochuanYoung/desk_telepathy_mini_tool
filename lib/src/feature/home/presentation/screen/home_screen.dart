import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:desk_telepathy/src/core/config/env.dart';
import 'package:desk_telepathy/src/core/config/window_size.dart';
import 'package:desk_telepathy/src/core/service/interaction_store.dart';
import 'package:desk_telepathy/src/core/service/location_service.dart';
import 'package:desk_telepathy/src/core/service/mqtt_service.dart';
import 'package:desk_telepathy/src/core/utils/platform_utils.dart';
import 'package:desk_telepathy/src/core/utils/window_helper.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/flower_bloom.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/flower_garden.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/heatmap_glow.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/log_viewer.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/moire_field.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/particle_background.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/ripple_pulse.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:window_manager/window_manager.dart';

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

  /// 丢花落在花园里的入口 —— 参见 [FlowerGarden]
  final GlobalKey<FlowerGardenState> _gardenKey = GlobalKey<FlowerGardenState>();

  TelepathyAction? _receivedAction;
  bool _showReceived = false;
  int _rippleTrigger = 0;

  ParticleType _bgParticle = ParticleType.stars;
  Color _bgParticleColor = Colors.white;

  PeerStatus _peerStatus = PeerStatus.offline;
  PeerStatus _myStatus = PeerStatus.online;

  double _heatIntensity = 0.0;
  bool _cooldown = false;

  LocationInfo? _myLocation;
  LocationInfo? _peerLocation;

  bool _toolMode = false;
  bool _pinned = true;

  /// pet 模式下，鼠标是否悬停在窗口上 —— 决定是否显现玻璃面板与图标
  bool _hovering = false;

  /// 对方的"活跃度"（0..1）—— 驱动莫尔条纹的旋转速度与复杂度
  /// 每次收到对方消息会被拉满到 1.0，然后平滑衰减回基线（由 [_peerStatus] 决定）
  late final AnimationController _activityCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
    value: 0,
  )..addListener(() => setState(() {}));

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
    _mqtt.sendLocation(info.encode());
  }

  Future<void> _connectMqtt() async {
    final ok = await _mqtt.connect();
    setState(() => _connected = ok);

    _connSub = _mqtt.connectionStream.listen((connected) {
      if (mounted) setState(() => _connected = connected);
    });

    _msgSub = _mqtt.messages.listen(_handleMessage);
  }

  void _handleMessage(TelepathyMessage msg) {
    // 任何来自对方的消息都表明 TA 刚刚"活跃"过
    _bumpPeerActivity();
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
        if (mounted && _peerStatus == PeerStatus.offline) {
          setState(() => _peerStatus = PeerStatus.online);
        }
      case MsgType.location:
        final loc = LocationInfo.decode(msg.data);
        if (loc != null && mounted) setState(() => _peerLocation = loc);
      case MsgType.vase:
        // 旧版本的共享花瓶事件 —— 当前 UI 已移除，忽略即可
        break;
    }
  }

  /// 把活跃度拉满，然后让它缓慢衰减到由状态决定的基线
  void _bumpPeerActivity() {
    _activityCtrl
      ..value = 1.0
      ..animateTo(0.0, duration: const Duration(seconds: 4), curve: Curves.easeOutCubic);
  }

  /// 根据对方当前状态 + 最近一次消息脉冲，合成实时活跃度
  double get _effectivePeerActivity {
    final baseline = switch (_peerStatus) {
      PeerStatus.offline => 0.0,
      PeerStatus.focus => 0.12,
      PeerStatus.online => 0.28,
      PeerStatus.busy => 0.55,
    };
    // _activityCtrl 1→0 的衰减叠加在 baseline 之上
    return math.max(baseline, _activityCtrl.value);
  }

  void _playReceivedAnimation(TelepathyAction action) {
    setState(() {
      _receivedAction = action;
      _showReceived = true;
      _bgParticle = action.particle;
      _bgParticleColor = action.color;
      _heatIntensity = _store.intensity;
      _rippleTrigger++;
    });
    // 在花园里落下一朵
    _gardenKey.currentState?.spawn(action.flower);
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
      _rippleTrigger++;
    });
    // 自己也在花园里丢一朵 —— 即时可视化反馈
    _gardenKey.currentState?.spawn(action.flower);
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
    _activityCtrl.dispose();
    _mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isMobile) return _buildMobileLayout();
    return _buildDesktopFrame();
  }

  // ───────────────────────── Desktop ─────────────────────────

  /// 桌面 frameless 工具：
  /// - pet 常态：220×260，全透明，只有一颗呼吸的心浮在桌面上；
  ///   鼠标靠近时，图标 / 定位 / 窗口按钮才淡入浮现。
  /// - tool 抽屉：420×520，轻磨砂玻璃底板，显示日志 / 位置 / 设置。
  Widget _buildDesktopFrame() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: _toolMode ? _buildToolShell() : _buildPetShell(),
      ),
    );
  }

  /// pet 形态（300×380）：
  ///   - 顶部 ~170: 莫尔干涉盘漂浮
  ///   - 整体背景：花园层 —— 丢花会在这里抽茎、绽放、飘落花瓣
  ///   - 悬停时才显现：玻璃面板 + 定位胶囊 + 丢花动作条
  Widget _buildPetShell() {
    return Stack(
      children: [
        // 极淡的粒子背景
        Positioned.fill(
          child: Opacity(
            opacity: 0.7,
            child: ParticleBackground(
              key: ValueKey('$_bgParticle-pet'),
              type: _bgParticle,
              color: _bgParticleColor,
              count: 14,
            ),
          ),
        ),

        // 花园层 —— 全窗口；花会从下半部抽茎生长
        Positioned.fill(child: FlowerGarden(key: _gardenKey)),

        // 莫尔干涉盘（上半部分）
        Positioned(
          left: 0,
          right: 0,
          top: 16,
          height: 170,
          child: Center(child: _buildCenterOrb()),
        ),

        // 悬停时才出现的玻璃面板 + 控件
        Positioned.fill(child: _buildPetOverlay()),
      ],
    );
  }

  Widget _buildPetOverlay() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      opacity: _hovering ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !_hovering,
        child: Stack(
          children: [
            // 整体极淡的磨砂玻璃底板 —— 只在 hover 时出现
            Positioned.fill(child: _GlassPanel(opacity: 0.08, borderOpacity: 0.10)),
            // 顶部：拖拽把手 + 状态 + 窗口按钮
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTitleBar(showChrome: true, compact: true),
            ),
            // 中下部：定位胶囊 + 动作线条图标
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLocationCard(compact: true),
                  const SizedBox(height: 10),
                  _buildActionBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// tool 形态：保留玻璃底板，把日志 / 设置 / 花园摊开
  Widget _buildToolShell() {
    return Stack(
      children: [
        Positioned.fill(child: _GlassPanel(opacity: 0.18, borderOpacity: 0.12)),
        Positioned.fill(
          child: ParticleBackground(
            key: ValueKey('$_bgParticle-tool'),
            type: _bgParticle,
            color: _bgParticleColor,
            count: 28,
          ),
        ),
        HeatmapGlow(intensity: _heatIntensity),

        // 花园层 —— 覆盖整个工具窗体；茎会从窗体下沿抽出来
        Positioned.fill(child: FlowerGarden(key: _gardenKey)),

        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTitleBar(showChrome: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildLocationCard(),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 120, child: _buildCenterOrb()),
            const SizedBox(height: 8),
            // 丢花动作条
            _buildActionBar(),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: const LogViewer(),
              ),
            ),
            _buildStatsBar(),
          ],
        ),
      ],
    );
  }

  /// 中心：莫尔条纹干涉盘（常态）+ 收到动作时的图标叠加 + 水滴波纹
  Widget _buildCenterOrb() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 热力光晕（互动越多越亮）
        // 注意：HeatmapGlow 内部本身就是 Positioned.fill + IgnorePointer，
        // 必须直接作为 Stack 的子节点，不能再包一层别的 widget
        if (_heatIntensity > 0) HeatmapGlow(intensity: _heatIntensity),

        // 莫尔条纹：始终在场，旋转速度跟随对方活跃度
        MoireField(activity: _effectivePeerActivity),

        // 水滴波纹 —— 发送/接收时触发一次
        Positioned.fill(
          child: RipplePulse(
            trigger: _rippleTrigger == 0 ? null : _rippleTrigger,
            color: (_showReceived && _receivedAction != null)
                ? _receivedAction!.color
                : const Color(0xFF67E8F9), // cyan-300
          ),
        ),

        // 收到动作时，图标在条纹之上 bounce in
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _showReceived && _receivedAction != null
              ? _buildReceivedAnimation(_receivedAction!)
              : const SizedBox.shrink(key: ValueKey('idle-placeholder')),
        ),
      ],
    );
  }

  Widget _buildReceivedAnimation(TelepathyAction action) {
    return Column(
      key: ValueKey('${action.code}_${DateTime.now().millisecondsSinceEpoch}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        BounceInDown(
          duration: const Duration(milliseconds: 800),
          child: FlowerBloom(
            key: ValueKey('bloom_${action.code}_$_rippleTrigger'),
            kind: action.flower,
            size: 96,
          ),
        ),
        const SizedBox(height: 6),
        FadeInUp(
          child: Text(
            action.label,
            style: TextStyle(
              color: action.color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              shadows: [Shadow(color: action.color.withValues(alpha: 0.5), blurRadius: 10)],
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── Mobile ─────────────────────────

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E1A),
      body: Stack(
        children: [
          Positioned.fill(
            child: ParticleBackground(
              key: ValueKey(_bgParticle),
              type: _bgParticle,
              color: _bgParticleColor,
              count: 28,
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
                Expanded(child: _buildCenterOrb()),
                _buildActionBar(),
                _buildStatsBar(),
              ],
            ),
          ),
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

  // ───────────────────────── 细节组件 ─────────────────────────

  Widget _buildTitleBar({required bool showChrome, bool compact = false}) {
    final titleContent = Row(
      children: [
        const Expanded(child: SizedBox.shrink()),
        GestureDetector(
          onTap: _cycleMyStatus,
          child: Tooltip(
            message: '点击切换我的状态',
            child: Icon(_myStatus.icon, size: 11, color: _myStatus.color),
          ),
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

    final bar = Container(
      height: compact ? 26 : 32,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
      child: titleContent,
    );
    if (!isDesktop) return bar;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: bar,
    );
  }

  Widget _buildLocationCard({bool compact = false}) {
    Widget chip(String label, LocationInfo? loc, Color color) {
      final text = loc == null ? '定位中…' : loc.display;
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.18), width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.place, size: compact ? 10 : 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$label $text',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: compact ? 9.5 : 10.5,
                  ),
                ),
              ),
              if (loc == null)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.2,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('我', _myLocation, const Color(0xFF5EEAD4)), // teal-300
        const SizedBox(width: 6),
        chip('TA', _peerLocation, const Color(0xFFA78BFA)), // violet-400
      ],
    );
  }

  Widget _buildActionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: TelepathyAction.values.map((action) {
        return _ActionGlyph(
          action: action,
          enabled: !_cooldown && _connected,
          onTap: () => _sendAction(action),
        );
      }).toList(),
    );
  }

  Widget _buildStatsBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Center(
        child: Text(
          '${_store.totalInteractions} 次互动',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.28),
            fontSize: 9,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 可复用样式 ─────────────────────────

/// 磨砂玻璃底板 —— 用 BackdropFilter 模糊后叠一层半透明白 + 极淡描边
class _GlassPanel extends StatelessWidget {
  final double opacity;
  final double borderOpacity;

  const _GlassPanel({this.opacity = 0.1, this.borderOpacity = 0.12});

  static const double _radius = 22;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: opacity),
                Colors.white.withValues(alpha: opacity * 0.4),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: borderOpacity), width: 0.6),
          ),
        ),
      ),
    );
  }
}

class _ChromeBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _ChromeBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  State<_ChromeBtn> createState() => _ChromeBtnState();
}

class _ChromeBtnState extends State<_ChromeBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? Colors.amberAccent
        : Colors.white.withValues(alpha: _hover ? 0.95 : 0.55);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(widget.icon, size: 12, color: color),
          ),
        ),
      ),
    );
  }
}

/// 线条风动作符号 —— 无边框，hover 时着色 + 微光
class _ActionGlyph extends StatefulWidget {
  final TelepathyAction action;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionGlyph({required this.action, required this.enabled, required this.onTap});

  @override
  State<_ActionGlyph> createState() => _ActionGlyphState();
}

class _ActionGlyphState extends State<_ActionGlyph> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hot = _hover && widget.enabled;
    return Tooltip(
      message: widget.action.label,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: widget.enabled ? 1.0 : 0.35,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hot ? widget.action.color.withValues(alpha: 0.10) : Colors.transparent,
                boxShadow: hot
                    ? [
                        BoxShadow(
                          color: widget.action.color.withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: AnimatedScale(
                scale: hot ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: FlowerIcon(
                  kind: widget.action.flower,
                  size: 26,
                  animated: hot,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

