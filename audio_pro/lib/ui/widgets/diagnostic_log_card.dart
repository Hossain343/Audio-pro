import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/audio_bridge_controller.dart';
import '../theme/cyber_theme.dart';

/// Temporary live diagnostic terminal card with a top-right Copy Logs button.
class DiagnosticLogCard extends StatefulWidget {
  const DiagnosticLogCard({
    super.key,
    required this.controller,
    this.boxHeight = 180,
  });

  final AudioBridgeController controller;
  final double boxHeight;

  @override
  State<DiagnosticLogCard> createState() => _DiagnosticLogCardState();
}

class _DiagnosticLogCardState extends State<DiagnosticLogCard> {
  final ScrollController _scrollController = ScrollController();
  bool _copied = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _copyLogs() async {
    final text = widget.controller.exportLogsText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      _copied = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostic logs copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _copied = false;
          });
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CyberTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CyberTheme.borderHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.terminal_rounded,
                size: 16,
                color: CyberTheme.cyanAccent,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'DIAGNOSTIC LOGS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    color: CyberTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: widget.controller.clearLogs,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 15,
                  color: CyberTheme.textSecondary,
                ),
                label: const Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 11,
                    color: CyberTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () => unawaited(_copyLogs()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _copied ? CyberTheme.emeraldOk : CyberTheme.cyanAccent,
                  side: BorderSide(
                    color: _copied ? CyberTheme.emeraldOk : CyberTheme.borderHairline,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 14,
                ),
                label: Text(
                  _copied ? 'Copied!' : 'Copy Logs',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: widget.boxHeight,
            decoration: BoxDecoration(
              color: CyberTheme.bgVoid,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: CyberTheme.borderHairline),
            ),
            child: ValueListenableBuilder<List<String>>(
              valueListenable: widget.controller.logNotifier,
              builder: (context, logs, _) {
                if (logs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Waiting for USB, permission, socket & audio events...',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: CyberTheme.textMuted,
                      ),
                    ),
                  );
                }
                return Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(10),
                    reverse: true,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final line = logs[logs.length - 1 - index];
                      final isErr = line.contains('ERR') ||
                          line.contains('fail') ||
                          line.contains('DENIED') ||
                          line.contains('Busy') ||
                          line.contains('unreachable');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            fontFamily: 'monospace',
                            color: isErr
                                ? CyberTheme.amberWait
                                : CyberTheme.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
