import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:desk_telepathy/src/core/config/window_size.dart';
import 'package:desk_telepathy/src/core/service/location_service.dart';
import 'package:desk_telepathy/src/core/utils/platform_utils.dart';
import 'package:desk_telepathy/src/core/utils/window_helper.dart';
import 'package:desk_telepathy/src/feature/home/presentation/provider/home_provider.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/flower_bloom.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/flower_garden.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/heatmap_glow.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/interference_globe.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/log_viewer.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/particle_background.dart';
import 'package:desk_telepathy/src/feature/home/presentation/widgets/status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomePageState();
}

class _HomePageState extends State<HomeScreen> with TickerProviderStateMixin {
  /// 丢花落在花园里的入口 —— 参见 [FlowerGarden]
  final GlobalKey<FlowerGardenState> _gardenKey = GlobalKey<FlowerGardenState>();

  StreamSubscription<ReceivedActionEvent>? _actionSub;
  StreamSubscription<void>? _bumpSub;

  TelepathyAction? _receivedAction;
  bool _showReceived = false;
  int _rippleTrigger = 0;

  bool _toolMode = false;
  bool _pinned = true;

  /// pet 模式下，鼠标是否悬停在窗口上
  bool _hovering = false;

  /// 对方的"活跃度"（0..1）—— 驱动莫尔条纹的旋转速度与复杂度
  /// 每次 provider 通知对方消息到达时拉满到 1.0，再缓慢衰减
  late final AnimationController _activityCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
    value: 0,
  )..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    // provider 已经在 main.dart 里 init() 过了，这里只订阅事件流
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<HomeProvider>();
      _actionSub = provider.onReceivedAction.listen(_onReceivedAction);
      _bumpSub = provider.onPeerActivityBump.listen((_) => _bumpPeerActivity());
    });
  }

  void _onReceivedAction(ReceivedActionEvent event) {
    if (!mounted) return;
    setState(() {
      _receivedAction = event.action;
      _showReceived = true;
      _rippleTrigger++;
    });
    _gardenKey.currentState?.spawn(event.action.flower);
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showReceived = false);
    });
  }

  void _bumpPeerActivity() {
    _activityCtrl
      ..value = 1.0
      ..animateTo(0.0, duration: const Duration(seconds: 4), curve: Curves.easeOutCubic);
  }

  double _effectivePeerActivity(PeerStatus peerStatus) {
    final baseline = switch (peerStatus) {
      PeerStatus.offline => 0.0,
      PeerStatus.focus => 0.12,
      PeerStatus.online => 0.28,
      PeerStatus.busy => 0.55,
    };
    return math.max(baseline, _activityCtrl.value);
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
    _actionSub?.cancel();
    _bumpSub?.cancel();
    _activityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isMobile) return _buildMobileLayout();
    return _buildDesktopFrame();
  }

  // ───────────────────────── Desktop ─────────────────────────

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

  /// pet 形态：整体几乎透明，悬停时才浮出玻璃面板 + 地球 + 控件
  Widget _buildPetShell() {
    final provider = context.watch<HomeProvider>();
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: 0.7,
            child: ParticleBackground(
              key: ValueKey('${provider.bgParticle}-pet'),
              type: provider.bgParticle,
              color: provider.bgParticleColor,
              count: 14,
            ),
          ),
        ),
        Positioned.fill(child: FlowerGarden(key: _gardenKey)),
        Positioned.fill(child: _buildPetOverlay()),
        Positioned(
          top: 32,
          left: 10,
          right: 10,
          child: _buildGreetingBanner(compact: true),
        ),
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
            Positioned.fill(child: _GlassPanel(opacity: 0.08, borderOpacity: 0.10)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTitleBar(showChrome: true, compact: true),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 28,
              height: 170,
              child: Center(child: _buildCenterOrb()),
            ),
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
    final provider = context.watch<HomeProvider>();
    return Stack(
      children: [
        Positioned.fill(child: _GlassPanel(opacity: 0.18, borderOpacity: 0.12)),
        Positioned.fill(
          child: ParticleBackground(
            key: ValueKey('${provider.bgParticle}-tool'),
            type: provider.bgParticle,
            color: provider.bgParticleColor,
            count: 28,
          ),
        ),
        HeatmapGlow(intensity: provider.heatIntensity),
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
            SizedBox(height: 140, child: _buildCenterOrb()),
            const SizedBox(height: 8),
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
        Positioned(
          top: 40,
          left: 16,
          right: 16,
          child: _buildGreetingBanner(),
        ),
      ],
    );
  }

  /// 对方上线欢迎条：4 秒后淡出，永远不挡点击
  Widget _buildGreetingBanner({bool compact = false}) {
    final greeting = context.watch<HomeProvider>().greeting;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.4),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: greeting == null
            ? const SizedBox.shrink(key: ValueKey('greet-empty'))
            : Center(
                key: ValueKey('greet-$greeting'),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 14,
                    vertical: compact ? 5 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F2E).withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF5EEAD4).withValues(alpha: 0.45),
                      width: 0.7,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5EEAD4).withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Text(
                    greeting,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: compact ? 10.5 : 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// 中心：旋转地球 + 焦点处的莫尔干涉 + 收到动作时的图标叠加
  Widget _buildCenterOrb() {
    final provider = context.watch<HomeProvider>();
    return Stack(
      alignment: Alignment.center,
      children: [
        if (provider.heatIntensity > 0) HeatmapGlow(intensity: provider.heatIntensity),
        InterferenceGlobe(
          focal: provider.focalLocation,
          activity: _effectivePeerActivity(provider.peerStatus),
          rippleTrigger: _rippleTrigger == 0 ? null : _rippleTrigger,
          primary: (_showReceived && _receivedAction != null)
              ? _receivedAction!.color
              : const Color(0xFF67E8F9),
          size: 130,
          onManualRotate: provider.clearFocalForManualRotation,
        ),
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
    return IgnorePointer(
      child: Column(
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
      ),
    );
  }

  // ───────────────────────── Mobile ─────────────────────────

  Widget _buildMobileLayout() {
    final provider = context.watch<HomeProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E1A),
      body: Stack(
        children: [
          Positioned.fill(
            child: ParticleBackground(
              key: ValueKey(provider.bgParticle),
              type: provider.bgParticle,
              color: provider.bgParticleColor,
              count: 28,
            ),
          ),
          HeatmapGlow(intensity: provider.heatIntensity),
          Positioned.fill(child: FlowerGarden(key: _gardenKey)),
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
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: SafeArea(child: _buildGreetingBanner()),
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
    final provider = context.watch<HomeProvider>();
    final titleContent = Row(
      children: [
        const Expanded(child: SizedBox.shrink()),
        GestureDetector(
          onTap: provider.cycleMyStatus,
          child: Tooltip(
            message: '点击切换我的状态',
            child: Icon(provider.myStatus.icon, size: 11, color: provider.myStatus.color),
          ),
        ),
        const SizedBox(width: 6),
        StatusIndicator(status: provider.peerStatus),
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
    final provider = context.watch<HomeProvider>();

    Widget chip(
      String label,
      LocationInfo? loc,
      Color color, {
      required bool loading,
      required bool dimmed,
    }) {
      final String text;
      if (loc != null) {
        text = loc.display;
      } else if (loading) {
        text = '定位中…';
      } else {
        text = '—';
      }
      final baseAlpha = dimmed ? 0.35 : 0.85;
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: dimmed ? 0.03 : 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: color.withValues(alpha: dimmed ? 0.10 : 0.18),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.place,
                size: compact ? 10 : 12,
                color: color.withValues(alpha: dimmed ? 0.5 : 1.0),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$label $text',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: baseAlpha),
                    fontSize: compact ? 9.5 : 10.5,
                  ),
                ),
              ),
              if (loading)
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

    final peerOffline = provider.peerStatus == PeerStatus.offline;

    return Row(
      children: [
        chip(
          '我',
          provider.myLocation,
          const Color(0xFF5EEAD4),
          loading: provider.myLocation == null,
          dimmed: false,
        ),
        const SizedBox(width: 6),
        chip(
          'TA',
          provider.peerLocation,
          const Color(0xFFA78BFA),
          // 关键修复：不再只看"对方在线 && 位置为空"，而是真正的"正在等待窗口期内"
          // 超时后 provider 会把 peerLocationLoading 置回 false，UI 立刻显示 "—"
          loading: !peerOffline && provider.peerLocation == null,
          dimmed: peerOffline,
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    final provider = context.watch<HomeProvider>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: TelepathyAction.values.map((action) {
        return _ActionGlyph(
          action: action,
          enabled: !provider.cooldown && provider.connected,
          onTap: () => provider.sendAction(action),
        );
      }).toList(),
    );
  }

  Widget _buildStatsBar() {
    final provider = context.watch<HomeProvider>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Center(
        child: Text(
          '${provider.store.totalInteractions} 次互动',
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
