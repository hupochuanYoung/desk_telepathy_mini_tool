import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/service/location_service.dart';

/// 中央地球（一颗会旋转的线框地球）。
///
/// * [focal] 变化时，球体以缓动曲线旋转，把该经纬度转到屏幕中心（正对观察者）。
/// * [activity] 0..1 控制大气光晕与边缘高光的强度，保持和整体氛围联动。
/// * [rippleTrigger] 每 +1 就在焦点处扩散一圈水滴波纹，作为"被点到了"的轻反馈。
///
/// 旋转逻辑（屏幕坐标下 y 向下）：
///   世界点 (lat, lon) → (cos(lat)·sin(lon), -sin(lat), cos(lat)·cos(lon))
///   绕 Y 转 -lon，再绕 X 转 -lat —— 恰好把 (lat, lon) 送到 (0, 0, 1) 正对摄像机。
class InterferenceGlobe extends StatefulWidget {
  const InterferenceGlobe({
    super.key,
    this.focal,
    required this.activity,
    this.rippleTrigger,
    this.primary = const Color(0xFF67E8F9), // cyan-300
    this.secondary = const Color(0xFFA78BFA), // violet-400
    this.size = 130,
  });

  final LocationInfo? focal;
  final double activity;
  final int? rippleTrigger;
  final Color primary;
  final Color secondary;
  final double size;

  @override
  State<InterferenceGlobe> createState() => _InterferenceGlobeState();
}

class _InterferenceGlobeState extends State<InterferenceGlobe>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _now = Duration.zero;

  // 当前展示的球体朝向 & tween 的起点 / 终点（均为弧度）
  double _lat = 0, _lon = 0;
  double _fromLat = 0, _fromLon = 0;
  double _toLat = 0, _toLon = 0;
  Duration _tweenStart = Duration.zero;
  static const Duration _tweenDur = Duration(milliseconds: 900);

  // 用于驱动焦点标记的脉冲呼吸
  double _pulsePhase = 0;

  // 焦点处扩散的水滴波纹
  final List<Duration> _ripples = [];
  int? _lastRippleTrigger;

  @override
  void initState() {
    super.initState();
    _lastRippleTrigger = widget.rippleTrigger;
    _seedFocal();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant InterferenceGlobe old) {
    super.didUpdateWidget(old);
    if (_focalChanged(old.focal, widget.focal)) _retargetFocal();
    if (widget.rippleTrigger != null &&
        widget.rippleTrigger != _lastRippleTrigger) {
      _lastRippleTrigger = widget.rippleTrigger;
      _ripples.add(_now);
      if (_ripples.length > 6) _ripples.removeAt(0);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ─── focal helpers ─────────────────────────────────────────

  bool _focalChanged(LocationInfo? a, LocationInfo? b) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    return a.lat != b.lat || a.lon != b.lon;
  }

  /// 第一次出现 focal 时不做 tween，直接定位 —— 避免冷启动时一下子转 180°。
  void _seedFocal() {
    final f = widget.focal;
    if (f == null || f.lat == null || f.lon == null) return;
    _lat = _fromLat = _toLat = f.lat! * math.pi / 180;
    _lon = _fromLon = _toLon = f.lon! * math.pi / 180;
  }

  void _retargetFocal() {
    final f = widget.focal;
    if (f == null || f.lat == null || f.lon == null) return;
    _fromLat = _lat;
    _fromLon = _lon;
    _toLat = f.lat! * math.pi / 180;
    var toLon = f.lon! * math.pi / 180;
    // 经度差走最短路径，避免 170° 和 -170° 之间绕远
    while (toLon - _fromLon > math.pi) {
      toLon -= 2 * math.pi;
    }
    while (toLon - _fromLon < -math.pi) {
      toLon += 2 * math.pi;
    }
    _toLon = toLon;
    _tweenStart = _now;
  }

  // ─── ticker ─────────────────────────────────────────

  void _onTick(Duration now) {
    final dt = _now == Duration.zero
        ? 0.0
        : (now - _now).inMicroseconds / 1e6;
    _now = now;

    // 缓慢脉冲（焦点标记的呼吸）
    _pulsePhase += dt * 0.6;

    // 旋转 tween
    final elapsed = (_now - _tweenStart).inMicroseconds.toDouble();
    final total = _tweenDur.inMicroseconds.toDouble();
    final t = total <= 0 ? 1.0 : (elapsed / total).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(t);
    _lat = _fromLat + (_toLat - _fromLat) * eased;
    _lon = _fromLon + (_toLon - _fromLon) * eased;

    // 老化水滴波纹
    _ripples.removeWhere(
      (r) => (_now - r).inMilliseconds > 1800,
    );

    setState(() {});
  }

  // ─── build ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasFocal = widget.focal != null &&
        widget.focal!.lat != null &&
        widget.focal!.lon != null;
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _GlobePainter(
          lat: _lat,
          lon: _lon,
          activity: widget.activity.clamp(0.0, 1.0),
          pulsePhase: _pulsePhase,
          rippleAges: _ripples
              .map((r) => (_now - r).inMicroseconds / 1e6)
              .toList(growable: false),
          primary: widget.primary,
          secondary: widget.secondary,
          hasFocal: hasFocal,
        ),
      ),
    );
  }
}

// ──────────────────────────── Painter ────────────────────────────

class _GlobePainter extends CustomPainter {
  _GlobePainter({
    required this.lat,
    required this.lon,
    required this.activity,
    required this.pulsePhase,
    required this.rippleAges,
    required this.primary,
    required this.secondary,
    required this.hasFocal,
  });

  final double lat;
  final double lon;
  final double activity;
  final double pulsePhase;
  final List<double> rippleAges; // 秒
  final Color primary;
  final Color secondary;
  final bool hasFocal;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;

    _paintAtmosphere(canvas, c, r);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    _paintSphereBody(canvas, c, r);
    _paintGrid(canvas, c, r);

    // 收到互动时的水滴波纹 —— 从焦点（屏幕中心）扩散
    if (hasFocal) _paintRipples(canvas, c, r);

    canvas.restore();

    // 外圈柔光描边（在 clip 外画，避免被裁）
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = primary.withValues(alpha: 0.28 + activity * 0.35),
    );

    if (hasFocal) _paintFocalMarker(canvas, c, r);
  }

  // 大气光晕
  void _paintAtmosphere(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
      c,
      r * 1.22,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: 0.22),
            primary.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const [0.6, 0.85, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.22)),
    );
  }

  // 球体本体 —— 左上偏亮的径向渐变
  void _paintSphereBody(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          radius: 1.0,
          colors: const [
            Color(0xFF1E3A5C),
            Color(0xFF0A1A2E),
            Color(0xFF050B18),
          ],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  // ── 3D 旋转 ──────────────────

  // 世界坐标：x 右、y 下（屏幕坐标）、z 指向观察者
  _Vec3 _worldPoint(double latRad, double lonRad) => _Vec3(
        math.cos(latRad) * math.sin(lonRad),
        -math.sin(latRad),
        math.cos(latRad) * math.cos(lonRad),
      );

  // 把世界点绕 Y(-lon)、再绕 X(-lat) 两步旋转到相机空间
  _Vec3 _toCamera(_Vec3 p) {
    final cL = math.cos(lon), sL = math.sin(lon);
    final qx = p.x * cL - p.z * sL;
    final qy = p.y;
    final qz = p.x * sL + p.z * cL;
    final cT = math.cos(lat), sT = math.sin(lat);
    return _Vec3(qx, qy * cT + qz * sT, -qy * sT + qz * cT);
  }

  // ── 经纬网 ──────────────────

  void _paintGrid(Canvas canvas, Offset c, double r) {
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55
      ..color = primary.withValues(alpha: 0.22);
    final equatorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = primary.withValues(alpha: 0.38);

    // 纬度：-60, -30, 0, 30, 60
    for (double deg = -60; deg <= 60; deg += 30) {
      _traceSphereCurve(
        canvas: canvas,
        c: c,
        r: r,
        segments: 72,
        paint: deg == 0 ? equatorPaint : basePaint,
        world: (i, n) {
          final lonRad = i * 2 * math.pi / n;
          return _worldPoint(deg * math.pi / 180, lonRad);
        },
      );
    }

    // 经度：每 30° 一条
    for (int k = 0; k < 12; k++) {
      final lonRad = k * math.pi / 6;
      _traceSphereCurve(
        canvas: canvas,
        c: c,
        r: r,
        segments: 64,
        paint: basePaint,
        world: (i, n) {
          final latRad = -math.pi / 2 + i * math.pi / n;
          return _worldPoint(latRad, lonRad);
        },
      );
    }
  }

  /// 沿球面采样、只把 z>0 的正面段落连成 path —— 拐入背面就断开。
  void _traceSphereCurve({
    required Canvas canvas,
    required Offset c,
    required double r,
    required int segments,
    required Paint paint,
    required _Vec3 Function(int i, int n) world,
  }) {
    final path = Path();
    bool drawing = false;
    for (int i = 0; i <= segments; i++) {
      final v = _toCamera(world(i, segments));
      if (v.z > 0) {
        final sx = c.dx + v.x * r;
        final sy = c.dy + v.y * r;
        if (!drawing) {
          path.moveTo(sx, sy);
          drawing = true;
        } else {
          path.lineTo(sx, sy);
        }
      } else {
        drawing = false;
      }
    }
    canvas.drawPath(path, paint);
  }

  // ── 水滴扩散 ─────────────────

  void _paintRipples(Canvas canvas, Offset c, double r) {
    for (final ageSec in rippleAges) {
      final t = (ageSec / 1.5).clamp(0.0, 1.0);
      if (t >= 1) continue;
      final rr = r * Curves.easeOut.transform(t);
      final alpha = (1 - t) * 0.55;
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = primary.withValues(alpha: alpha),
      );
    }
  }

  // ── 焦点标记（脉冲光点） ─────────────────

  void _paintFocalMarker(Canvas canvas, Offset c, double r) {
    final pulse = pulsePhase % 1.0;
    final haloR = 3.0 + activity * 1.0 + pulse * 4.0;
    final haloAlpha = (1 - pulse).clamp(0.0, 1.0) * 0.55;
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..color = primary.withValues(alpha: haloAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final centerColor = Color.lerp(secondary, primary, activity)!;
    canvas.drawCircle(
      c,
      2.4 + activity * 1.3,
      Paint()..color = centerColor.withValues(alpha: 0.95),
    );
    // 中心白色小高光
    canvas.drawCircle(
      c.translate(-0.6, -0.6),
      1.0,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) => true;
}

class _Vec3 {
  final double x;
  final double y;
  final double z;
  const _Vec3(this.x, this.y, this.z);
}
