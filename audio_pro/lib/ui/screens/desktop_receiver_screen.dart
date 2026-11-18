import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio_device.dart';
import '../../services/audio_bridge_controller.dart';
import '../theme/cyber_theme.dart';
import '../widgets/vu_meter_waveform.dart';

class DesktopReceiverScreen extends StatelessWidget {
  const DesktopReceiverScreen({
    super.key,
    required this.controller,
  });

  final AudioBridgeController controller;

  @override
  Widget build(BuildContext context) {
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

        return Scaffold(
          backgroundColor: CyberTheme.bgVoid,
          appBar: AppBar(
            title: const Text(
              'AudioPro · Windows Virtual Sound Card Host',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            actions: <Widget>[
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
                // Connected Phone & USB Status Row
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: CyberTheme.bgSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CyberTheme.borderHairline),
                  ),
                  child: Row(
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
                                fontSize: 24,
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
                          const SizedBox(height: 8),
                          Text(
                            'Latency: ${controller.vuSnapshot.latencyMs.toStringAsFixed(1)} ms · '
                            'Jitter: ${controller.vuSnapshot.jitterMs.toStringAsFixed(1)} ms',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CyberTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Virtual Driver Endpoints
                Expanded(
                  child: Row(
                    children: <Widget>[
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
                              const Text(
                                'VIRTUAL MICROPHONE (PHONE -> WINDOWS)',
                                style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.1,
                                  color: CyberTheme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<AudioEndpoint>(
                                key: ValueKey<String?>(controller.selectedOutput?.id),
                                initialValue: controller.selectedOutput,
                                isExpanded: true,
                                dropdownColor: CyberTheme.bgSurfaceElevated,
                                items: controller.outputDevices
                                    .map(
                                      (d) => DropdownMenuItem<AudioEndpoint>(
                                        value: d,
                                        child: Text(d.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (d) {
                                  if (d != null) {
                                    unawaited(controller.selectOutputDevice(d));
                                  }
                                },
                              ),
                              const Spacer(),
                              VuMeterWaveform(
                                rms: controller.vuSnapshot.inputRms,
                                peak: controller.vuSnapshot.inputPeak,
                                isMuted: controller.isInputMuted,
                                height: 96,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
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
                              const Text(
                                'VIRTUAL SPEAKER (WINDOWS -> PHONE)',
                                style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.1,
                                  color: CyberTheme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<AudioEndpoint>(
                                key: ValueKey<String?>(controller.selectedInput?.id),
                                initialValue: controller.selectedInput,
                                isExpanded: true,
                                dropdownColor: CyberTheme.bgSurfaceElevated,
                                items: controller.inputDevices
                                    .map(
                                      (d) => DropdownMenuItem<AudioEndpoint>(
                                        value: d,
                                        child: Text(d.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (d) {
                                  if (d != null) {
                                    unawaited(controller.selectInputDevice(d));
                                  }
                                },
                              ),
                              const Spacer(),
                              VuMeterWaveform(
                                rms: controller.vuSnapshot.outputRms,
                                peak: controller.vuSnapshot.outputRms,
                                isMuted: false,
                                height: 96,
                              ),
                            ],
                          ),
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
