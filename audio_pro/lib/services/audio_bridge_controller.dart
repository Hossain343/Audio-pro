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

  AudioVuSnapshot vuSnapshot = AudioVuSnapshot.zero;
  String? lastError;

  bool get isDesktopHost =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> initialize() async {
    try {
      localDeviceName = await _bridge.getLocalDeviceName();
    } catch (_) {
      // Keep default fallback
    }

    if (!isDesktopHost) {
      await _requestMobilePermissions();
    }

    unawaited(_vuSub?.cancel());
    _vuSub = _bridge.vuSnapshots.listen(
      (snapshot) {
        vuSnapshot = snapshot;
        notifyListeners();
      },
      onError: (Object err) {
        lastError = err.toString();
        notifyListeners();
      },
    );

    unawaited(_usbSub?.cancel());
    _usbSub = _bridge.usbEvents.listen((event) {
      final state = event['status']?.toString() ?? '';
      final remoteName = event['peerName']?.toString();
      final transport = event['transport']?.toString();

      if (state == 'connected') {
        status = BridgeConnectionStatus.connected;
        peerInfo = PeerInfo(
          deviceName: remoteName ?? peerInfo.deviceName,
          platformName: isDesktopHost ? 'Mobile Client' : 'Windows Host',
          transportLabel: transport ?? 'USB Tunnel',
          sampleRateHz: 48000,
          frameDurationMs: 5,
        );
        _reconnectTimer?.cancel();
      } else if (state == 'connecting') {
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
      } else if (state == 'disconnected') {
        status = BridgeConnectionStatus.disconnected;
        vuSnapshot = AudioVuSnapshot.zero;
        if (autoConnectEnabled) {
          _scheduleReconnect();
        }
      } else if (state == 'usb_attached' && autoConnectEnabled) {
        unawaited(connectBridge());
      } else if (state == 'devices_changed') {
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
      await permissions.request();
    } catch (_) {
      // Do not fail app startup if platform permission prompt throws
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
      notifyListeners();
    } on PlatformException catch (e) {
      lastError = e.message;
      notifyListeners();
    }
  }

  Future<void> connectBridge() async {
    if (status == BridgeConnectionStatus.connecting) return;
    status = BridgeConnectionStatus.connecting;
    lastError = null;
    notifyListeners();

    try {
      localDeviceName = await _bridge.getLocalDeviceName();
      await _bridge.setBackgroundLockEnabled(isBackgroundLockActive);
      final started = await _bridge.startBridge(
        isHostMode: isDesktopHost,
        localDeviceName: localDeviceName,
        host: hostAddress,
        port: port,
      );
      if (!started && autoConnectEnabled) {
        status = BridgeConnectionStatus.disconnected;
        _scheduleReconnect();
        notifyListeners();
      }
    } on PlatformException catch (e) {
      status = BridgeConnectionStatus.disconnected;
      lastError = e.message ?? 'Bridge initialization failed';
      if (autoConnectEnabled) {
        _scheduleReconnect();
      }
      notifyListeners();
    }
  }

  Future<void> disconnectBridge() async {
    _reconnectTimer?.cancel();
    await _bridge.stopBridge();
    status = BridgeConnectionStatus.disconnected;
    vuSnapshot = AudioVuSnapshot.zero;
    notifyListeners();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (status == BridgeConnectionStatus.disconnected && autoConnectEnabled) {
        unawaited(connectBridge());
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
    notifyListeners();
    await _bridge.setVirtualEndpoints(
      virtualMicName: virtualMicName,
      virtualSpkName: virtualSpkName,
    );
  }

  Future<void> toggleLoopback(bool enabled) async {
    loopbackEnabled = enabled;
    notifyListeners();
    await _bridge.setLoopbackEnabled(enabled);
  }

  Future<void> triggerHostPulse() async {
    await _bridge.triggerHostPulse();
  }

  Future<void> toggleTestTone(bool enabled) async {
    testToneEnabled = enabled;
    notifyListeners();
    await _bridge.setTestToneEnabled(enabled);
  }

  Future<void> setAutoConnect(bool enabled) async {
    autoConnectEnabled = enabled;
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
    notifyListeners();
    if (status != BridgeConnectionStatus.disconnected) {
      await disconnectBridge();
      await connectBridge();
    }
  }

  Future<void> selectInputDevice(AudioEndpoint endpoint) async {
    selectedInput = endpoint;
    notifyListeners();
    await _bridge.setInputDevice(endpoint.id);
  }

  Future<void> selectOutputDevice(AudioEndpoint endpoint) async {
    selectedOutput = endpoint;
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
    notifyListeners();
    await _bridge.setInputMuted(isInputMuted);
  }

  Future<void> toggleBackgroundLock(bool enabled) async {
    isBackgroundLockActive = enabled;
    notifyListeners();
    await _bridge.setBackgroundLockEnabled(enabled);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    unawaited(_vuSub?.cancel());
    unawaited(_usbSub?.cancel());
    super.dispose();
  }
}
