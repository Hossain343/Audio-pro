import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio_device.dart';
import '../../services/audio_bridge_controller.dart';
import '../theme/cyber_theme.dart';
import '../widgets/diagnostic_log_card.dart';
import '../widgets/vu_meter_waveform.dart';

class MobileTransmitterScreen extends StatefulWidget {
  const MobileTransmitterScreen({
    super.key,
    required this.controller,
  });

  final AudioBridgeController controller;

  @override
  State<MobileTransmitterScreen> createState() =>
      _MobileTransmitterScreenState();
}

class _MobileTransmitterScreenState extends State<MobileTransmitterScreen> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(
      text: widget.controller.hostAddress,
    );
    _portController = TextEditingController(
      text: widget.controller.port.toString(),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _applyEndpoint() async {
    FocusScope.of(context).unfocus();
    final parsedPort = int.tryParse(_portController.text.trim()) ?? 38900;
    await widget.controller.updateTargetEndpoint(
      _hostController.text,
      parsedPort,
    );
  }

  Future<void> _testEndpoint() async {
    FocusScope.of(context).unfocus();
    final parsedPort = int.tryParse(_portController.text.trim()) ?? 38900;
    await widget.controller.testTargetEndpoint(
      _hostController.text,
      parsedPort,
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
        final statusText = switch (controller.status) {
          BridgeConnectionStatus.connected => 'Connected',
          BridgeConnectionStatus.connecting => 'Probing / Connecting...',
          BridgeConnectionStatus.disconnected => 'Disconnected · Waiting',
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
                    : () => unawaited(controller.connectBridge()),
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      ValueListenableBuilder<AudioVuSnapshot>(
                        valueListenable: controller.vuNotifier,
                        builder: (context, vu, _) {
                          return Text(
                            '${controller.peerInfo.transportLabel} · '
                            '${vu.latencyMs.toStringAsFixed(1)} ms latency · '
                            '${controller.peerInfo.sampleRateHz} Hz PCM',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CyberTheme.textSecondary,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          'Auto-connect on USB attach',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: controller.autoConnectEnabled,
                        onChanged: (v) =>
                            unawaited(controller.setAutoConnect(v)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _hostController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'USB Tunnel / PC IP',
                                hintText: '127.0.0.1',
                                filled: true,
                                fillColor: CyberTheme.bgVoid,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'Port',
                                hintText: '38900',
                                filled: true,
                                fillColor: CyberTheme.bgVoid,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => unawaited(_applyEndpoint()),
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text('Apply IP/Port'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: controller.isTestingEndpoint
                                  ? null
                                  : () => unawaited(_testEndpoint()),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: CyberTheme.cyanAccent,
                              ),
                              icon: const Icon(
                                Icons.network_check_rounded,
                                size: 16,
                              ),
                              label: Text(
                                controller.isTestingEndpoint
                                    ? 'Testing...'
                                    : 'Test IP/Port',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Reset to USB (127.0.0.1)',
                            onPressed: () {
                              _hostController.text = '127.0.0.1';
                              _portController.text = '38900';
                              unawaited(_applyEndpoint());
                            },
                            icon: const Icon(
                              Icons.usb_rounded,
                              color: CyberTheme.cyanAccent,
                            ),
                          ),
                        ],
                      ),
                      if (controller.endpointTestResult != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: CyberTheme.bgVoid,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: controller.endpointTestResult!.ok
                                  ? CyberTheme.emeraldOk
                                  : CyberTheme.amberWait,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                controller.endpointTestResult!.summary,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: controller.endpointTestResult!.ok
                                      ? CyberTheme.emeraldOk
                                      : CyberTheme.amberWait,
                                ),
                              ),
                              if (controller
                                  .endpointTestResult!.details.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 3),
                                Text(
                                  controller.endpointTestResult!.details,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: CyberTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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
                          Row(
                            children: <Widget>[
                              TextButton.icon(
                                onPressed: () => unawaited(
                                  controller.toggleTestTone(
                                    !controller.testToneEnabled,
                                  ),
                                ),
                                icon: Icon(
                                  controller.testToneEnabled
                                      ? Icons.waves_rounded
                                      : Icons.graphic_eq_rounded,
                                  size: 16,
                                  color: controller.testToneEnabled
                                      ? CyberTheme.amberWait
                                      : CyberTheme.cyanAccent,
                                ),
                                label: Text(
                                  controller.testToneEnabled
                                      ? 'Test Tone'
                                      : 'Live Mic',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: controller.testToneEnabled
                                        ? CyberTheme.amberWait
                                        : CyberTheme.textSecondary,
                                  ),
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
                                tooltip:
                                    controller.isInputMuted ? 'Unmute' : 'Mute',
                              ),
                            ],
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
                        key: ValueKey<String?>(controller.selectedInput?.id),
                        initialValue: controller.selectedInput,
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
                            unawaited(controller.selectInputDevice(endpoint));
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      VuMeterWaveform(
                        label: 'Mic Input Levelizer',
                        vuListenable: controller.vuNotifier,
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
                        controller.selectedOutput?.name ??
                            'Phone Speaker / Earbuds',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CyberTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AudioEndpoint>(
                        key: ValueKey<String?>(controller.selectedOutput?.id),
                        initialValue: controller.selectedOutput,
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
                            unawaited(controller.selectOutputDevice(endpoint));
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
                      ValueListenableBuilder<AudioVuSnapshot>(
                        valueListenable: controller.vuNotifier,
                        builder: (context, vu, _) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: vu.outputRms,
                              minHeight: 6,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                CyberTheme.emeraldOk,
                              ),
                            ),
                          );
                        },
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
                    style:
                        TextStyle(fontSize: 12, color: CyberTheme.textSecondary),
                  ),
                  value: controller.isBackgroundLockActive,
                  onChanged: controller.toggleBackgroundLock,
                ),
                const SizedBox(height: 16),

                // Temporary Live Diagnostic Log Viewer
                DiagnosticLogCard(
                  controller: controller,
                  boxHeight: 190,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
