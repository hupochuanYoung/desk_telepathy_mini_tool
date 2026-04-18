import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  runApp(const DigitalFlowerApp());
}

class DigitalFlowerApp extends StatelessWidget {
  const DigitalFlowerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Digital Flower Garden',
      theme: ThemeData.dark(useMaterial3: true),
      home: const DigitalFlowerPage(),
    );
  }
}

enum FlowerType {
  tulip,
  daisy,
  lily,
}

class DigitalFlowerPage extends StatefulWidget {
  const DigitalFlowerPage({super.key});

  @override
  State<DigitalFlowerPage> createState() => _DigitalFlowerPageState();
}

class _DigitalFlowerPageState extends State<DigitalFlowerPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<Bloom> _blooms = <Bloom>[];
  final math.Random _random = math.Random();
  double _time = 0;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(() {
        setState(() {
          _time += 0.016;
          for (final bloom in _blooms) {
            bloom.age += 0.016;
            bloom.petalDrift += 0.008 + bloom.energy * 0.003;
          }
          _blooms.removeWhere((bloom) => bloom.age > bloom.life);
        });
      })
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  FlowerType _randomFlowerType() {
    final v = _random.nextDouble();
    if (v < 0.34) return FlowerType.tulip;
    if (v < 0.68) return FlowerType.daisy;
    return FlowerType.lily;
  }

  void _spawnBloom(Offset position, {bool fromDrag = false}) {
    final hueBase =
        (position.dx / (_size.width == 0 ? 1 : _size.width)) * 360;
    final double energy = fromDrag
        ? 0.6 + _random.nextDouble() * 0.9
        : 0.9 + _random.nextDouble() * 1.2;

    final type = _randomFlowerType();

    int petalCount;
    double petalLength;
    double petalWidth;
    double coreRadius;
    Color bloomColor;
    Color glowColor;

    switch (type) {
      case FlowerType.tulip:
        petalCount = 3;
        petalLength = 20 + _random.nextDouble() * 16;
        petalWidth = 14 + _random.nextDouble() * 10;
        coreRadius = 5 + _random.nextDouble() * 4;
        bloomColor = HSVColor.fromAHSV(
          1,
          (330 + _random.nextDouble() * 35) % 360,
          0.50 + _random.nextDouble() * 0.22,
          0.92 + _random.nextDouble() * 0.06,
        ).toColor();
        glowColor = HSVColor.fromAHSV(
          1,
          (hueBase + 330 + _random.nextDouble() * 30) % 360,
          0.24,
          1,
        ).toColor();
        break;
      case FlowerType.daisy:
        petalCount = 10 + _random.nextInt(5);
        petalLength = 13 + _random.nextDouble() * 10;
        petalWidth = 5 + _random.nextDouble() * 4;
        coreRadius = 6 + _random.nextDouble() * 4;
        bloomColor = HSVColor.fromAHSV(
          1,
          52 + _random.nextDouble() * 16,
          0.12 + _random.nextDouble() * 0.10,
          0.98,
        ).toColor();
        glowColor = HSVColor.fromAHSV(
          1,
          48 + _random.nextDouble() * 20,
          0.20,
          1,
        ).toColor();
        break;
      case FlowerType.lily:
        petalCount = 6;
        petalLength = 22 + _random.nextDouble() * 18;
        petalWidth = 10 + _random.nextDouble() * 8;
        coreRadius = 4 + _random.nextDouble() * 3;
        bloomColor = HSVColor.fromAHSV(
          1,
          (280 + _random.nextDouble() * 60) % 360,
          0.18 + _random.nextDouble() * 0.18,
          0.98,
        ).toColor();
        glowColor = HSVColor.fromAHSV(
          1,
          (hueBase + 260 + _random.nextDouble() * 60) % 360,
          0.16,
          1,
        ).toColor();
        break;
    }

    _blooms.add(
      Bloom(
        type: type,
        position: position,
        stemHeight: 60 + _random.nextDouble() * 120,
        stemBend: -28 + _random.nextDouble() * 56,
        petalCount: petalCount,
        petalLength: petalLength,
        petalWidth: petalWidth,
        coreRadius: coreRadius,
        rotationSeed: _random.nextDouble() * math.pi * 2,
        age: 0,
        life: 12 + _random.nextDouble() * 12,
        energy: energy,
        petalDrift: _random.nextDouble() * math.pi * 2,
        stemColor:
        HSVColor.fromAHSV(1, 118 + _random.nextDouble() * 24, 0.45, 0.65)
            .toColor(),
        bloomColor: bloomColor,
        glowColor: glowColor,
      ),
    );
  }

  void _seedGarden() {
    if (_size == Size.zero || _blooms.isNotEmpty) return;
    for (int i = 0; i < 9; i++) {
      final dx = 40 + _random.nextDouble() * (_size.width - 80);
      final dy = _size.height * (0.45 + _random.nextDouble() * 0.4);
      _spawnBloom(Offset(dx, dy));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          _size = Size(constraints.maxWidth, constraints.maxHeight);
          WidgetsBinding.instance.addPostFrameCallback((_) => _seedGarden());

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _spawnBloom(details.localPosition),
            onPanUpdate: (details) {
              if (_random.nextDouble() < 0.38) {
                _spawnBloom(details.localPosition, fromDrag: true);
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: GardenPainter(
                      blooms: _blooms,
                      time: _time,
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Digital Flower Garden',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                            color: Colors.white.withOpacity(0.92),
                            fontWeight: FontWeight.w300,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '点击开花，拖动会长出一串电子花枝。\n现在会随机生成郁金香、小雏菊和百合。',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                            color: Colors.white.withOpacity(0.65),
                            height: 1.5,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            _GlassTag(label: 'interactive'),
                            const SizedBox(width: 10),
                            _GlassTag(label: 'tulip / daisy / lily'),
                            const SizedBox(width: 10),
                            _GlassTag(label: '${_blooms.length} blooms'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GlassTag extends StatelessWidget {
  const _GlassTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.78),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class Bloom {
  Bloom({
    required this.type,
    required this.position,
    required this.stemHeight,
    required this.stemBend,
    required this.petalCount,
    required this.petalLength,
    required this.petalWidth,
    required this.coreRadius,
    required this.rotationSeed,
    required this.age,
    required this.life,
    required this.energy,
    required this.petalDrift,
    required this.stemColor,
    required this.bloomColor,
    required this.glowColor,
  });

  final FlowerType type;
  final Offset position;
  final double stemHeight;
  final double stemBend;
  final int petalCount;
  final double petalLength;
  final double petalWidth;
  final double coreRadius;
  final double rotationSeed;
  final double life;
  final double energy;
  final Color stemColor;
  final Color bloomColor;
  final Color glowColor;

  double age;
  double petalDrift;
}

class GardenPainter extends CustomPainter {
  GardenPainter({required this.blooms, required this.time});

  final List<Bloom> blooms;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintMist(canvas, size);

    for (final bloom in blooms) {
      _paintStem(canvas, bloom);
    }

    for (final bloom in blooms) {
      _paintGlow(canvas, bloom);
      _paintFlower(canvas, bloom);
      _paintFloatingPetals(canvas, bloom);
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF090A12),
        const Color(0xFF12192A),
        const Color(0xFF1C1130),
        const Color(0xFF0D1320),
      ],
      stops: const [0, 0.35, 0.72, 1],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  void _paintMist(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final positions = <Offset>[
      Offset(size.width * 0.18, size.height * 0.22),
      Offset(size.width * 0.82, size.height * 0.18),
      Offset(size.width * 0.52, size.height * 0.72),
    ];
    final radii = <double>[180, 160, 220];
    final colors = <Color>[
      const Color(0x2236D6C8),
      const Color(0x22FF72B6),
      const Color(0x224B7BFF),
    ];

    for (int i = 0; i < positions.length; i++) {
      paint.shader = RadialGradient(
        colors: [colors[i], Colors.transparent],
      ).createShader(Rect.fromCircle(center: positions[i], radius: radii[i]));
      canvas.drawCircle(positions[i], radii[i], paint);
    }
  }

  void _paintStem(Canvas canvas, Bloom bloom) {
    final t = (bloom.age / bloom.life).clamp(0.0, 1.0);
    final grow = Curves.easeOutCubic.transform(math.min(t * 1.8, 1.0));
    final sway = math.sin(time * 0.8 + bloom.rotationSeed) * 8 * bloom.energy;

    final start = bloom.position;
    final end = Offset(
      bloom.position.dx + sway,
      bloom.position.dy - bloom.stemHeight * grow,
    );
    final control = Offset(
      bloom.position.dx + bloom.stemBend + sway * 0.6,
      bloom.position.dy - bloom.stemHeight * 0.58 * grow,
    );

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

    final stemPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 + bloom.energy * 1.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          bloom.stemColor.withOpacity(0.05),
          bloom.stemColor.withOpacity(0.95),
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      ).createShader(Rect.fromPoints(start, end));

    canvas.drawPath(path, stemPaint);

    final leafPaint = Paint()
      ..color = bloom.stemColor.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final leafAnchor = _quadraticPoint(start, control, end, 0.58);
    final leafDir = (end - start).direction + math.pi / 2.8;
    _drawLeaf(canvas, leafAnchor, 18 + bloom.energy * 8, leafDir, leafPaint);
    _drawLeaf(canvas, leafAnchor.translate(-4, 10), 13 + bloom.energy * 6,
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

  void _paintGlow(Canvas canvas, Bloom bloom) {
    final center = _flowerCenter(bloom);
    final pulse = 0.78 + math.sin(time * 1.6 + bloom.rotationSeed) * 0.12;
    final radius = (bloom.petalLength * 2.2 + bloom.energy * 20) * pulse;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          bloom.glowColor.withOpacity(0.24),
          bloom.glowColor.withOpacity(0.08),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  void _paintFlower(Canvas canvas, Bloom bloom) {
    final center = _flowerCenter(bloom);
    final open =
    Curves.easeOutBack.transform(math.min((bloom.age / bloom.life) * 2.2, 1.0));
    final pulse =
        1 + math.sin(time * (1.2 + bloom.energy * 0.3) + bloom.rotationSeed) * 0.06;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bloom.rotationSeed + math.sin(time + bloom.rotationSeed) * 0.08);
    canvas.scale(open * pulse);

    switch (bloom.type) {
      case FlowerType.tulip:
        _paintTulipShape(canvas, bloom);
        break;
      case FlowerType.daisy:
        _paintDaisyShape(canvas, bloom, time);
        break;
      case FlowerType.lily:
        _paintLilyShape(canvas, bloom, time);
        break;
    }

    canvas.restore();
  }

  void _paintTulipShape(Canvas canvas, Bloom bloom) {
    final petalPaint = Paint()..style = PaintingStyle.fill;
    final light = Color.lerp(bloom.bloomColor, Colors.white, 0.28)!;
    final dark = Color.lerp(bloom.bloomColor, Colors.black, 0.18)!;

    void drawPetal(double dx, double tipY, double widthScale) {
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(
          bloom.petalWidth * widthScale + dx,
          -bloom.petalLength * 0.18,
          dx,
          tipY,
        )
        ..quadraticBezierTo(
          -bloom.petalWidth * widthScale + dx,
          -bloom.petalLength * 0.18,
          0,
          0,
        );

      petalPaint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [dark.withOpacity(0.92), bloom.bloomColor, light],
      ).createShader(
        Rect.fromLTWH(
          -bloom.petalWidth * 1.4,
          -bloom.petalLength * 1.3,
          bloom.petalWidth * 2.8,
          bloom.petalLength * 1.4,
        ),
      );
      canvas.drawPath(path, petalPaint);
    }

    drawPetal(-bloom.petalWidth * 0.45, -bloom.petalLength * 0.88, 0.95);
    drawPetal(bloom.petalWidth * 0.45, -bloom.petalLength * 0.88, 0.95);
    drawPetal(0, -bloom.petalLength * 1.08, 1.05);

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.75),
          bloom.glowColor.withOpacity(0.5),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: bloom.coreRadius * 2.4));
    canvas.drawCircle(const Offset(0, -2), bloom.coreRadius, corePaint);
  }

  void _paintDaisyShape(Canvas canvas, Bloom bloom, double time) {
    final petalPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < bloom.petalCount; i++) {
      final angle = (math.pi * 2 / bloom.petalCount) * i;
      final wobble = math.sin(time * 1.4 + i + bloom.rotationSeed) * 0.06;
      canvas.save();
      canvas.rotate(angle + wobble);

      final petalPath = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(
          bloom.petalWidth,
          -bloom.petalLength * 0.08,
          0,
          -bloom.petalLength,
        )
        ..quadraticBezierTo(
          -bloom.petalWidth,
          -bloom.petalLength * 0.08,
          0,
          0,
        );

      petalPaint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          const Color(0xFFF1EAFE).withOpacity(0.92),
          Colors.white.withOpacity(0.94),
          const Color(0xFFFFF6D7).withOpacity(0.22),
        ],
      ).createShader(
        Rect.fromLTWH(
          -bloom.petalWidth,
          -bloom.petalLength,
          bloom.petalWidth * 2,
          bloom.petalLength,
        ),
      );

      canvas.drawPath(petalPath, petalPaint);
      canvas.restore();
    }

    final coreColor = const Color(0xFFFFD75E);
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.9),
          coreColor,
          const Color(0xFFFFB72B),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: bloom.coreRadius * 2.4));

    canvas.drawCircle(Offset.zero, bloom.coreRadius * 1.45, corePaint);
  }

  void _paintLilyShape(Canvas canvas, Bloom bloom, double time) {
    final petalPaint = Paint()..style = PaintingStyle.fill;
    final base = Color.lerp(bloom.bloomColor, Colors.white, 0.38)!;
    final edge = Color.lerp(bloom.bloomColor, const Color(0xFFD59BFF), 0.45)!;

    for (int i = 0; i < 6; i++) {
      final angle = (math.pi * 2 / 6) * i;
      final wobble = math.sin(time * 1.2 + i + bloom.rotationSeed) * 0.05;
      canvas.save();
      canvas.rotate(angle + wobble);

      final petalPath = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(
          bloom.petalWidth * 0.95,
          -bloom.petalLength * 0.22,
          0,
          -bloom.petalLength,
        )
        ..quadraticBezierTo(
          -bloom.petalWidth * 0.95,
          -bloom.petalLength * 0.22,
          0,
          0,
        );

      petalPaint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [edge.withOpacity(0.78), base, Colors.white.withOpacity(0.88)],
      ).createShader(
        Rect.fromLTWH(
          -bloom.petalWidth,
          -bloom.petalLength,
          bloom.petalWidth * 2,
          bloom.petalLength,
        ),
      );

      canvas.drawPath(petalPath, petalPaint);

      final dotPaint = Paint()
        ..color = const Color(0xFFB74B9A).withOpacity(0.22);
      for (int j = 0; j < 4; j++) {
        final yy = -bloom.petalLength * (0.28 + j * 0.13);
        final xx = math.sin(j * 1.7 + i) * bloom.petalWidth * 0.22;
        canvas.drawCircle(Offset(xx, yy), 1.1 + j * 0.2, dotPaint);
      }

      canvas.restore();
    }

    final filamentPaint = Paint()
      ..color = const Color(0xFFFFE4A8).withOpacity(0.85)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final a = -0.25 + i * 0.25;
      final end = Offset(math.sin(a) * 8, -bloom.coreRadius * 2.2 - i * 2);
      canvas.drawLine(Offset.zero, end, filamentPaint);
      canvas.drawCircle(end, 1.8, Paint()..color = const Color(0xFFFFA94D));
    }
  }

  void _paintFloatingPetals(Canvas canvas, Bloom bloom) {
    final center = _flowerCenter(bloom);
    final paint = Paint()..style = PaintingStyle.fill;
    final particleCount = 3 + (bloom.energy * 2).floor();

    for (int i = 0; i < particleCount; i++) {
      final shift = bloom.petalDrift + i * 1.7;
      final dx = math.cos(shift) * (8 + i * 6) + math.sin(time * 0.7 + i) * 4;
      final dy = math.sin(shift * 1.2) * 10 + (bloom.age * 8) % 28;
      final petalCenter = center.translate(dx, dy);
      final angle = shift + math.sin(time + i) * 0.3;
      final opacity = (0.16 - i * 0.02).clamp(0.04, 0.16);

      canvas.save();
      canvas.translate(petalCenter.dx, petalCenter.dy);
      canvas.rotate(angle);

      final path = Path();
      switch (bloom.type) {
        case FlowerType.tulip:
          path
            ..moveTo(0, 0)
            ..quadraticBezierTo(5.5, -1.8, 0, -11)
            ..quadraticBezierTo(-5.5, -1.8, 0, 0);
          paint.color = bloom.bloomColor.withOpacity(opacity);
          break;
        case FlowerType.daisy:
          path
            ..moveTo(0, 0)
            ..quadraticBezierTo(3.5, -1.0, 0, -8)
            ..quadraticBezierTo(-3.5, -1.0, 0, 0);
          paint.color = Colors.white.withOpacity(opacity + 0.03);
          break;
        case FlowerType.lily:
          path
            ..moveTo(0, 0)
            ..quadraticBezierTo(4.5, -1.6, 0, -10)
            ..quadraticBezierTo(-4.5, -1.6, 0, 0);
          paint.color = bloom.bloomColor.withOpacity(opacity);
          break;
      }

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  Offset _flowerCenter(Bloom bloom) {
    final t = (bloom.age / bloom.life).clamp(0.0, 1.0);
    final grow = Curves.easeOutCubic.transform(math.min(t * 1.8, 1.0));
    final sway = math.sin(time * 0.8 + bloom.rotationSeed) * 8 * bloom.energy;
    return Offset(
      bloom.position.dx + sway,
      bloom.position.dy - bloom.stemHeight * grow,
    );
  }

  Offset _quadraticPoint(Offset p0, Offset p1, Offset p2, double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * p0.dx + 2 * mt * t * p1.dx + t * t * p2.dx,
      mt * mt * p0.dy + 2 * mt * t * p1.dy + t * t * p2.dy,
    );
  }

  @override
  bool shouldRepaint(covariant GardenPainter oldDelegate) {
    return true;
  }
}
