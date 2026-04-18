import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 莫尔条纹干涉圆盘
///
/// 两层密度略不同的放射状细线 + 一层同心圆环，
/// 反向旋转时因线密度差异产生旋转的花瓣状干涉图案。
///
/// [activity] 0..1：
///   - 0.0 几近静止（只有极缓慢的呼吸）
///   - 0.3 对方在线
///   - 0.6 对方"忙碌"
///   - 1.0 对方刚刚动作（之后指数衰减回基线）
///
/// 配色默认 **冷色干涉**（青 + 紫），避开俗气的粉色。
class MoireField extends StatefulWidget {
  final double activity;
  final Color primary;
  final Color secondary;
  final double size;

  const MoireField({
    super.key,
    required this.activity,
    this.primary = const Color(0xFF67E8F9), // cyan-300
    this.secondary = const Color(0xFFA78BFA), // violet-400
    this.size = 130,
  });

  @override
  State<MoireField> createState() => _MoireFieldState();
}

class _MoireFieldState extends State<MoireField> with SingleTickerProviderStateMixin {
  late final _MoireClock _clock = _MoireClock(initialActivity: widget.activity);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _clock.tick(elapsed, widget.activity))..start();
  }

  @override
  void didUpdateWidget(covariant MoireField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clock.activity = widget.activity;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _MoirePainter(
          clock: _clock,
          primary: widget.primary,
          secondary: widget.secondary,
        ),
      ),
    );
  }
}

/// 手动累积相位的"时钟"——避免活跃度突变时角度跳变
class _MoireClock extends ChangeNotifier {
  Duration _last = Duration.zero;
  double phaseA = 0; // 顺时针放射层
  double phaseB = 0; // 逆时针放射层
  double phaseRing = 0; // 同心圆环漂移
  double activity;

  _MoireClock({required double initialActivity}) : activity = initialActivity;

  void tick(Duration elapsed, double activityNow) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    activity = activityNow;
    // 即便 activity=0 也保留极慢的漂移，避免完全死板
    phaseA += dt * (0.04 + activityNow * 0.9);
    phaseB -= dt * (0.03 + activityNow * 0.75);
    phaseRing += dt * (0.02 + activityNow * 0.12);
    notifyListeners();
  }
}

class _MoirePainter extends CustomPainter {
  final _MoireClock clock;
  final Color primary;
  final Color secondary;

  _MoirePainter({
    required this.clock,
    required this.primary,
    required this.secondary,
  }) : super(repaint: clock);

  // 线条层密度（略有差异是产生莫尔干涉的关键）
  static const int _countA = 96;
  static const int _countB = 108;
  static const int _ringCount = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;
    final act = clock.activity.clamp(0.0, 1.0);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    // 背景极暗的径向渐变，让条纹更"立体"
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0.15),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // 放射层 A（顺时针）
    _drawRadial(
      canvas,
      c,
      r,
      count: _countA,
      rotation: clock.phaseA,
      inner: r * 0.05,
      color: primary,
      alpha: 0.35 + act * 0.30,
      strokeWidth: 0.6,
    );

    // 放射层 B（逆时针、线数略多 → 产生漂亮的干涉花瓣）
    _drawRadial(
      canvas,
      c,
      r,
      count: _countB,
      rotation: clock.phaseB,
      inner: r * 0.05,
      color: secondary,
      alpha: 0.30 + act * 0.30,
      strokeWidth: 0.6,
    );

    // 同心圆环 —— 与放射层产生径向-切向莫尔
    _drawRings(
      canvas,
      c,
      r,
      count: _ringCount,
      offset: clock.phaseRing % 1.0,
      color: primary.withValues(alpha: 0.12 + act * 0.13),
    );

    // 活跃度高时，叠加第三层淡色高光（增强复杂度）
    if (act > 0.4) {
      _drawRadial(
        canvas,
        c,
        r,
        count: 144,
        rotation: clock.phaseA * 0.4,
        inner: r * 0.2,
        color: Colors.white,
        alpha: (act - 0.4) * 0.35,
        strokeWidth: 0.4,
      );
    }

    canvas.restore();

    // 外圈柔光描边
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = primary.withValues(alpha: 0.25 + act * 0.35),
    );

    // 中心光点（紫色 → 活跃时变亮变青）
    final centerColor = Color.lerp(secondary, primary, act)!;
    canvas.drawCircle(
      c,
      2.2 + act * 1.2,
      Paint()
        ..color = centerColor.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5),
    );
  }

  void _drawRadial(
    Canvas canvas,
    Offset c,
    double r, {
    required int count,
    required double rotation,
    required double inner,
    required Color color,
    required double alpha,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final step = 2 * math.pi / count;
    for (int i = 0; i < count; i++) {
      final a = rotation + i * step;
      final dx = math.cos(a);
      final dy = math.sin(a);
      canvas.drawLine(
        c + Offset(dx, dy) * inner,
        c + Offset(dx, dy) * r,
        paint,
      );
    }
  }

  void _drawRings(
    Canvas canvas,
    Offset c,
    double r, {
    required int count,
    required double offset,
    required Color color,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4
      ..color = color
      ..isAntiAlias = true;
    for (int i = 1; i <= count; i++) {
      final rr = r * ((i + offset) % count) / count;
      if (rr < 1.5) continue;
      canvas.drawCircle(c, rr, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MoirePainter old) =>
      old.primary != primary || old.secondary != secondary;
}
