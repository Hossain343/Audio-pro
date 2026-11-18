import 'package:flutter/foundation.dart';

enum BridgeConnectionStatus {
  disconnected,
  connecting,
  connected,
}

enum AudioEndpointType {
  builtInMic,
  bluetoothSco,
  wiredHeadset,
  usbAudio,
  speakerphone,
  earpiece,
  bluetoothA2dp,
  virtualDriver,
}

@immutable
class AudioEndpoint {
  const AudioEndpoint({
    required this.id,
    required this.name,
    required this.type,
    required this.isInput,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final AudioEndpointType type;
  final bool isInput;
  final bool isDefault;

  factory AudioEndpoint.fromMap(Map<dynamic, dynamic> map) {
    final rawType = map['type']?.toString() ?? 'builtInMic';
    final parsedType = AudioEndpointType.values.firstWhere(
      (e) => e.name == rawType,
      orElse: () => AudioEndpointType.builtInMic,
    );
    return AudioEndpoint(
      id: map['id']?.toString() ?? 'default',
      name: map['name']?.toString() ?? 'Unknown Device',
      type: parsedType,
      isInput: map['isInput'] == true,
      isDefault: map['isDefault'] == true,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type.name,
        'isInput': isInput,
        'isDefault': isDefault,
      };
}

@immutable
class AudioVuSnapshot {
  const AudioVuSnapshot({
    required this.inputRms,
    required this.inputPeak,
    required this.outputRms,
    required this.latencyMs,
    required this.jitterMs,
    required this.packetsPerSecond,
    required this.packetLossPct,
  });

  final double inputRms;
  final double inputPeak;
  final double outputRms;
  final double latencyMs;
  final double jitterMs;
  final int packetsPerSecond;
  final double packetLossPct;

  static const AudioVuSnapshot zero = AudioVuSnapshot(
    inputRms: 0.0,
    inputPeak: 0.0,
    outputRms: 0.0,
    latencyMs: 0.0,
    jitterMs: 0.0,
    packetsPerSecond: 0,
    packetLossPct: 0.0,
  );

  factory AudioVuSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return AudioVuSnapshot(
      inputRms: ((map['inputRms'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      inputPeak: ((map['inputPeak'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      outputRms: ((map['outputRms'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      latencyMs: ((map['latencyMs'] as num?) ?? 0).toDouble(),
      jitterMs: ((map['jitterMs'] as num?) ?? 0).toDouble(),
      packetsPerSecond: ((map['packetsPerSecond'] as num?) ?? 0).toInt(),
      packetLossPct: ((map['packetLossPct'] as num?) ?? 0).toDouble(),
    );
  }
}

@immutable
class PeerInfo {
  const PeerInfo({
    required this.deviceName,
    required this.platformName,
    required this.transportLabel,
    required this.sampleRateHz,
    required this.frameDurationMs,
  });

  final String deviceName;
  final String platformName;
  final String transportLabel;
  final int sampleRateHz;
  final int frameDurationMs;

  static const PeerInfo unknownDesktop = PeerInfo(
    deviceName: 'Searching Windows Host...',
    platformName: 'Windows',
    transportLabel: 'USB ADB / Socket',
    sampleRateHz: 48000,
    frameDurationMs: 5,
  );

  static const PeerInfo unknownMobile = PeerInfo(
    deviceName: 'Awaiting USB Device...',
    platformName: 'Android / iOS',
    transportLabel: 'USB Tunnel',
    sampleRateHz: 48000,
    frameDurationMs: 5,
  );
}
