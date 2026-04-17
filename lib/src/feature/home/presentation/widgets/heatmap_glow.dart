import 'package:flutter/material.dart';

/// 互动热力图光晕 — 互动越多，光晕越亮越丰富
class HeatmapGlow extends StatelessWidget {
  /// 0.0 ~ 1.0 互动强度
  final double intensity;

  const HeatmapGlow({super.key, required this.intensity});

  @override
  Widget build(BuildContext context) {
    if (intensity <= 0) return const SizedBox.shrink();

    // 根据强度插值颜色：冷蓝 → 暖紫 → 热粉
    final color = Color.lerp(
      const Color(0xFF3B82F6), // 蓝
      const Color(0xFFEC4899), // 粉
      intensity,
    )!;

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(seconds: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.8,
              colors: [
                color.withValues(alpha: intensity * 0.15),
                color.withValues(alpha: intensity * 0.05),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
