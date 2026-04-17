import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/service/app_logger.dart';

/// 日志查看面板 —— 订阅 [AppLogger.stream]，自动 tail-follow 最新条目
class LogViewer extends StatefulWidget {
  const LogViewer({super.key});

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  late List<LogEntry> _entries;
  StreamSubscription<LogEntry>? _sub;
  final _scroll = ScrollController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _entries = List.of(AppLogger.history);
    _sub = AppLogger.stream.listen((e) {
      if (!mounted) return;
      setState(() => _entries = List.of(AppLogger.history));
      if (_follow) _scheduleScrollToBottom();
    });
    _scroll.addListener(_onUserScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleScrollToBottom());
  }

  void _onUserScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 8;
    if (_follow != atBottom) setState(() => _follow = atBottom);
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copyAll() async {
    final text = _entries.map((e) => e.toString()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志已复制'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.terminal, size: 14, color: Colors.white.withValues(alpha: 0.6)),
            const SizedBox(width: 6),
            Text(
              '日志 (${_entries.length})',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
            ),
            const Spacer(),
            _IconBtn(
              icon: _follow ? Icons.vertical_align_bottom : Icons.pause_circle_outline,
              tooltip: _follow ? '自动滚动' : '已暂停，滚动到底部继续',
              onTap: () {
                setState(() => _follow = true);
                _scheduleScrollToBottom();
              },
            ),
            _IconBtn(icon: Icons.copy, tooltip: '复制全部', onTap: _copyAll),
            _IconBtn(
              icon: Icons.delete_outline,
              tooltip: '清空',
              onTap: () {
                AppLogger.clear();
                setState(() => _entries = []);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: _entries.isEmpty
                ? Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _entries.length,
                    itemBuilder: (_, i) => _LogLine(entry: _entries[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  final LogEntry entry;

  const _LogLine({required this.entry});

  Color get _levelColor {
    switch (entry.level) {
      case LogLevel.debug:
        return Colors.white.withValues(alpha: 0.5);
      case LogLevel.info:
        return Colors.lightBlueAccent;
      case LogLevel.warn:
        return Colors.amberAccent;
      case LogLevel.error:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, height: 1.3),
          children: [
            TextSpan(
              text: entry.formattedTime,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: entry.level.name.toUpperCase().padRight(5),
              style: TextStyle(color: _levelColor, fontWeight: FontWeight.w600),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: entry.tag,
              style: TextStyle(color: Colors.purpleAccent.withValues(alpha: 0.9)),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: entry.message,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
