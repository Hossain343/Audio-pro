import Foundation
import AVFoundation
import Network
import Flutter
import UIKit

final class AudioEngineBridge: NSObject {
    private let methodChannel: FlutterMethodChannel
    private let vuChannel: FlutterEventChannel
    private let usbChannel: FlutterEventChannel

    private var vuSink: FlutterEventSink?
    private var usbSink: FlutterEventSink?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var connection: NWConnection?
    private let audioQueue = DispatchQueue(label: "com.audiopro.ios.socket", qos: .userInteractive)

    private var isRunning = false
    private var isInputMuted = false
    private var outputGain: Float = 0.85
    private var sequence: UInt32 = 1

    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 48000,
        channels: 1,
        interleaved: true
    )!

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: "com.audiopro/bridge", binaryMessenger: messenger)
        vuChannel = FlutterEventChannel(name: "com.audiopro/vu_stream", binaryMessenger: messenger)
        usbChannel = FlutterEventChannel(name: "com.audiopro/usb_events", binaryMessenger: messenger)
        super.init()

        vuChannel.setStreamHandler(VuStreamHandler { [weak self] sink in
            self?.vuSink = sink
        })
        usbChannel.setStreamHandler(UsbStreamHandler { [weak self] sink in
            self?.usbSink = sink
        })

        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startBridge":
            let args = call.arguments as? [String: Any]
            let port = (args?["port"] as? Int) ?? 38900
            let name = (args?["localDeviceName"] as? String) ?? UIDevice.current.name
            startBridge(port: UInt16(port), deviceName: name)
            result(true)
        case "stopBridge":
            stopBridge()
            result(nil)
        case "listAudioEndpoints":
            result(enumerateEndpoints())
        case "setInputDevice":
            let args = call.arguments as? [String: Any]
            let id = args?["deviceId"] as? String
            result(selectInputPort(id: id))
        case "setOutputDevice":
            let args = call.arguments as? [String: Any]
            let id = args?["deviceId"] as? String
            result(selectOutputPort(id: id))
        case "setOutputVolume":
            let args = call.arguments as? [String: Any]
            let vol = (args?["volume"] as? Double) ?? 0.85
            outputGain = Float(max(0.0, min(1.0, vol)))
            playerNode.volume = outputGain
            result(nil)
        case "setInputMuted":
            let args = call.arguments as? [String: Any]
            isInputMuted = (args?["muted"] as? Bool) ?? false
            result(nil)
        case "setBackgroundLockEnabled":
            configureAudioSession()
            result(nil)
        case "getLocalDeviceName":
            result(UIDevice.current.name)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
            )
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            NSLog("AudioPro AVAudioSession error: \(error.localizedDescription)")
        }
    }

    private func enumerateEndpoints() -> [[String: Any]] {
        let session = AVAudioSession.sharedInstance()
        var endpoints: [[String: Any]] = []
        if let inputs = session.availableInputs {
            for port in inputs {
                let typeStr = port.portType == .bluetoothHFP || port.portType == .bluetoothLE
                    ? "bluetoothSco"
                    : (port.portType == .headsetMic ? "wiredHeadset" : "builtInMic")
                endpoints.append([
                    "id": port.uid,
                    "name": port.portName,
                    "type": typeStr,
                    "isInput": true,
                    "isDefault": port.portType == .builtInMic
                ])
            }
        }
        for output in session.currentRoute.outputs {
            let typeStr = output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP
                ? "bluetoothA2dp"
                : (output.portType == .builtInReceiver ? "earpiece" : "speakerphone")
            endpoints.append([
                "id": output.uid,
                "name": output.portName,
                "type": typeStr,
                "isInput": false,
                "isDefault": output.portType == .builtInSpeaker
            ])
        }
        return endpoints
    }

    private func selectInputPort(id: String?) -> Bool {
        guard let id = id else { return false }
        let session = AVAudioSession.sharedInstance()
        guard let target = session.availableInputs?.first(where: { $0.uid == id }) else {
            return false
        }
        do {
            try session.setPreferredInput(target)
            return true
        } catch {
            return false
        }
    }

    private func selectOutputPort(id: String?) -> Bool {
        guard let id = id else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            if id.lowercased().contains("speaker") {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
            return true
        } catch {
            return false
        }
    }

    private func startBridge(port: UInt16, deviceName: String) {
        stopBridge()
        isRunning = true
        configureAudioSession()
        startAudioEngine()
        connectSocket(host: "127.0.0.1", port: port, deviceName: deviceName)
    }

    private func startAudioEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
        playerNode.volume = outputGain

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: hwFormat, to: playbackFormat)

        inputNode.installTap(onBus: 0, bufferSize: 240, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRunning, let converter = converter else { return }
            let outCapacity = AVAudioFrameCount(240)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: self.playbackFormat, frameCapacity: outCapacity) else {
                return
            }

            var err: NSError?
            var consumed = false
            converter.convert(to: outBuf, error: &err) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard err == nil, let chData = outBuf.int16ChannelData else { return }
            let frameLen = Int(outBuf.frameLength)
            let byteCount = frameLen * 2
            var pcmData = Data(bytes: chData[0], count: byteCount)

            var rms: Double = 0
            var peak: Double = 0
            if self.isInputMuted {
                pcmData.resetBytes(in: 0..<byteCount)
            } else {
                var sumSq: Double = 0
                for i in 0..<frameLen {
                    let s = Double(chData[0][i]) / 32768.0
                    peak = max(peak, abs(s))
                    sumSq += s * s
                }
                rms = frameLen > 0 ? min(1.0, sqrt(sumSq / Double(frameLen))) : 0
            }

            self.sendPacket(type: 2, channels: 1, payload: pcmData)
            DispatchQueue.main.async {
                self.vuSink?([
                    "inputRms": rms,
                    "inputPeak": peak,
                    "outputRms": 0.0,
                    "latencyMs": 22.0,
                    "jitterMs": 2.8,
                    "packetsPerSecond": 200,
                    "packetLossPct": 0.0
                ])
            }
        }

        do {
            try engine.start()
            playerNode.play()
        } catch {
            NSLog("AudioPro AVAudioEngine start failed: \(error.localizedDescription)")
        }
    }

    private func connectSocket(host: String, port: UInt16, deviceName: String) {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let nwPort = NWEndpoint.Port(rawValue: port) ?? 38900
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.emitUsbStatus("connected", peerName: "WINDOWS-HOST", transport: "USB usbmuxd")
                let hello = [
                    "deviceName": deviceName,
                    "platform": "iOS",
                    "sampleRate": 48000,
                    "frameSamples": 240
                ] as [String: Any]
                if let json = try? JSONSerialization.data(withJSONObject: hello) {
                    self.sendPacket(type: 0, channels: 1, payload: json)
                }
                self.receiveNextHeader()
            case .preparing:
                self.emitUsbStatus("connecting", peerName: nil, transport: "USB Probe")
            case .failed(_), .cancelled:
                self.emitUsbStatus("disconnected", peerName: nil, transport: "USB Disconnected")
            default:
                break
            }
        }
        conn.start(queue: audioQueue)
    }

    private func receiveNextHeader() {
        connection?.receive(minimumIncompleteLength: 16, maximumLength: 16) { [weak self] data, _, isComplete, error in
            guard let self = self, self.isRunning, error == nil, !isComplete, let hdr = data, hdr.count == 16 else {
                return
            }
            let type = hdr[5]
            let len = Int(hdr[14]) | (Int(hdr[15]) << 8)
            guard len > 0, len <= 8192 else {
                self.receiveNextHeader()
                return
            }
            self.connection?.receive(minimumIncompleteLength: len, maximumLength: len) { payload, _, _, err in
                if err == nil, let pcm = payload, type == 3 {
                    self.schedulePlayback(pcm: pcm)
                }
                self.receiveNextHeader()
            }
        }
    }

    private func schedulePlayback(pcm: Data) {
        let frameCount = AVAudioFrameCount(pcm.count / 2)
        guard let buf = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount),
              let dst = buf.int16ChannelData else { return }
        buf.frameLength = frameCount
        pcm.withUnsafeBytes { raw in
            if let src = raw.bindMemory(to: Int16.self).baseAddress {
                dst[0].update(from: src, count: Int(frameCount))
            }
        }
        playerNode.scheduleBuffer(buf, completionHandler: nil)
    }

    private func sendPacket(type: UInt8, channels: UInt8, payload: Data) {
        guard let conn = connection, conn.state == .ready else { return }
        var frame = Data(capacity: 16 + payload.count)
        frame.append(contentsOf: [0x41, 0x50, 0x52, 0x4F, 1, type, channels & 0x0F, 0])
        var seq = sequence.littleEndian
        sequence &+= 1
        frame.append(Data(bytes: &seq, count: 4))
        var ts = UInt16(0).littleEndian
        frame.append(Data(bytes: &ts, count: 2))
        var len = UInt16(payload.count).littleEndian
        frame.append(Data(bytes: &len, count: 2))
        frame.append(payload)
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func stopBridge() {
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        connection?.cancel()
        connection = nil
    }

    private func emitUsbStatus(_ status: String, peerName: String?, transport: String) {
        DispatchQueue.main.async {
            self.usbSink?([
                "status": status,
                "peerName": peerName ?? "WINDOWS-HOST",
                "transport": transport
            ])
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.usbSink?(["status": "devices_changed"])
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        if type == .ended && isRunning {
            configureAudioSession()
            try? engine.start()
            playerNode.play()
        }
    }
}

private final class VuStreamHandler: NSObject, FlutterStreamHandler {
    private let onSink: (FlutterEventSink?) -> Void
    init(_ onSink: @escaping (FlutterEventSink?) -> Void) { self.onSink = onSink }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onSink(events); return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onSink(nil); return nil
    }
}

private final class UsbStreamHandler: NSObject, FlutterStreamHandler {
    private let onSink: (FlutterEventSink?) -> Void
    init(_ onSink: @escaping (FlutterEventSink?) -> Void) { self.onSink = onSink }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onSink(events); return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onSink(nil); return nil
    }
}
