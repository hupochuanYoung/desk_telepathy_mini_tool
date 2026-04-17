import 'package:flutter/material.dart';

/// 对方的状态
enum PeerStatus {
  online('在线', Icons.circle, Colors.greenAccent),
  busy('忙碌中', Icons.local_fire_department, Colors.orangeAccent),
  focus('专注模式', Icons.nightlight_round, Colors.indigoAccent),
  offline('离线', Icons.circle_outlined, Colors.grey);

  final String label;
  final IconData icon;
  final Color color;
  const PeerStatus(this.label, this.icon, this.color);

  static PeerStatus fromCode(String code) {
    try {
      return PeerStatus.values.firstWhere((s) => s.name == code);
    } catch (_) {
      return PeerStatus.offline;
    }
  }
}

/// 状态指示器 — 显示在标题栏右侧
class StatusIndicator extends StatelessWidget {
  final PeerStatus status;

  const StatusIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '对方: ${status.label}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(color: status.color, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
