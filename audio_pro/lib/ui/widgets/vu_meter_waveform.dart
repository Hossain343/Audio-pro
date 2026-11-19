import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/cyber_theme.dart';

/// Real-time animated VU bar & dynamic waveform levelizer driven by native RMS/Peak audio.
class VuMeterWaveform extends StatefulWidget {
  const VuMeterWaveform({
    super.key,
    required this.rms,
    required this.peak,
    required this.isMuted,
    this.label,
    this.barCount = 28,
    this.height = 68,
  });

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
  double _phase = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(() {
        setState(() {
          _phase += 0.16;
        });
      });
    unawaited(_ticker.repeat());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _formatDbfs() {
    if (widget.isMuted) return 'MUTED';
    if (widget.rms <= 0.0001) return '-96.0 dBFS';
    final db = 20.0 * (math.log(widget.rms) / math.ln10);
    return '${db.clamp(-96.0, 0.0).toStringAsFixed(1)} dBFS';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRms = widget.isMuted ? 0.0 : widget.rms;
    final effectivePeak = widget.isMuted ? 0.0 : widget.peak;

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
              Text(
                _formatDbfs(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.isMuted
                      ? CyberTheme.crimsonOff
                      : CyberTheme.cyanAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _VuWaveformPainter(
              rms: effectiveRms,
              peak: effectivePeak,
              phase: _phase,
              barCount: widget.barCount,
              isMuted: widget.isMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _VuWaveformPainter extends CustomPainter {
  _VuWaveformPainter({
    required this.rms,
    required this.peak,
    required this.phase,
    required this.barCount,
    required this.isMuted,
  });

  final double rms;
  final double peak;
  final double phase;
  final int barCount;
  final bool isMuted;

  @override
  void paint(Canvas canvas, Size size) {
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
    return oldDelegate.rms != rms ||
        oldDelegate.peak != peak ||
        oldDelegate.phase != phase ||
        oldDelegate.isMuted != isMuted;
  }
}
