import 'dart:async';
import 'package:flutter/services.dart';
import '../core/audio_device.dart';

class EndpointTestResult {
  const EndpointTestResult({
    required this.ok,
    required this.portInUse,
    required this.summary,
    this.details = '',
  });

  factory EndpointTestResult.fromMap(Map<dynamic, dynamic> map) {
    return EndpointTestResult(
      ok: map['ok'] == true,
      portInUse: map['portInUse'] == true,
      summary: map['summary']?.toString() ?? 'Test completed',
      details: map['details']?.toString() ?? '',
    );
  }

  final bool ok;
  final bool portInUse;
  final String summary;
  final String details;
}

/// Platform channel bridge into Kotlin (Android), Swift (iOS), and C++ (Windows).
class NativeAudioBridge {
  static const MethodChannel _method = MethodChannel('com.audiopro/bridge');
  static const EventChannel _vuStream = EventChannel('com.audiopro/vu_stream');
  static const EventChannel _usbEvents = EventChannel('com.audiopro/usb_events');

  Stream<AudioVuSnapshot>? _cachedVuStream;
  Stream<Map<dynamic, dynamic>>? _cachedUsbStream;

  Stream<AudioVuSnapshot> get vuSnapshots {
    _cachedVuStream ??= _vuStream.receiveBroadcastStream().map((dynamic event) {
      if (event is Map) {
        return AudioVuSnapshot.fromMap(event);
      }
      return AudioVuSnapshot.zero;
    });
    return _cachedVuStream!;
  }

  Stream<Map<dynamic, dynamic>> get usbEvents {
    _cachedUsbStream ??= _usbEvents.receiveBroadcastStream().map((dynamic event) {
      if (event is Map) return event;
      return <dynamic, dynamic>{};
    });
    return _cachedUsbStream!;
  }

  Future<bool> startBridge({
    required bool isHostMode,
    required String localDeviceName,
    String host = '127.0.0.1',
    int port = 38900,
  }) async {
    final ok = await _method.invokeMethod<bool>('startBridge', <String, dynamic>{
      'isHostMode': isHostMode,
      'localDeviceName': localDeviceName,
      'host': host,
      'port': port,
    });
    return ok ?? false;
  }

  Future<void> stopBridge() async {
    await _method.invokeMethod<void>('stopBridge');
  }

  Future<EndpointTestResult> testEndpoint({
    required String host,
    required int port,
  }) async {
    try {
      final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
        'testEndpoint',
        <String, dynamic>{
          'host': host,
          'port': port,
        },
      );
      if (raw != null) {
        return EndpointTestResult.fromMap(raw);
      }
      return const EndpointTestResult(
        ok: false,
        portInUse: false,
        summary: 'No test response returned from native bridge',
      );
    } on MissingPluginException {
      return const EndpointTestResult(
        ok: false,
        portInUse: false,
        summary: 'Endpoint test not supported on this platform',
      );
    }
  }

  Future<List<AudioEndpoint>> listAudioEndpoints() async {
    final rawList = await _method.invokeMethod<List<dynamic>>('listAudioEndpoints');
    if (rawList == null) return const <AudioEndpoint>[];
    return rawList
        .whereType<Map<dynamic, dynamic>>()
        .map(AudioEndpoint.fromMap)
        .toList(growable: false);
  }

  Future<bool> setInputDevice(String deviceId) async {
    final ok = await _method.invokeMethod<bool>('setInputDevice', <String, dynamic>{
      'deviceId': deviceId,
    });
    return ok ?? false;
  }

  Future<bool> setOutputDevice(String deviceId) async {
    final ok = await _method.invokeMethod<bool>('setOutputDevice', <String, dynamic>{
      'deviceId': deviceId,
    });
    return ok ?? false;
  }

  Future<void> setVirtualEndpoints({
    required String virtualMicName,
    required String virtualSpkName,
  }) async {
    try {
      await _method.invokeMethod<void>('setVirtualEndpoints', <String, dynamic>{
        'virtualMicName': virtualMicName,
        'virtualSpkName': virtualSpkName,
      });
    } on MissingPluginException {
      // Optional on mobile platforms
    }
  }

  Future<void> setLoopbackEnabled(bool enabled) async {
    try {
      await _method.invokeMethod<void>('setLoopbackEnabled', <String, dynamic>{
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Windows-only
    }
  }

  Future<void> triggerHostPulse() async {
    try {
      await _method.invokeMethod<void>('triggerHostPulse');
    } on MissingPluginException {
      // Windows-only
    }
  }

  Future<void> setTestToneEnabled(bool enabled) async {
    try {
      await _method.invokeMethod<void>('setTestToneEnabled', <String, dynamic>{
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Optional
    }
  }

  Future<void> setOutputVolume(double volume) async {
    await _method.invokeMethod<void>('setOutputVolume', <String, dynamic>{
      'volume': volume.clamp(0.0, 1.0),
    });
  }

  Future<void> setInputMuted(bool muted) async {
    await _method.invokeMethod<void>('setInputMuted', <String, dynamic>{
      'muted': muted,
    });
  }

  Future<void> setBackgroundLockEnabled(bool enabled) async {
    await _method.invokeMethod<void>('setBackgroundLockEnabled', <String, dynamic>{
      'enabled': enabled,
    });
  }

  Future<String> getLocalDeviceName() async {
    final name = await _method.invokeMethod<String>('getLocalDeviceName');
    return name ?? 'AudioPro-Device';
  }

  Future<List<String>> getLocalAddresses() async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('getLocalAddresses');
      if (raw == null) return const <String>[];
      return raw.map((e) => e.toString()).toList(growable: false);
    } on MissingPluginException {
      return const <String>[];
    }
  }
}
