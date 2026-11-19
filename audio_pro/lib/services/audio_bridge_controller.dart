import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/audio_device.dart';
import 'native_audio_bridge.dart';

class AudioBridgeController extends ChangeNotifier {
  AudioBridgeController({NativeAudioBridge? bridge})
      : _bridge = bridge ?? NativeAudioBridge();

  final NativeAudioBridge _bridge;

  StreamSubscription<AudioVuSnapshot>? _vuSub;
  StreamSubscription<Map<dynamic, dynamic>>? _usbSub;
  Timer? _reconnectTimer;

  BridgeConnectionStatus status = BridgeConnectionStatus.disconnected;
  PeerInfo peerInfo = Platform.isWindows
      ? PeerInfo.unknownMobile
      : PeerInfo.unknownDesktop;

  String localDeviceName = Platform.isWindows ? 'WINDOWS-HOST' : 'Mobile Device';
  List<AudioEndpoint> inputDevices = const <AudioEndpoint>[];
  List<AudioEndpoint> outputDevices = const <AudioEndpoint>[];

  AudioEndpoint? selectedInput;
  AudioEndpoint? selectedOutput;

  String virtualMicName = 'AudioPro Virtual Mic';
  String virtualSpkName = 'AudioPro Virtual Speaker';
  String hostAddress = '127.0.0.1';
  int port = 38900;

  double outputVolume = 0.85;
  bool isInputMuted = false;
  bool isBackgroundLockActive = true;
  bool autoConnectEnabled = true;
  bool loopbackEnabled = true;
  bool testToneEnabled = false;

  /// Dedicated ValueNotifier so high-frequency VU updates never rebuild the
  /// entire screen tree (prevents scroll/tap lag on iOS and Android).
  final ValueNotifier<AudioVuSnapshot> vuNotifier =
      ValueNotifier<AudioVuSnapshot>(AudioVuSnapshot.zero);

  /// Live diagnostic log stream for native + Dart troubleshooting.
  final ValueNotifier<List<String>> logNotifier =
      ValueNotifier<List<String>>(const <String>[]);

  AudioVuSnapshot get vuSnapshot => vuNotifier.value;
  String? lastError;

  bool get isDesktopHost =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  void addLog(String source, String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    final line = '[$hh:$mm:$ss.$ms] [$source] $message';
    final next = <String>[...logNotifier.value, line];
    if (next.length > 250) {
      next.removeRange(0, next.length - 250);
    }
    logNotifier.value = List<String>.unmodifiable(next);
  }

  void clearLogs() {
    logNotifier.value = const <String>[];
  }

  String exportLogsText() {
    if (logNotifier.value.isEmpty) {
      return '[AudioPro] No diagnostic logs recorded yet.';
    }
    return logNotifier.value.join('\n');
  }

  Future<void> initialize() async {
    addLog(
      'APP',
      'Initializing AudioPro (${Platform.operatingSystem}, desktop=$isDesktopHost)',
    );
    try {
      localDeviceName = await _bridge.getLocalDeviceName();
      addLog('APP', 'Local device name: $localDeviceName');
    } catch (e) {
      addLog('APP', 'getLocalDeviceName fallback ($e)');
    }

    if (!isDesktopHost) {
      await _requestMobilePermissions();
    }

    unawaited(_vuSub?.cancel());
    _vuSub = _bridge.vuSnapshots.listen(
      (snapshot) {
        vuNotifier.value = snapshot;
      },
      onError: (Object err) {
        lastError = err.toString();
        addLog('VU-ERR', err.toString());
        notifyListeners();
      },
    );

    unawaited(_usbSub?.cancel());
    _usbSub = _bridge.usbEvents.listen((event) {
      final state = event['status']?.toString() ?? '';
      if (state == 'log') {
        final src = event['source']?.toString() ?? 'NATIVE';
        final msg = event['message']?.toString() ?? '';
        if (msg.isNotEmpty) {
          addLog(src, msg);
        }
        return;
      }

      final remoteName = event['peerName']?.toString();
      final transport = event['transport']?.toString();

      if (state == 'connected') {
        final prevStatus = status;
        status = BridgeConnectionStatus.connected;
        peerInfo = PeerInfo(
          deviceName: remoteName ?? peerInfo.deviceName,
          platformName: isDesktopHost ? 'Mobile Client' : 'Windows Host',
          transportLabel: transport ?? 'USB Tunnel',
          sampleRateHz: 48000,
          frameDurationMs: 5,
        );
        _reconnectTimer?.cancel();
        if (prevStatus != BridgeConnectionStatus.connected) {
          addLog('EVENT', 'Connected to ${peerInfo.deviceName} ($transport)');
        }
      } else if (state == 'connecting') {
        final prevStatus = status;
        status = BridgeConnectionStatus.connecting;
        if (transport != null && transport.isNotEmpty) {
          peerInfo = PeerInfo(
            deviceName: peerInfo.deviceName,
            platformName: peerInfo.platformName,
            transportLabel: transport,
            sampleRateHz: 48000,
            frameDurationMs: 5,
          );
        }
        if (prevStatus != BridgeConnectionStatus.connecting) {
          addLog('EVENT', 'Connecting: ${transport ?? "probing"}');
        }
      } else if (state == 'disconnected') {
        final prevStatus = status;
        status = BridgeConnectionStatus.disconnected;
        vuNotifier.value = AudioVuSnapshot.zero;
        if (prevStatus != BridgeConnectionStatus.disconnected) {
          addLog('EVENT', 'Disconnected (${transport ?? "closed"})');
        }
        if (autoConnectEnabled) {
          _scheduleReconnect();
        }
      } else if (state == 'usb_attached' && autoConnectEnabled) {
        addLog('EVENT', 'USB cable attached -> triggering connectBridge');
        unawaited(connectBridge());
      } else if (state == 'devices_changed') {
        addLog('EVENT', 'Audio devices changed -> refreshing endpoints');
        unawaited(refreshEndpoints());
      }
      notifyListeners();
    });

    await refreshEndpoints();
    if (isDesktopHost) {
      await _bridge.setVirtualEndpoints(
        virtualMicName: virtualMicName,
        virtualSpkName: virtualSpkName,
      );
      await _bridge.setLoopbackEnabled(loopbackEnabled);
    } else {
      try {
        await _bridge.setBackgroundLockEnabled(isBackgroundLockActive);
      } catch (e) {
        addLog('APP', 'setBackgroundLockEnabled error: $e');
      }
    }

    if (autoConnectEnabled) {
      await connectBridge();
    }
  }

  Future<void> _requestMobilePermissions() async {
    try {
      final permissions = <Permission>[
        Permission.microphone,
        if (Platform.isAndroid) Permission.bluetoothConnect else Permission.bluetooth,
        Permission.notification,
      ];
      final statuses = await permissions.request();
      for (final entry in statuses.entries) {
        addLog('PERM', '${entry.key.toString().split('.').last}: ${entry.value.name}');
      }
    } catch (e) {
      addLog('PERM', 'Permission request exception: $e');
    }
  }

  Future<void> refreshEndpoints() async {
    try {
      final all = await _bridge.listAudioEndpoints();
      inputDevices = all.where((d) => d.isInput).toList(growable: false);
      outputDevices = all.where((d) => !d.isInput).toList(growable: false);

      if (selectedInput == null || !inputDevices.contains(selectedInput)) {
        selectedInput = inputDevices.isNotEmpty
            ? inputDevices.firstWhere(
                (d) => d.isDefault,
                orElse: () => inputDevices.first,
              )
            : null;
      }
      if (selectedOutput == null || !outputDevices.contains(selectedOutput)) {
        selectedOutput = outputDevices.isNotEmpty
            ? outputDevices.firstWhere(
                (d) => d.isDefault,
                orElse: () => outputDevices.first,
              )
            : null;
      }
      addLog(
        'AUDIO',
        'Endpoints loaded: ${inputDevices.length} inputs, ${outputDevices.length} outputs',
      );
      notifyListeners();
    } on PlatformException catch (e) {
      lastError = e.message;
      addLog('AUDIO-ERR', 'listAudioEndpoints failed: ${e.message}');
      notifyListeners();
    }
  }

  Future<void> connectBridge({bool isAutoRetry = false}) async {
    if (status == BridgeConnectionStatus.connecting) return;
    status = BridgeConnectionStatus.connecting;
    lastError = null;
    notifyListeners();

    try {
      if (!isAutoRetry) {
        addLog(
          'BRIDGE',
          'connectBridge(host=$hostAddress, port=$port, hostMode=$isDesktopHost)',
        );
        await _bridge.setBackgroundLockEnabled(isBackgroundLockActive);
      }
      final started = await _bridge.startBridge(
        isHostMode: isDesktopHost,
        localDeviceName: localDeviceName,
        host: hostAddress,
        port: port,
      );
      if (!started && autoConnectEnabled) {
        status = BridgeConnectionStatus.disconnected;
        addLog('BRIDGE', 'startBridge returned false -> scheduling retry');
        _scheduleReconnect();
        notifyListeners();
      }
    } on PlatformException catch (e) {
      status = BridgeConnectionStatus.disconnected;
      lastError = e.message ?? 'Bridge initialization failed';
      addLog('BRIDGE-ERR', lastError!);
      if (autoConnectEnabled) {
        _scheduleReconnect();
      }
      notifyListeners();
    }
  }

  Future<void> disconnectBridge() async {
    _reconnectTimer?.cancel();
    addLog('BRIDGE', 'disconnectBridge requested by user');
    await _bridge.stopBridge();
    status = BridgeConnectionStatus.disconnected;
    vuNotifier.value = AudioVuSnapshot.zero;
    notifyListeners();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (status == BridgeConnectionStatus.disconnected && autoConnectEnabled) {
        unawaited(connectBridge(isAutoRetry: true));
      }
    });
  }

  Future<void> applyVirtualEndpoints({
    required String micName,
    required String spkName,
  }) async {
    final trimmedMic = micName.trim();
    final trimmedSpk = spkName.trim();
    virtualMicName = trimmedMic.isEmpty ? 'AudioPro Virtual Mic' : trimmedMic;
    virtualSpkName = trimmedSpk.isEmpty ? 'AudioPro Virtual Speaker' : trimmedSpk;
    addLog('HOST', 'Virtual endpoints updated: mic="$virtualMicName" spk="$virtualSpkName"');
    notifyListeners();
    await _bridge.setVirtualEndpoints(
      virtualMicName: virtualMicName,
      virtualSpkName: virtualSpkName,
    );
  }

  Future<void> toggleLoopback(bool enabled) async {
    loopbackEnabled = enabled;
    addLog('HOST', 'WASAPI loopback ${enabled ? "enabled" : "disabled"}');
    notifyListeners();
    await _bridge.setLoopbackEnabled(enabled);
  }

  Future<void> triggerHostPulse() async {
    addLog('HOST', 'Triggering 528Hz test pulse to mobile speaker');
    await _bridge.triggerHostPulse();
  }

  Future<void> toggleTestTone(bool enabled) async {
    testToneEnabled = enabled;
    addLog('AUDIO', 'Mobile 440Hz test tone ${enabled ? "enabled" : "disabled"}');
    notifyListeners();
    await _bridge.setTestToneEnabled(enabled);
  }

  Future<void> setAutoConnect(bool enabled) async {
    autoConnectEnabled = enabled;
    addLog('BRIDGE', 'Auto-connect ${enabled ? "enabled" : "disabled"}');
    if (!enabled) {
      _reconnectTimer?.cancel();
    } else if (status == BridgeConnectionStatus.disconnected) {
      unawaited(connectBridge());
    }
    notifyListeners();
  }

  Future<void> updateTargetEndpoint(String host, int newPort) async {
    final cleanHost = host.trim();
    hostAddress = cleanHost.isEmpty ? '127.0.0.1' : cleanHost;
    port = newPort.clamp(1024, 65535);
    addLog('BRIDGE', 'Target endpoint set to $hostAddress:$port');
    notifyListeners();
    if (status != BridgeConnectionStatus.disconnected) {
      await disconnectBridge();
      await connectBridge();
    } else if (autoConnectEnabled) {
      await connectBridge();
    }
  }

  Future<void> selectInputDevice(AudioEndpoint endpoint) async {
    selectedInput = endpoint;
    addLog('AUDIO', 'Selected input: ${endpoint.name} (${endpoint.id})');
    notifyListeners();
    await _bridge.setInputDevice(endpoint.id);
  }

  Future<void> selectOutputDevice(AudioEndpoint endpoint) async {
    selectedOutput = endpoint;
    addLog('AUDIO', 'Selected output: ${endpoint.name} (${endpoint.id})');
    notifyListeners();
    await _bridge.setOutputDevice(endpoint.id);
  }

  Future<void> updateOutputVolume(double value) async {
    outputVolume = value.clamp(0.0, 1.0);
    notifyListeners();
    await _bridge.setOutputVolume(outputVolume);
  }

  Future<void> toggleInputMute() async {
    isInputMuted = !isInputMuted;
    addLog('AUDIO', 'Input microphone ${isInputMuted ? "MUTED" : "UNMUTED"}');
    notifyListeners();
    await _bridge.setInputMuted(isInputMuted);
  }

  Future<void> toggleBackgroundLock(bool enabled) async {
    isBackgroundLockActive = enabled;
    addLog('POWER', 'Background WakeLock ${enabled ? "enabled" : "disabled"}');
    notifyListeners();
    await _bridge.setBackgroundLockEnabled(enabled);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    unawaited(_vuSub?.cancel());
    unawaited(_usbSub?.cancel());
    vuNotifier.dispose();
    logNotifier.dispose();
    super.dispose();
  }
}
