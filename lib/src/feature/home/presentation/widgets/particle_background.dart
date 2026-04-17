import 'dart:math';
import 'package:flutter/material.dart';

/// 粒子类型
enum ParticleType { snow, stars, hearts, firefly }

class Particle {
  double x, y, speed, size, opacity;
  Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
  });
}

/// 粒子背景 — 用 CustomPainter + AnimationController 驱动
class ParticleBackground extends StatefulWidget {
  final ParticleType type;
  final Color color;
  final int count;

  const ParticleBackground({
    super.key,
    this.type = ParticleType.stars,
    this.color = Colors.white,
    this.count = 30,
  });

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Particle> _particles;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _particles = List.generate(widget.count, (_) => _randomParticle());
  }

  Particle _randomParticle() => Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.001 + _random.nextDouble() * 0.003,
        size: 1.5 + _random.nextDouble() * 3,
        opacity: 0.2 + _random.nextDouble() * 0.6,
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 更新粒子位置
        for (final p in _particles) {
          switch (widget.type) {
            case ParticleType.snow:
              p.y += p.speed;
              p.x += sin(p.y * 10) * 0.001;
            case ParticleType.stars:
              p.opacity = 0.2 + (sin(DateTime.now().millisecondsSinceEpoch *
                  0.001 * p.speed * 100) + 1) * 0.4;
            case ParticleType.hearts:
              p.y -= p.speed * 1.5;
              p.x += sin(p.y * 8) * 0.002;
            case ParticleType.firefly:
              p.x += sin(DateTime.now().millisecondsSinceEpoch *
                  0.0005 * p.speed * 50) * 0.003;
              p.y += cos(DateTime.now().millisecondsSinceEpoch *
                  0.0003 * p.speed * 50) * 0.002;
              p.opacity = 0.1 + (sin(DateTime.now().millisecondsSinceEpoch *
                  0.002 * p.speed * 100) + 1) * 0.4;
          }
          // 循环
          if (p.y > 1.1) { p.y = -0.1; p.x = _random.nextDouble(); }
          if (p.y < -0.1) { p.y = 1.1; p.x = _random.nextDouble(); }
          p.x = p.x % 1.0;
        }
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            type: widget.type,
            color: widget.color,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final ParticleType type;
  final Color color;

  _ParticlePainter({
    required this.particles,
    required this.type,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = color.withValues(alpha: p.opacity);

      final dx = p.x * size.width;
      final dy = p.y * size.height;

      switch (type) {
        case ParticleType.snow:
          canvas.drawCircle(Offset(dx, dy), p.size, paint);
        case ParticleType.stars:
          _drawStar(canvas, Offset(dx, dy), p.size, paint);
        case ParticleType.hearts:
          _drawHeart(canvas, Offset(dx, dy), p.size * 2, paint);
        case ParticleType.firefly:
          paint.maskFilter = MaskFilter.blur(BlurStyle.normal, p.size);
          canvas.drawCircle(Offset(dx, dy), p.size, paint);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final angle = (i * pi / 2);
      final x = center.dx + cos(angle) * radius;
      final y = center.dy + sin(angle) * radius;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
    // 简单十字星
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint..strokeWidth = 0.8,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      paint..strokeWidth = 0.8,
    );
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final w = size;
    final h = size;
    path.moveTo(center.dx, center.dy + h * 0.35);
    path.cubicTo(
      center.dx - w * 0.5, center.dy - h * 0.1,
      center.dx - w * 0.5, center.dy - h * 0.5,
      center.dx, center.dy - h * 0.2,
    );
    path.cubicTo(
      center.dx + w * 0.5, center.dy - h * 0.5,
      center.dx + w * 0.5, center.dy - h * 0.1,
      center.dx, center.dy + h * 0.35,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
