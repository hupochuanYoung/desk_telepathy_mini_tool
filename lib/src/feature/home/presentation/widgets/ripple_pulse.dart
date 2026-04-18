import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 水滴波纹 —— 收到消息时从中心向外扩散几层同心圆
///
/// 用 [trigger] 作为 key/标识，每次变化重启动画
class RipplePulse extends StatefulWidget {
  final Object? trigger;
  final Color color;
  final Duration duration;

  const RipplePulse({
    super.key,
    required this.trigger,
    required this.color,
    this.duration = const Duration(milliseconds: 1600),
  });

  @override
  State<RipplePulse> createState() => _RipplePulseState();
}

class _RipplePulseState extends State<RipplePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (widget.trigger != null) _ctrl.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant RipplePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && widget.trigger != null) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _RipplePainter(_ctrl.value, widget.color),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double t;
  final Color color;

  _RipplePainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0) return;
    final center = size.center(Offset.zero);
    final maxR = math.min(size.width, size.height) * 0.55;

    for (int i = 0; i < 3; i++) {
      final delay = i * 0.18;
      final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local == 0) continue;
      final eased = Curves.easeOutCubic.transform(local);
      final r = maxR * eased;
      final alpha = (1 - local) * 0.55;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * (1 - local * 0.5)
        ..color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.t != t || old.color != color;
}
