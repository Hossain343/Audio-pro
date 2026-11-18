import 'package:flutter/material.dart';
import '../../core/audio_device.dart';
import '../../services/audio_bridge_controller.dart';
import '../theme/cyber_theme.dart';
import '../widgets/vu_meter_waveform.dart';

class MobileTransmitterScreen extends StatelessWidget {
  const MobileTransmitterScreen({
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
        final statusText = switch (controller.status) {
          BridgeConnectionStatus.connected => 'Connected via USB',
          BridgeConnectionStatus.connecting => 'Connecting (USB Handshake)...',
          BridgeConnectionStatus.disconnected => 'Disconnected · Waiting for USB',
        };

        return Scaffold(
          backgroundColor: CyberTheme.bgVoid,
          appBar: AppBar(
            title: const Text(
              'AudioPro',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            actions: <Widget>[
              TextButton.icon(
                onPressed: controller.status == BridgeConnectionStatus.connected
                    ? controller.disconnectBridge
                    : controller.connectBridge,
                icon: Icon(
                  controller.status == BridgeConnectionStatus.connected
                      ? Icons.usb_off_rounded
                      : Icons.usb_rounded,
                  color: CyberTheme.cyanAccent,
                  size: 18,
                ),
                label: Text(
                  controller.status == BridgeConnectionStatus.connected
                      ? 'Disconnect'
                      : 'Reconnect',
                  style: const TextStyle(color: CyberTheme.cyanAccent),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                // Desktop Host Status Card
                Container(
                  padding: const EdgeInsets.all(16),
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
                            'WINDOWS HOST',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.1,
                              color: CyberTheme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: <Widget>[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        controller.peerInfo.deviceName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: CyberTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${controller.peerInfo.transportLabel} · '
                        '${controller.vuSnapshot.latencyMs.toStringAsFixed(1)} ms latency · '
                        '${controller.peerInfo.sampleRateHz} Hz PCM',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CyberTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Input Microphone + Real-time VU Meter Card
                Container(
                  padding: const EdgeInsets.all(16),
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
                            'ACTIVE MICROPHONE',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.1,
                              color: CyberTheme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            onPressed: controller.toggleInputMute,
                            icon: Icon(
                              controller.isInputMuted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
                              color: controller.isInputMuted
                                  ? CyberTheme.crimsonOff
                                  : CyberTheme.cyanAccent,
                            ),
                            tooltip: controller.isInputMuted ? 'Unmute' : 'Mute',
                          ),
                        ],
                      ),
                      Text(
                        controller.selectedInput?.name ?? 'Default Microphone',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CyberTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AudioEndpoint>(
                        value: controller.selectedInput,
                        isExpanded: true,
                        dropdownColor: CyberTheme.bgSurfaceElevated,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: CyberTheme.bgVoid,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: CyberTheme.borderHairline,
                            ),
                          ),
                        ),
                        items: controller.inputDevices
                            .map(
                              (device) => DropdownMenuItem<AudioEndpoint>(
                                value: device,
                                child: Text(
                                  device.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (endpoint) {
                          if (endpoint != null) {
                            controller.selectInputDevice(endpoint);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      VuMeterWaveform(
                        rms: controller.vuSnapshot.inputRms,
                        peak: controller.vuSnapshot.inputPeak,
                        isMuted: controller.isInputMuted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Output Speaker / Earbuds + Volume Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CyberTheme.bgSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CyberTheme.borderHairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'AUDIO OUTPUT DEVICE',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          color: CyberTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        controller.selectedOutput?.name ?? 'Phone Speaker / Earbuds',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CyberTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AudioEndpoint>(
                        value: controller.selectedOutput,
                        isExpanded: true,
                        dropdownColor: CyberTheme.bgSurfaceElevated,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: CyberTheme.bgVoid,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: CyberTheme.borderHairline,
                            ),
                          ),
                        ),
                        items: controller.outputDevices
                            .map(
                              (device) => DropdownMenuItem<AudioEndpoint>(
                                value: device,
                                child: Text(
                                  device.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (endpoint) {
                          if (endpoint != null) {
                            controller.selectOutputDevice(endpoint);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          const Text(
                            'Output Volume',
                            style: TextStyle(
                              fontSize: 13,
                              color: CyberTheme.textSecondary,
                            ),
                          ),
                          Text(
                            '${(controller.outputVolume * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: CyberTheme.cyanAccent,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: controller.outputVolume,
                        onChanged: controller.updateOutputVolume,
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: controller.vuSnapshot.outputRms,
                          minHeight: 6,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            CyberTheme.emeraldOk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Background Service Resilience Toggle
                SwitchListTile(
                  tileColor: CyberTheme.bgSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: CyberTheme.borderHairline),
                  ),
                  title: const Text(
                    'Background Audio & WakeLock',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Keep low-latency USB audio streaming when screen locks or app minimizes.',
                    style: TextStyle(fontSize: 12, color: CyberTheme.textSecondary),
                  ),
                  value: controller.isBackgroundLockActive,
                  onChanged: controller.toggleBackgroundLock,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
