import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

  List<AudioEndpoint> inputDevices = const <AudioEndpoint>[];
  List<AudioEndpoint> outputDevices = const <AudioEndpoint>[];

  AudioEndpoint? selectedInput;
  AudioEndpoint? selectedOutput;

  double outputVolume = 0.85;
  bool isInputMuted = false;
  bool isBackgroundLockActive = true;
  bool autoConnectEnabled = true;

  AudioVuSnapshot vuSnapshot = AudioVuSnapshot.zero;
  String? lastError;

  bool get isDesktopHost =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> initialize() async {
    if (!isDesktopHost) {
      await _requestMobilePermissions();
    }

    _vuSub?.cancel();
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

    _usbSub?.cancel();
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
      } else if (state == 'disconnected') {
        status = BridgeConnectionStatus.disconnected;
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
    if (autoConnectEnabled) {
      await connectBridge();
    }
  }

  Future<void> _requestMobilePermissions() async {
    await <Permission>[
      Permission.microphone,
      Permission.bluetoothConnect,
      Permission.notification,
    ].request();
  }

  Future<void> refreshEndpoints() async {
    try {
      final all = await _bridge.listAudioEndpoints();
      inputDevices = all.where((d) => d.isInput).toList(growable: false);
      outputDevices = all.where((d) => !d.isInput).toList(growable: false);

      if (selectedInput == null && inputDevices.isNotEmpty) {
        selectedInput = inputDevices.firstWhere(
          (d) => d.isDefault,
          orElse: () => inputDevices.first,
        );
      }
      if (selectedOutput == null && outputDevices.isNotEmpty) {
        selectedOutput = outputDevices.firstWhere(
          (d) => d.isDefault,
          orElse: () => outputDevices.first,
        );
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
      final localName = await _bridge.getLocalDeviceName();
      await _bridge.setBackgroundLockEnabled(isBackgroundLockActive);
      final started = await _bridge.startBridge(
        isHostMode: isDesktopHost,
        localDeviceName: localName,
      );
      if (!started && autoConnectEnabled) {
        _scheduleReconnect();
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
    _vuSub?.cancel();
    _usbSub?.cancel();
    super.dispose();
  }
}
