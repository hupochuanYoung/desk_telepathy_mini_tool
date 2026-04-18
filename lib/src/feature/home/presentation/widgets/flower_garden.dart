import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'flower_bloom.dart';

/// 一朵正在生长的花（含茎、花头、飘落的花瓣）
class _GardenBloom {
  _GardenBloom({
    required this.kind,
    required this.position,
    required this.stemHeight,
    required this.stemBend,
    required this.rotationSeed,
    required this.life,
    required this.energy,
    required this.petalDrift,
  }) : age = 0;

  final FlowerKind kind;
  final Offset position;
  final double stemHeight;
  final double stemBend;
  final double rotationSeed;
  final double life;
  final double energy;

  double age;
  double petalDrift;
}

/// 丢花互动的可视化花园。
///
/// 使用方式：拿 [GlobalKey] 到 [FlowerGardenState]，调用 [FlowerGardenState.spawn]
/// 就会随机落下一朵对应花种 —— 茎会向上抽出，花头绽开，花瓣缓缓飘落，
/// 生命结束时整朵花整体淡出。
class FlowerGarden extends StatefulWidget {
  const FlowerGarden({super.key});

  @override
  State<FlowerGarden> createState() => FlowerGardenState();
}

class FlowerGardenState extends State<FlowerGarden>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final List<_GardenBloom> _blooms = [];
  final math.Random _random = math.Random();
  double _time = 0;
  Size _size = Size.zero;

  /// 待决的 spawn —— LayoutBuilder 首次拿到尺寸之前 spawn 会存到这里
  final List<FlowerKind> _pending = [];

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(() {
        // 固定步长推进：比 ticker.value 更稳
        setState(() {
          _time += 0.016;
          for (final b in _blooms) {
            b.age += 0.016;
            b.petalDrift += 0.008 + b.energy * 0.003;
          }
          _blooms.removeWhere((b) => b.age > b.life);
        });
      })
      ..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 在花园里落下一朵花。
  /// [position] 为空时会在靠近"地面"（窗口下沿）的范围里随机选位。
  void spawn(FlowerKind kind, {Offset? position}) {
    if (_size == Size.zero) {
      _pending.add(kind);
      return;
    }
    final pos = position ?? _randomGroundPosition();
    _blooms.add(_makeBloom(kind, pos));
  }

  Offset _randomGroundPosition() {
    final w = math.max(_size.width - 48, 1.0);
    // 尽量让花头不超出顶部：茎高约 50~130，我们把 position.y 控制在下半部
    final bottomY = _size.height * 0.92;
    final topY = _size.height * 0.65;
    return Offset(
      24 + _random.nextDouble() * w,
      topY + _random.nextDouble() * math.max(bottomY - topY, 1),
    );
  }

  _GardenBloom _makeBloom(FlowerKind kind, Offset pos) {
    return _GardenBloom(
      kind: kind,
      position: pos,
      stemHeight: 50 + _random.nextDouble() * 80,
      stemBend: -24 + _random.nextDouble() * 48,
      rotationSeed: _random.nextDouble() * math.pi * 2,
      life: 8 + _random.nextDouble() * 6,
      energy: 0.7 + _random.nextDouble() * 0.9,
      petalDrift: _random.nextDouble() * math.pi * 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_pending.isNotEmpty && _size != Size.zero) {
          final pending = List<FlowerKind>.from(_pending);
          _pending.clear();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            for (final k in pending) {
              spawn(k);
            }
          });
        }
        return IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _GardenPainter(blooms: _blooms, time: _time),
          ),
        );
      },
    );
  }
}

/// 花园绘制器 —— 渲染所有活跃的茎 + 花头 + 飘落花瓣
class _GardenPainter extends CustomPainter {
  _GardenPainter({required this.blooms, required this.time});

  final List<_GardenBloom> blooms;
  final double time;

  static const _stemColor = Color(0xFF7FB57A);

  @override
  void paint(Canvas canvas, Size size) {
    // 先画茎（全部在花头下面）
    for (final b in blooms) {
      _paintStem(canvas, b);
    }
    // 再画花头 + 飘落花瓣
    for (final b in blooms) {
      _paintBloom(canvas, b);
      _paintFloatingPetals(canvas, b);
    }
  }

  double _lifeT(_GardenBloom b) => (b.age / b.life).clamp(0.0, 1.0);

  /// 生命末段的淡出系数（0..1）
  double _fade(_GardenBloom b) {
    final t = _lifeT(b);
    if (t < 0.75) return 1.0;
    return ((1 - t) / 0.25).clamp(0.0, 1.0);
  }

  Offset _flowerCenter(_GardenBloom b) {
    final t = _lifeT(b);
    final grow = Curves.easeOutCubic.transform(math.min(t * 2.0, 1.0));
    final sway = math.sin(time * 0.8 + b.rotationSeed) * 8 * b.energy;
    return Offset(b.position.dx + sway, b.position.dy - b.stemHeight * grow);
  }

  void _paintStem(Canvas canvas, _GardenBloom b) {
    final t = _lifeT(b);
    final grow = Curves.easeOutCubic.transform(math.min(t * 2.0, 1.0));
    final sway = math.sin(time * 0.8 + b.rotationSeed) * 8 * b.energy;
    final fade = _fade(b);

    final start = b.position;
    final end = Offset(start.dx + sway, start.dy - b.stemHeight * grow);
    final control = Offset(
      start.dx + b.stemBend + sway * 0.6,
      start.dy - b.stemHeight * 0.58 * grow,
    );

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

    final stemPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 + b.energy * 0.8
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          _stemColor.withValues(alpha: 0.05 * fade),
          _stemColor.withValues(alpha: 0.85 * fade),
        ],
      ).createShader(Rect.fromPoints(start, end));
    canvas.drawPath(path, stemPaint);

    // 一对叶片
    final leafPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _stemColor.withValues(alpha: 0.22 * fade);
    final leafAnchor = _quadPoint(start, control, end, 0.58);
    final leafDir = (end - start).direction + math.pi / 2.8;
    _drawLeaf(canvas, leafAnchor, 16 + b.energy * 6, leafDir, leafPaint);
    _drawLeaf(canvas, leafAnchor.translate(-3, 8), 11 + b.energy * 5,
        leafDir + math.pi, leafPaint);
  }

  void _drawLeaf(
      Canvas canvas, Offset center, double length, double angle, Paint paint) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(length * 0.3, -length * 0.36, length, 0)
      ..quadraticBezierTo(length * 0.3, length * 0.36, 0, 0);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  Offset _quadPoint(Offset p0, Offset p1, Offset p2, double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * p0.dx + 2 * mt * t * p1.dx + t * t * p2.dx,
      mt * mt * p0.dy + 2 * mt * t * p1.dy + t * t * p2.dy,
    );
  }

  void _paintBloom(Canvas canvas, _GardenBloom b) {
    final center = _flowerCenter(b);
    final t = _lifeT(b);
    final open = Curves.easeOutBack.transform(math.min(t * 2.4, 1.0));
    final pulse = 1 + math.sin(time * 1.3 + b.rotationSeed) * 0.05;
    final fade = _fade(b);
    if (open <= 0 || fade <= 0) return;

    // 背景微光晕
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          b.kind.accent.withValues(alpha: 0.22 * fade * open),
          b.kind.accent.withValues(alpha: 0.06 * fade * open),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 42));
    canvas.drawCircle(center, 42, glow);

    // 用 saveLayer 整体淡出（茎和花分开 fade 会显得不统一，所以花这里统一做）
    final layerRect = Rect.fromCircle(center: center, radius: 60);
    final layerPaint = Paint()
      ..colorFilter = ColorFilter.mode(
        Colors.white.withValues(alpha: fade),
        BlendMode.modulate,
      );
    canvas.saveLayer(layerRect, layerPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(b.rotationSeed + math.sin(time + b.rotationSeed) * 0.08);
    // 花园里的花尺寸比"收到时中央那朵"小一些，大约是 0.55× 单位尺寸
    canvas.scale(open * pulse * 0.55);
    FlowerBloomPainter.paintHeadAtOrigin(canvas, b.kind, time);
    canvas.restore();

    canvas.restore();
  }

  /// 围着花头打转、缓慢下沉的花瓣 —— 参考 main2.dart 的 _paintFloatingPetals
  void _paintFloatingPetals(Canvas canvas, _GardenBloom b) {
    final center = _flowerCenter(b);
    final fade = _fade(b);
    final t = _lifeT(b);
    // 花半开之后才开始飘瓣
    if (t < 0.25) return;

    final particleCount = 3 + (b.energy * 2).floor();
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < particleCount; i++) {
      final shift = b.petalDrift + i * 1.7;
      final dx = math.cos(shift) * (10 + i * 6) + math.sin(time * 0.7 + i) * 4;
      // dy 随时间累积 —— 花瓣会越飘越低
      final dy = math.sin(shift * 1.2) * 8 + (b.age * 10) % 36;
      final petalCenter = center.translate(dx, dy);
      final angle = shift + math.sin(time + i) * 0.3;
      final opacity = (0.24 - i * 0.025).clamp(0.05, 0.24) * fade;

      canvas.save();
      canvas.translate(petalCenter.dx, petalCenter.dy);
      canvas.rotate(angle);

      final path = Path();
      switch (b.kind) {
        case FlowerKind.tulip:
          path
            ..moveTo(0, 0)
            ..quadraticBezierTo(5.5, -1.8, 0, -11)
            ..quadraticBezierTo(-5.5, -1.8, 0, 0);
          paint.color = b.kind.accent.withValues(alpha: opacity);
        case FlowerKind.daisy:
          path
            ..moveTo(0, 0)
            ..quadraticBezierTo(3.5, -1.0, 0, -8)
            ..quadraticBezierTo(-3.5, -1.0, 0, 0);
          paint.color = Colors.white.withValues(alpha: opacity + 0.04);
        case FlowerKind.lily:
          path
            ..moveTo(0, 0)
            ..quadraticBezierTo(4.5, -1.6, 0, -10)
            ..quadraticBezierTo(-4.5, -1.6, 0, 0);
          paint.color = b.kind.accent.withValues(alpha: opacity);
        case FlowerKind.rose:
          path
            ..moveTo(0, 0)
            ..quadraticBezierTo(4.2, -1.2, 0, -9)
            ..quadraticBezierTo(-4.2, -1.2, 0, 0);
          paint.color = b.kind.accent.withValues(alpha: opacity);
        case FlowerKind.sunflower:
          path
            ..moveTo(0, 0)
            ..quadraticBezierTo(2.8, -0.8, 0, -9.5)
            ..quadraticBezierTo(-2.8, -0.8, 0, 0);
          paint.color = b.kind.accent.withValues(alpha: opacity);
      }

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GardenPainter oldDelegate) => true;
}
