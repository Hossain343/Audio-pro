import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio_device.dart';
import '../../services/audio_bridge_controller.dart';
import '../theme/cyber_theme.dart';
import '../widgets/vu_meter_waveform.dart';

class DesktopReceiverScreen extends StatefulWidget {
  const DesktopReceiverScreen({
    super.key,
    required this.controller,
  });

  final AudioBridgeController controller;

  @override
  State<DesktopReceiverScreen> createState() => _DesktopReceiverScreenState();
}

class _DesktopReceiverScreenState extends State<DesktopReceiverScreen> {
  late final TextEditingController _micNameController;
  late final TextEditingController _spkNameController;
  bool _appliedNotice = false;

  @override
  void initState() {
    super.initState();
    _micNameController = TextEditingController(
      text: widget.controller.virtualMicName,
    );
    _spkNameController = TextEditingController(
      text: widget.controller.virtualSpkName,
    );
  }

  @override
  void dispose() {
    _micNameController.dispose();
    _spkNameController.dispose();
    super.dispose();
  }

  Future<void> _applyEndpointNames() async {
    await widget.controller.applyVirtualEndpoints(
      micName: _micNameController.text,
      spkName: _spkNameController.text,
    );
    if (!mounted) return;
    setState(() {
      _appliedNotice = true;
    });
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _appliedNotice = false;
          });
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final statusColor = switch (controller.status) {
          BridgeConnectionStatus.connected => CyberTheme.emeraldOk,
          BridgeConnectionStatus.connecting => CyberTheme.amberWait,
          BridgeConnectionStatus.disconnected => CyberTheme.crimsonOff,
        };
        final statusLabel = switch (controller.status) {
          BridgeConnectionStatus.connected => 'USB Bridge Active',
          BridgeConnectionStatus.connecting => 'Listening for USB Phone...',
          BridgeConnectionStatus.disconnected => 'Host Offline',
        };
        final isConnected = controller.status == BridgeConnectionStatus.connected;

        return Scaffold(
          backgroundColor: CyberTheme.bgVoid,
          appBar: AppBar(
            title: const Text(
              'AudioPro · Windows Virtual Sound Card Host',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            actions: <Widget>[
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${controller.localDeviceName} · TCP:${controller.port}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: CyberTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: CyberTheme.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: controller.status == BridgeConnectionStatus.disconnected
                      ? controller.connectBridge
                      : controller.disconnectBridge,
                  icon: Icon(
                    controller.status == BridgeConnectionStatus.disconnected
                        ? Icons.play_arrow_rounded
                        : Icons.stop_rounded,
                  ),
                  label: Text(
                    controller.status == BridgeConnectionStatus.disconnected
                        ? 'Start Host'
                        : 'Stop Host',
                  ),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Connected Phone & Telemetry Strip
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: CyberTheme.bgSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CyberTheme.borderHairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  'CONNECTED PHONE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 1.1,
                                    color: CyberTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  controller.peerInfo.deviceName,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Transport: ${controller.peerInfo.transportLabel} · '
                                  '48 kHz / 16-bit PCM',
                                  style: const TextStyle(
                                    color: CyberTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (_appliedNotice) ...<Widget>[
                                const SizedBox(height: 6),
                                const Text(
                                  'Virtual device names updated',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: CyberTheme.emeraldOk,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: CyberTheme.borderHairline),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _TelemetryMetric(
                              label: 'TOTAL LATENCY',
                              value: isConnected
                                  ? '${controller.vuSnapshot.latencyMs.toStringAsFixed(1)} ms'
                                  : '—',
                              accent: true,
                            ),
                          ),
                          Expanded(
                            child: _TelemetryMetric(
                              label: 'JITTER BUFFER',
                              value: isConnected
                                  ? '${controller.vuSnapshot.jitterMs.toStringAsFixed(1)} ms'
                                  : '—',
                            ),
                          ),
                          Expanded(
                            child: _TelemetryMetric(
                              label: 'PCM STREAM',
                              value: isConnected
                                  ? '${controller.vuSnapshot.packetsPerSecond} pkt/s'
                                  : '0 pkt/s',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Virtual Driver Endpoints
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Virtual Microphone Card: Name input ONLY (Phone -> Windows)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: CyberTheme.bgSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CyberTheme.borderHairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  const Text(
                                    'VIRTUAL MICROPHONE (PHONE -> WINDOWS)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 1.1,
                                      color: CyberTheme.textMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: controller.toggleInputMute,
                                    tooltip: controller.isInputMuted
                                        ? 'Unmute Virtual Mic'
                                        : 'Mute Virtual Mic',
                                    icon: Icon(
                                      controller.isInputMuted
                                          ? Icons.mic_off_rounded
                                          : Icons.mic_rounded,
                                      size: 20,
                                      color: controller.isInputMuted
                                          ? CyberTheme.crimsonOff
                                          : CyberTheme.cyanAccent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Virtual Sound Card Microphone Name',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CyberTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: TextField(
                                      controller: _micNameController,
                                      onSubmitted: (_) => unawaited(_applyEndpointNames()),
                                      style: const TextStyle(fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: 'e.g. AudioPro Virtual Mic',
                                        filled: true,
                                        fillColor: CyberTheme.bgVoid,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: CyberTheme.borderHairline,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: CyberTheme.borderHairline,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: CyberTheme.cyanAccent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton(
                                    onPressed: () => unawaited(_applyEndpointNames()),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: CyberTheme.cyanAccent,
                                      side: const BorderSide(
                                        color: CyberTheme.borderHairline,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 13,
                                      ),
                                    ),
                                    child: const Text('Apply'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Active Virtual Mic: ${controller.virtualMicName}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: CyberTheme.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              VuMeterWaveform(
                                label: 'WASAPI Virtual Mic Output',
                                rms: controller.vuSnapshot.inputRms,
                                peak: controller.vuSnapshot.inputPeak,
                                isMuted: controller.isInputMuted,
                                height: 92,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Virtual Speaker Card (Windows -> Phone)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: CyberTheme.bgSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CyberTheme.borderHairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  const Text(
                                    'VIRTUAL SPEAKER (WINDOWS -> PHONE)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 1.1,
                                      color: CyberTheme.textMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        unawaited(controller.triggerHostPulse()),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: CyberTheme.cyanAccent,
                                      side: const BorderSide(
                                        color: CyberTheme.borderHairline,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                    ),
                                    icon: const Icon(Icons.volume_up_rounded, size: 16),
                                    label: const Text(
                                      'Send Test Pulse',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Virtual Sound Card Speaker Name',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CyberTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: TextField(
                                      controller: _spkNameController,
                                      onSubmitted: (_) => unawaited(_applyEndpointNames()),
                                      style: const TextStyle(fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: 'e.g. AudioPro Virtual Speaker',
                                        filled: true,
                                        fillColor: CyberTheme.bgVoid,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: CyberTheme.borderHairline,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: CyberTheme.borderHairline,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: CyberTheme.cyanAccent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton(
                                    onPressed: () => unawaited(_applyEndpointNames()),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: CyberTheme.cyanAccent,
                                      side: const BorderSide(
                                        color: CyberTheme.borderHairline,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 13,
                                      ),
                                    ),
                                    child: const Text('Apply'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text(
                                  'Stream Windows System Audio (WASAPI Loopback)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: CyberTheme.textSecondary,
                                  ),
                                ),
                                value: controller.loopbackEnabled,
                                onChanged: (val) =>
                                    unawaited(controller.toggleLoopback(val)),
                              ),
                              const Spacer(),
                              VuMeterWaveform(
                                label: 'WASAPI Loopback Capture',
                                rms: controller.vuSnapshot.outputRms,
                                peak: controller.vuSnapshot.outputRms,
                                isMuted: false,
                                height: 92,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Optional WASAPI Hardware Monitor / VB-Cable Bridge & Driver Summary Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: CyberTheme.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CyberTheme.borderHairline),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Text(
                        'WASAPI Bridge Output:',
                        style: TextStyle(
                          fontSize: 12,
                          color: CyberTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 320,
                        child: DropdownButtonFormField<AudioEndpoint>(
                          key: ValueKey<String?>(controller.selectedOutput?.id),
                          initialValue: controller.selectedOutput,
                          isExpanded: true,
                          dropdownColor: CyberTheme.bgSurfaceElevated,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: CyberTheme.bgVoid,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: CyberTheme.borderHairline,
                              ),
                            ),
                          ),
                          items: controller.outputDevices
                              .map(
                                (d) => DropdownMenuItem<AudioEndpoint>(
                                  value: d,
                                  child: Text(
                                    d.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (d) {
                            if (d != null) {
                              unawaited(controller.selectOutputDevice(d));
                            }
                          },
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'MMCSS Pro Audio · Lock-Free Ring · 48,000 Hz · 16-bit PCM · 5 ms',
                        style: TextStyle(
                          fontSize: 12,
                          color: CyberTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TelemetryMetric extends StatelessWidget {
  const _TelemetryMetric({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.0,
            color: CyberTheme.textMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: accent ? CyberTheme.cyanAccent : CyberTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
