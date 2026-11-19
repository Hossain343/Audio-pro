import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/audio_device.dart';
import '../theme/cyber_theme.dart';

/// Real-time animated VU bar & dynamic waveform levelizer driven by native RMS/Peak audio.
/// Uses CustomPainter's repaint listenable + RepaintBoundary so animations run smoothly
/// without triggering widget tree rebuilds or starving touch/scroll handling.
class VuMeterWaveform extends StatefulWidget {
  const VuMeterWaveform({
    super.key,
    this.vuListenable,
    this.useOutputLevel = false,
    this.rms = 0.0,
    this.peak = 0.0,
    required this.isMuted,
    this.label,
    this.barCount = 28,
    this.height = 68,
  });

  final ValueListenable<AudioVuSnapshot>? vuListenable;
  final bool useOutputLevel;
  final double rms;
  final double peak;
  final bool isMuted;
  final String? label;
  final int barCount;
  final double height;

  @override
  State<VuMeterWaveform> createState() => _VuMeterWaveformState();
}

class _VuMeterWaveformState extends State<VuMeterWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late Listenable _repaintListenable;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _updateRepaintListenable();
    unawaited(_ticker.repeat());
  }

  @override
  void didUpdateWidget(covariant VuMeterWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vuListenable != widget.vuListenable) {
      _updateRepaintListenable();
    }
  }

  void _updateRepaintListenable() {
    final vu = widget.vuListenable;
    _repaintListenable = vu != null
        ? Listenable.merge(<Listenable>[_ticker, vu])
        : _ticker;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _formatDbfs(double rawRms) {
    if (widget.isMuted) return 'MUTED';
    if (rawRms <= 0.0001) return '-96.0 dBFS';
    final db = 20.0 * (math.log(rawRms) / math.ln10);
    return '${db.clamp(-96.0, 0.0).toStringAsFixed(1)} dBFS';
  }

  Widget _buildDbfsText(double rawRms) {
    return Text(
      _formatDbfs(rawRms),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: widget.isMuted ? CyberTheme.crimsonOff : CyberTheme.cyanAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.label != null) ...<Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                widget.label!,
                style: const TextStyle(
                  fontSize: 11,
                  color: CyberTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.vuListenable != null)
                ValueListenableBuilder<AudioVuSnapshot>(
                  valueListenable: widget.vuListenable!,
                  builder: (context, snapshot, _) {
                    final activeRms = widget.useOutputLevel
                        ? snapshot.outputRms
                        : snapshot.inputRms;
                    return _buildDbfsText(activeRms);
                  },
                )
              else
                _buildDbfsText(widget.rms),
            ],
          ),
          const SizedBox(height: 6),
        ],
        RepaintBoundary(
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _VuWaveformPainter(
                repaint: _repaintListenable,
                ticker: _ticker,
                vuListenable: widget.vuListenable,
                useOutputLevel: widget.useOutputLevel,
                fallbackRms: widget.rms,
                fallbackPeak: widget.peak,
                barCount: widget.barCount,
                isMuted: widget.isMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VuWaveformPainter extends CustomPainter {
  _VuWaveformPainter({
    required Listenable repaint,
    required this.ticker,
    required this.vuListenable,
    required this.useOutputLevel,
    required this.fallbackRms,
    required this.fallbackPeak,
    required this.barCount,
    required this.isMuted,
  }) : super(repaint: repaint);

  final Animation<double> ticker;
  final ValueListenable<AudioVuSnapshot>? vuListenable;
  final bool useOutputLevel;
  final double fallbackRms;
  final double fallbackPeak;
  final int barCount;
  final bool isMuted;

  @override
  void paint(Canvas canvas, Size size) {
    final snapshot = vuListenable?.value;
    final double rawRms = snapshot != null
        ? (useOutputLevel ? snapshot.outputRms : snapshot.inputRms)
        : fallbackRms;
    final double rawPeak = snapshot != null
        ? (useOutputLevel ? snapshot.outputRms : snapshot.inputPeak)
        : fallbackPeak;

    final rms = isMuted ? 0.0 : rawRms;
    final peak = isMuted ? 0.0 : rawPeak;
    final phase = ticker.value * math.pi * 2.0;

    const barSpacing = 4.0;
    final totalSpacing = barSpacing * (barCount - 1);
    final barWidth = ((size.width - totalSpacing) / barCount).clamp(2.0, 14.0);
    final midY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final normIdx = i / (barCount - 1);
      final envelope = math.sin(normIdx * math.pi);
      final ripple = 0.65 + 0.35 * math.sin(phase + i * 0.55);
      final amplitude = isMuted
          ? 0.05
          : ((rms * 1.45 * envelope * ripple) + (peak * 0.25 * envelope))
              .clamp(0.06, 1.0);

      final barHeight = amplitude * (size.height - 8);
      final x = i * (barWidth + barSpacing);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, midY),
          width: barWidth,
          height: barHeight,
        ),
        const Radius.circular(3),
      );

      final Color color;
      if (isMuted) {
        color = CyberTheme.textMuted.withAlpha(90);
      } else if (amplitude > 0.85) {
        color = CyberTheme.crimsonOff;
      } else if (amplitude > 0.62) {
        color = CyberTheme.amberWait;
      } else {
        color = CyberTheme.cyanAccent;
      }

      final paint = Paint()..color = color;
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VuWaveformPainter oldDelegate) {
    return oldDelegate.vuListenable != vuListenable ||
        oldDelegate.useOutputLevel != useOutputLevel ||
        oldDelegate.fallbackRms != fallbackRms ||
        oldDelegate.fallbackPeak != fallbackPeak ||
        oldDelegate.barCount != barCount ||
        oldDelegate.isMuted != isMuted;
  }
}
