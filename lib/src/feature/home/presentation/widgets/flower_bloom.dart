import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 丢花互动的花种
enum FlowerKind {
  tulip('tulip', '郁金香'),
  daisy('daisy', '雏菊'),
  lily('lily', '百合'),
  rose('rose', '玫瑰'),
  sunflower('sunflower', '向日葵');

  final String code;
  final String label;

  const FlowerKind(this.code, this.label);

  static FlowerKind? fromCode(String code) {
    for (final f in FlowerKind.values) {
      if (f.code == code) return f;
    }
    return null;
  }

  /// 代表色 —— 在热区光晕、按钮光晕里复用
  Color get accent {
    switch (this) {
      case FlowerKind.tulip:
        return const Color(0xFFFF8BB8);
      case FlowerKind.daisy:
        return const Color(0xFFFFE88A);
      case FlowerKind.lily:
        return const Color(0xFFD4A5FF);
      case FlowerKind.rose:
        return const Color(0xFFFF6A7D);
      case FlowerKind.sunflower:
        return const Color(0xFFFFC93E);
    }
  }
}

/// 一朵"会开花"的绘制体
/// - [progress] 0..1，越大花开得越饱满
/// - [time]     全局时间，用来做花瓣摆动（秒）
/// - [size]     画布边长，花心定在中央
class FlowerBloomPainter extends CustomPainter {
  FlowerBloomPainter({
    required this.kind,
    required this.progress,
    required this.time,
  });

  final FlowerKind kind;
  final double progress;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final open = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    final pulse = 1 + math.sin(time * 2.2) * 0.05;
    final scale = (size.shortestSide / 140) * open * pulse;
    final unit = size.shortestSide * 0.42;

    // 背景光晕
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          kind.accent.withValues(alpha: 0.32 * open),
          kind.accent.withValues(alpha: 0.10 * open),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: unit * 1.6));
    canvas.drawCircle(center, unit * 1.6, glowPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.sin(time * 0.9) * 0.05);
    canvas.scale(scale);
    paintHeadAtOrigin(canvas, kind, time);
    canvas.restore();
  }

  /// 在当前画布原点绘制一朵花（不含光晕、不含 open/pulse 缩放）。
  /// 用于 FlowerGarden 等复用场景 —— 调用方负责平移和缩放。
  static void paintHeadAtOrigin(Canvas canvas, FlowerKind kind, double time) {
    switch (kind) {
      case FlowerKind.tulip:
        _paintTulip(canvas, time);
      case FlowerKind.daisy:
        _paintDaisy(canvas, time);
      case FlowerKind.lily:
        _paintLily(canvas, time);
      case FlowerKind.rose:
        _paintRose(canvas, time);
      case FlowerKind.sunflower:
        _paintSunflower(canvas, time);
    }
  }

  // ─────────────── Tulip (郁金香)：3 瓣合拢 ───────────────
  static void _paintTulip(Canvas canvas, double time) {
    const petalLength = 52.0;
    const petalWidth = 28.0;
    final base = const Color(0xFFFF8BB8);
    final light = Color.lerp(base, Colors.white, 0.35)!;
    final dark = Color.lerp(base, const Color(0xFF5A1A38), 0.25)!;

    void drawPetal(double dx, double tipY, double widthScale) {
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(
          petalWidth * widthScale + dx,
          -petalLength * 0.2,
          dx,
          tipY,
        )
        ..quadraticBezierTo(
          -petalWidth * widthScale + dx,
          -petalLength * 0.2,
          0,
          0,
        );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [dark, base, light],
        ).createShader(
          Rect.fromLTWH(
            -petalWidth * 1.4,
            -petalLength * 1.3,
            petalWidth * 2.8,
            petalLength * 1.4,
          ),
        );
      canvas.drawPath(path, paint);
    }

    drawPetal(-petalWidth * 0.45, -petalLength * 0.88, 0.95);
    drawPetal(petalWidth * 0.45, -petalLength * 0.88, 0.95);
    drawPetal(0, -petalLength * 1.08, 1.05);

    final core = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withValues(alpha: 0.85), base.withValues(alpha: 0.4), Colors.transparent],
      ).createShader(Rect.fromCircle(center: const Offset(0, -4), radius: 14));
    canvas.drawCircle(const Offset(0, -4), 8, core);
  }

  // ─────────────── Daisy (雏菊)：多瓣白色放射 ───────────────
  static void _paintDaisy(Canvas canvas, double time) {
    const petalLength = 38.0;
    const petalWidth = 11.0;
    const petalCount = 12;

    for (int i = 0; i < petalCount; i++) {
      final angle = (math.pi * 2 / petalCount) * i;
      final wobble = math.sin(time * 1.8 + i) * 0.08;
      canvas.save();
      canvas.rotate(angle + wobble);

      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(petalWidth, -petalLength * 0.1, 0, -petalLength)
        ..quadraticBezierTo(-petalWidth, -petalLength * 0.1, 0, 0);

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFFFFF5D2).withValues(alpha: 0.55),
            Colors.white,
            Colors.white.withValues(alpha: 0.9),
          ],
        ).createShader(
          Rect.fromLTWH(-petalWidth, -petalLength, petalWidth * 2, petalLength),
        );

      canvas.drawPath(path, paint);
      canvas.restore();
    }

    const coreColor = Color(0xFFFFD75E);
    final corePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Colors.white, coreColor, Color(0xFFFFAF2A)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 22));
    canvas.drawCircle(Offset.zero, 13, corePaint);

    // 中心小点点
    final dotPaint = Paint()..color = const Color(0xFF7A4B00).withValues(alpha: 0.5);
    for (int j = 0; j < 6; j++) {
      final a = (math.pi * 2 / 6) * j;
      canvas.drawCircle(Offset(math.cos(a) * 5, math.sin(a) * 5), 1.2, dotPaint);
    }
  }

  // ─────────────── Lily (百合)：6 瓣紫色 + 花蕊 ───────────────
  static void _paintLily(Canvas canvas, double time) {
    const petalLength = 54.0;
    const petalWidth = 22.0;
    final base = Color.lerp(const Color(0xFFD4A5FF), Colors.white, 0.38)!;
    final edge = const Color(0xFFB46BFF);

    for (int i = 0; i < 6; i++) {
      final angle = (math.pi * 2 / 6) * i;
      final wobble = math.sin(time * 1.3 + i) * 0.07;
      canvas.save();
      canvas.rotate(angle + wobble);

      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(
          petalWidth * 0.95,
          -petalLength * 0.25,
          0,
          -petalLength,
        )
        ..quadraticBezierTo(
          -petalWidth * 0.95,
          -petalLength * 0.25,
          0,
          0,
        );

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            edge.withValues(alpha: 0.85),
            base,
            Colors.white.withValues(alpha: 0.9),
          ],
        ).createShader(
          Rect.fromLTWH(-petalWidth, -petalLength, petalWidth * 2, petalLength),
        );
      canvas.drawPath(path, paint);

      final dotPaint = Paint()..color = const Color(0xFFB74B9A).withValues(alpha: 0.35);
      for (int j = 0; j < 4; j++) {
        final yy = -petalLength * (0.3 + j * 0.12);
        final xx = math.sin(j * 1.7 + i) * petalWidth * 0.22;
        canvas.drawCircle(Offset(xx, yy), 1.1 + j * 0.2, dotPaint);
      }
      canvas.restore();
    }

    // 花蕊
    final filament = Paint()
      ..color = const Color(0xFFFFE4A8)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final tip = Paint()..color = const Color(0xFFFFA94D);
    for (int i = 0; i < 4; i++) {
      final a = -0.35 + i * 0.23;
      final end = Offset(math.sin(a) * 10, -12 - i * 2.2);
      canvas.drawLine(Offset.zero, end, filament);
      canvas.drawCircle(end, 2.2, tip);
    }
  }

  // ─────────────── Rose (玫瑰)：多层卷起花瓣 ───────────────
  static void _paintRose(Canvas canvas, double time) {
    final base = const Color(0xFFE53E5A);
    final dark = Color.lerp(base, Colors.black, 0.35)!;
    final light = Color.lerp(base, Colors.white, 0.4)!;

    // 外层大花瓣（5 片）
    const outerR = 38.0;
    for (int i = 0; i < 5; i++) {
      final angle = (math.pi * 2 / 5) * i - math.pi / 2;
      final wobble = math.sin(time * 1.1 + i) * 0.05;
      canvas.save();
      canvas.rotate(angle + wobble);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(outerR * 0.85, -outerR * 0.25, 0, -outerR)
        ..quadraticBezierTo(-outerR * 0.85, -outerR * 0.25, 0, 0);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [dark, base, light],
        ).createShader(
          Rect.fromLTWH(-outerR, -outerR, outerR * 2, outerR),
        );
      canvas.drawPath(path, paint);
      canvas.restore();
    }

    // 中层花瓣（4 片，错位）
    const midR = 22.0;
    for (int i = 0; i < 4; i++) {
      final angle = (math.pi * 2 / 4) * i + math.pi / 4;
      canvas.save();
      canvas.rotate(angle);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(midR * 0.9, -midR * 0.15, 0, -midR)
        ..quadraticBezierTo(-midR * 0.9, -midR * 0.15, 0, 0);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [dark, base],
        ).createShader(Rect.fromLTWH(-midR, -midR, midR * 2, midR));
      canvas.drawPath(path, paint);
      canvas.restore();
    }

    // 花心 —— 一小簇卷起
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [light, base, dark],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 12));
    canvas.drawCircle(Offset.zero, 9, corePaint);

    // 高光
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(const Offset(-3, -4), 3.2, highlight);
  }

  // ─────────────── Sunflower (向日葵)：细长黄瓣 + 棕色花心 ───────────────
  static void _paintSunflower(Canvas canvas, double time) {
    const petalLength = 42.0;
    const petalWidth = 9.0;
    const petalCount = 18;
    final base = const Color(0xFFFFC93E);
    final dark = const Color(0xFFFF9A00);
    final light = const Color(0xFFFFEAA0);

    for (int i = 0; i < petalCount; i++) {
      final angle = (math.pi * 2 / petalCount) * i;
      final wobble = math.sin(time * 1.6 + i * 0.5) * 0.06;
      canvas.save();
      canvas.rotate(angle + wobble);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(petalWidth, -petalLength * 0.3, 0, -petalLength)
        ..quadraticBezierTo(-petalWidth, -petalLength * 0.3, 0, 0);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [dark, base, light],
        ).createShader(
          Rect.fromLTWH(-petalWidth, -petalLength, petalWidth * 2, petalLength),
        );
      canvas.drawPath(path, paint);
      canvas.restore();
    }

    // 棕色花心 + 种子纹理
    final coreOuter = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF8B4A00), Color(0xFF3E1C00)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 16));
    canvas.drawCircle(Offset.zero, 15, coreOuter);

    final seedPaint = Paint()..color = const Color(0xFF1E0A00).withValues(alpha: 0.7);
    const rings = [5.0, 9.0, 13.0];
    const counts = [6, 10, 14];
    for (int r = 0; r < rings.length; r++) {
      final radius = rings[r];
      final count = counts[r];
      for (int i = 0; i < count; i++) {
        final a = (math.pi * 2 / count) * i + r * 0.4;
        canvas.drawCircle(
          Offset(math.cos(a) * radius, math.sin(a) * radius),
          1.0,
          seedPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant FlowerBloomPainter old) =>
      old.progress != progress || old.time != time || old.kind != kind;
}

/// 收到/发出丢花时，中央位置一次"开花"动画
class FlowerBloom extends StatefulWidget {
  const FlowerBloom({
    super.key,
    required this.kind,
    this.size = 84,
    this.onComplete,
  });

  final FlowerKind kind;
  final double size;
  final VoidCallback? onComplete;

  @override
  State<FlowerBloom> createState() => _FlowerBloomState();
}

class _FlowerBloomState extends State<FlowerBloom>
    with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final AnimationController _tick = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _grow.forward().whenComplete(() => widget.onComplete?.call());
  }

  @override
  void dispose() {
    _grow.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_grow, _tick]),
        builder: (_, _) {
          return CustomPaint(
            painter: FlowerBloomPainter(
              kind: widget.kind,
              progress: Curves.easeOutCubic.transform(_grow.value),
              time: _tick.value * 4, // 0..4 秒
            ),
          );
        },
      ),
    );
  }
}

/// 动作条上使用的小尺寸静态花朵图标
class FlowerIcon extends StatefulWidget {
  const FlowerIcon({
    super.key,
    required this.kind,
    this.size = 22,
    this.animated = false,
  });

  final FlowerKind kind;
  final double size;

  /// 是否持续做轻微摆动动画（hover 时用）
  final bool animated;

  @override
  State<FlowerIcon> createState() => _FlowerIconState();
}

class _FlowerIconState extends State<FlowerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didUpdateWidget(covariant FlowerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.animated && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.animated) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) {
          return CustomPaint(
            painter: FlowerBloomPainter(
              kind: widget.kind,
              progress: 1.0,
              time: _ctrl.value * 4,
            ),
          );
        },
      ),
    );
  }
}
