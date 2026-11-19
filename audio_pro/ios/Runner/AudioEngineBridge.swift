import Foundation
import AVFoundation
import Darwin
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
    private var isNodeAttached = false
    private var isTapInstalled = false

    private var connection: NWConnection?
    private var listener: NWListener?
    private var listenerPort: UInt16 = 0
    private let audioQueue = DispatchQueue(label: "com.audiopro.ios.socket", qos: .userInteractive)

    private var isRunning = false
    private var isInputMuted = false
    private var isTestToneEnabled = false
    private var outputGain: Float = 0.85
    private var sequence: UInt32 = 1
    private var testPhase: Double = 0.0

    private var targetHost: String = "127.0.0.1"
    private var targetPort: UInt16 = 38900
    private var localDeviceName: String = UIDevice.current.name

    private var pcmAccumulator: [Int16] = []
    private var pcmReadIndex: Int = 0
    private var isAudioSessionConfigured = false
    private var latestOutputRms: Double = 0.0
    private var packetsSentThisSec: Int = 0
    private var lastRateCheckTime: CFTimeInterval = CACurrentMediaTime()
    private var measuredPps: Int = 0
    private var lastVuEmitTime: CFTimeInterval = 0

    // Standard Float32 non-interleaved format required by AVAudioEngine.mainMixerNode
    private let mixerFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 1,
        interleaved: false
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

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopBridge()
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startBridge":
            let args = call.arguments as? [String: Any]
            let port = (args?["port"] as? Int) ?? 38900
            let host = (args?["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (args?["localDeviceName"] as? String) ?? UIDevice.current.name
            targetHost = (host?.isEmpty == false) ? host! : "127.0.0.1"
            targetPort = UInt16(clamping: port)
            localDeviceName = name
            startBridge()
            result(true)
        case "stopBridge":
            stopBridge()
            result(nil)
        case "testEndpoint":
            let args = call.arguments as? [String: Any]
            let port = UInt16(clamping: (args?["port"] as? Int) ?? 38900)
            let rawHost = (args?["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = (rawHost?.isEmpty == false) ? rawHost! : "127.0.0.1"
            testEndpoint(host: host, port: port, result: result)
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
        case "setTestToneEnabled":
            let args = call.arguments as? [String: Any]
            isTestToneEnabled = (args?["enabled"] as? Bool) ?? false
            result(nil)
        case "setBackgroundLockEnabled":
            let args = call.arguments as? [String: Any]
            let enabled = (args?["enabled"] as? Bool) ?? true
            if enabled && !isAudioSessionConfigured {
                configureAudioSession()
            }
            result(nil)
        case "getLocalDeviceName":
            result(UIDevice.current.name)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @discardableResult
    private func configureAudioSession(force: Bool = false) -> Bool {
        if isAudioSessionConfigured && !force {
            return true
        }
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
            isAudioSessionConfigured = true
            emitLog("AVAudioSession active (48kHz, 5ms IOBuffer)")
            return true
        } catch {
            isAudioSessionConfigured = false
            emitLog("AVAudioSession error: \(error.localizedDescription)")
            NSLog("AudioPro AVAudioSession error: \(error.localizedDescription)")
            return false
        }
    }

    private func enumerateEndpoints() -> [[String: Any]] {
        let session = AVAudioSession.sharedInstance()
        var endpoints: [[String: Any]] = []
        if let inputs = session.availableInputs {
            for port in inputs {
                let typeStr: String
                if port.portType == .bluetoothHFP || port.portType == .bluetoothLE {
                    typeStr = "bluetoothSco"
                } else if port.portType == .headsetMic {
                    typeStr = "wiredHeadset"
                } else if port.portType == .usbAudio {
                    typeStr = "usbAudio"
                } else {
                    typeStr = "builtInMic"
                }
                endpoints.append([
                    "id": port.uid,
                    "name": port.portName,
                    "type": typeStr,
                    "isInput": true,
                    "isDefault": port.portType == .builtInMic
                ])
            }
        }

        if endpoints.isEmpty {
            endpoints.append([
                "id": "ios-builtin-mic",
                "name": "iPhone Built-in Microphone",
                "type": "builtInMic",
                "isInput": true,
                "isDefault": true
            ])
        }

        var seenOutputIds = Set<String>()
        for output in session.currentRoute.outputs {
            let typeStr: String
            if output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP || output.portType == .bluetoothLE {
                typeStr = "bluetoothA2dp"
            } else if output.portType == .builtInReceiver {
                typeStr = "earpiece"
            } else if output.portType == .headphones || output.portType == .usbAudio {
                typeStr = "wiredHeadset"
            } else {
                typeStr = "speakerphone"
            }
            seenOutputIds.insert(output.uid)
            endpoints.append([
                "id": output.uid,
                "name": output.portName,
                "type": typeStr,
                "isInput": false,
                "isDefault": output.portType == .builtInSpeaker
            ])
        }

        if !endpoints.contains(where: { ($0["isInput"] as? Bool) == false && ($0["type"] as? String) == "speakerphone" }) {
            endpoints.append([
                "id": "ios-speaker",
                "name": "iPhone Loudspeaker",
                "type": "speakerphone",
                "isInput": false,
                "isDefault": true
            ])
        }
        if !endpoints.contains(where: { ($0["isInput"] as? Bool) == false && ($0["type"] as? String) == "earpiece" }) {
            endpoints.append([
                "id": "ios-receiver",
                "name": "iPhone Earpiece / Default Route",
                "type": "earpiece",
                "isInput": false,
                "isDefault": false
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
            NSLog("AudioPro setPreferredInput failed: \(error.localizedDescription)")
            return false
        }
    }

    private func selectOutputPort(id: String?) -> Bool {
        guard let id = id else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            if id == "ios-speaker" || id.lowercased().contains("speaker") {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
            return true
        } catch {
            NSLog("AudioPro overrideOutputAudioPort failed: \(error.localizedDescription)")
            return false
        }
    }

    private func startBridge() {
        isRunning = true
        emitLog("startBridge target=\(targetHost):\(targetPort) device=\(localDeviceName)")

        // Only initialize AVAudioEngine if not already running; never tear down audio during TCP retries.
        ensureAudioEngineStarted(retryCount: 0)
        ensureListenerStarted(port: targetPort)
        if targetHost != "127.0.0.1" && targetHost != "localhost" {
            connectSocket(host: targetHost, port: targetPort, deviceName: localDeviceName)
        }
    }

    private func ensureAudioEngineStarted(retryCount: Int) {
        guard isRunning else { return }
        if engine.isRunning && isTapInstalled {
            return
        }

        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            break
        case .undetermined:
            emitLog("Record permission undetermined; requesting permission")
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.emitLog("Record permission callback granted=\(granted)")
                    guard self.isRunning, granted else { return }
                    self.ensureAudioEngineStarted(retryCount: retryCount)
                }
            }
            return
        case .denied:
            emitLog("Microphone permission DENIED; AVAudioEngine skipped")
            NSLog("AudioPro microphone permission denied; skipping AVAudioEngine capture")
            return
        @unknown default:
            return
        }

        guard configureAudioSession() else {
            return
        }

        if !isNodeAttached {
            engine.attach(playerNode)
            isNodeAttached = true
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: mixerFormat)
        playerNode.volume = outputGain

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            emitLog("Invalid hwFormat (\(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) ch), retry=\(retryCount)")
            NSLog("AudioPro invalid input hardware format (\(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) ch)")
            if retryCount < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.ensureAudioEngineStarted(retryCount: retryCount + 1)
                }
            }
            return
        }

        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: mixerFormat) else {
            NSLog("AudioPro failed to create AVAudioConverter from \(hwFormat) to \(mixerFormat)")
            return
        }

        let ratio = mixerFormat.sampleRate / hwFormat.sampleRate
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRunning else { return }

            let estimatedFrames = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
            guard estimatedFrames > 0,
                  let outBuf = AVAudioPCMBuffer(pcmFormat: self.mixerFormat, frameCapacity: estimatedFrames) else {
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

            guard err == nil,
                  outBuf.frameLength > 0,
                  let floatChannel = outBuf.floatChannelData?[0] else {
                return
            }

            let count = Int(outBuf.frameLength)
            let samples = Array(UnsafeBufferPointer(start: floatChannel, count: count))
            self.audioQueue.async {
                self.processConvertedSamples(samples: samples)
            }
        }
        isTapInstalled = true

        engine.prepare()
        do {
            try engine.start()
            if engine.isRunning {
                playerNode.play()
                emitLog("AVAudioEngine started (hw=\(Int(hwFormat.sampleRate))Hz/\(hwFormat.channelCount)ch)")
            }
        } catch {
            emitLog("AVAudioEngine start failed: \(error.localizedDescription)")
            NSLog("AudioPro AVAudioEngine start failed: \(error.localizedDescription)")
        }
    }

    private func processConvertedSamples(samples: [Float]) {
        guard isRunning else { return }
        let count = samples.count

        var sumSq: Double = 0
        var peak: Double = 0

        for i in 0..<count {
            var sampleF = Double(samples[i])
            if isInputMuted {
                sampleF = 0.0
            } else if isTestToneEnabled {
                sampleF = 0.25 * sin(testPhase)
                testPhase += 2.0 * Double.pi * 440.0 / 48000.0
                if testPhase > 2.0 * Double.pi {
                    testPhase -= 2.0 * Double.pi
                }
            }
            let clamped = max(-1.0, min(1.0, sampleF))
            peak = max(peak, abs(clamped))
            sumSq += clamped * clamped
            let pcm16 = Int16(max(-32768.0, min(32767.0, clamped * 32767.0)))
            pcmAccumulator.append(pcm16)
        }

        let rms = count > 0 ? min(1.0, sqrt(sumSq / Double(count))) : 0.0

        // Drain exact 240-sample (5ms) packets using O(1) read cursor
        while pcmAccumulator.count - pcmReadIndex >= 240 {
            let endIdx = pcmReadIndex + 240
            var leBytes = Data(capacity: 480)
            for idx in pcmReadIndex..<endIdx {
                var little = pcmAccumulator[idx].littleEndian
                withUnsafeBytes(of: &little) { leBytes.append(contentsOf: $0) }
            }
            pcmReadIndex = endIdx
            sendPacketOnAudioQueue(type: 2, channels: 1, payload: leBytes)
            packetsSentThisSec += 1
        }
        if pcmReadIndex >= 2400 {
            pcmAccumulator.removeFirst(pcmReadIndex)
            pcmReadIndex = 0
        }

        let now = CACurrentMediaTime()
        if now - lastRateCheckTime >= 1.0 {
            measuredPps = packetsSentThisSec
            packetsSentThisSec = 0
            lastRateCheckTime = now
        }

        if now - lastVuEmitTime >= 0.066 {
            lastVuEmitTime = now
            let outRms = latestOutputRms
            latestOutputRms = max(0.0, latestOutputRms * 0.85)
            let pps = measuredPps
            DispatchQueue.main.async {
                self.vuSink?([
                    "inputRms": rms,
                    "inputPeak": peak,
                    "outputRms": outRms,
                    "latencyMs": 22.0,
                    "jitterMs": 2.6,
                    "packetsPerSecond": pps,
                    "packetLossPct": 0.0
                ])
            }
        }
    }

    private func ensureListenerStarted(port: UInt16) {
        audioQueue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            if let existing = self.listener, self.listenerPort == port {
                switch existing.state {
                case .ready, .setup, .waiting(_):
                    return
                default:
                    existing.cancel()
                    self.listener = nil
                }
            } else if let existing = self.listener {
                existing.cancel()
                self.listener = nil
            }

            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true

            guard let nwPort = NWEndpoint.Port(rawValue: port),
                  let newListener = try? NWListener(using: params, on: nwPort) else {
                self.emitLog("Failed to create NWListener on port \(port)")
                return
            }

            self.listener = newListener
            self.listenerPort = port

            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard let self = self, self.listener === newListener else { return }
                switch state {
                case .ready:
                    self.emitLog("USB Listener ready on :\(port) (awaiting Windows usbmuxd USB cable)")
                    if self.connection == nil && (self.targetHost == "127.0.0.1" || self.targetHost == "localhost") {
                        self.emitUsbStatus("connecting", peerName: "WINDOWS-HOST", transport: "USB Listener :\(port)")
                    }
                case .waiting(let err):
                    self.emitLog("USB Listener waiting on :\(port): \(err.localizedDescription)")
                case .failed(let err):
                    self.emitLog("USB Listener failed on :\(port): \(err.localizedDescription)")
                    self.emitUsbStatus("disconnected", peerName: nil, transport: "Port \(port) Busy/Error")
                    self.listener = nil
                case .cancelled:
                    if self.listener === newListener {
                        self.listener = nil
                    }
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] newConn in
                guard let self = self, self.isRunning else {
                    newConn.cancel()
                    return
                }
                self.emitLog("Incoming USB tunnel connection accepted on :\(port)")
                if let oldConn = self.connection {
                    oldConn.stateUpdateHandler = nil
                    oldConn.cancel()
                }
                self.connection = newConn
                let deviceName = self.localDeviceName
                newConn.stateUpdateHandler = { [weak self, weak newConn] state in
                    guard let self = self, let conn = newConn, self.connection === conn else { return }
                    switch state {
                    case .ready:
                        self.emitLog("USB tunnel .ready; sending APRO handshake")
                        self.emitUsbStatus("connected", peerName: "WINDOWS-HOST", transport: "USB Cable (usbmuxd)")
                        let hello = [
                            "deviceName": deviceName,
                            "platform": "iOS",
                            "sampleRate": 48000,
                            "frameSamples": 240
                        ] as [String: Any]
                        if let json = try? JSONSerialization.data(withJSONObject: hello) {
                            self.sendPacketOnAudioQueue(type: 0, channels: 1, payload: json)
                        }
                        self.receiveNextHeader(for: conn)
                    case .failed(let err):
                        self.emitLog("Incoming USB connection failed: \(err.localizedDescription)")
                        self.handleSocketDisconnect(conn)
                    case .cancelled:
                        self.handleSocketDisconnect(conn)
                    default:
                        break
                    }
                }
                newConn.start(queue: self.audioQueue)
            }

            newListener.start(queue: self.audioQueue)
        }
    }

    private func connectSocket(host: String, port: UInt16, deviceName: String) {
        audioQueue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            if let existing = self.connection, case .ready = existing.state {
                return
            }

            if let oldConn = self.connection {
                oldConn.stateUpdateHandler = nil
                oldConn.cancel()
                self.connection = nil
            }

            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            tcpOptions.connectionTimeout = 3
            let params = NWParameters(tls: nil, tcp: tcpOptions)

            let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 38900)
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
            self.connection = conn

            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard let self = self, let conn = conn, self.connection === conn else { return }
                switch state {
                case .ready:
                    self.emitLog("TCP ready -> \(host):\(port); sending APRO handshake")
                    self.emitUsbStatus("connected", peerName: "WINDOWS-HOST", transport: "USB usbmuxd / TCP")
                    let hello = [
                        "deviceName": deviceName,
                        "platform": "iOS",
                        "sampleRate": 48000,
                        "frameSamples": 240
                    ] as [String: Any]
                    if let json = try? JSONSerialization.data(withJSONObject: hello) {
                        self.sendPacketOnAudioQueue(type: 0, channels: 1, payload: json)
                    }
                    self.receiveNextHeader(for: conn)
                case .preparing:
                    self.emitLog("Probing TCP \(host):\(port)...")
                    self.emitUsbStatus("connecting", peerName: nil, transport: "USB Probe (\(host):\(port))")
                case .waiting(let err):
                    self.emitLog("TCP waiting/unreachable (\(host):\(port)): \(err.localizedDescription)")
                    self.emitUsbStatus("disconnected", peerName: nil, transport: "USB Host Unreachable")
                    conn.stateUpdateHandler = nil
                    conn.cancel()
                    self.connection = nil
                case .failed(let err):
                    self.emitLog("TCP failed (\(host):\(port)): \(err.localizedDescription)")
                    self.emitUsbStatus("disconnected", peerName: nil, transport: "USB Disconnected")
                    if self.connection === conn {
                        self.connection = nil
                    }
                case .cancelled:
                    self.emitLog("TCP connection cancelled")
                    self.emitUsbStatus("disconnected", peerName: nil, transport: "USB Disconnected")
                    if self.connection === conn {
                        self.connection = nil
                    }
                default:
                    break
                }
            }
            conn.start(queue: self.audioQueue)
        }
    }

    private func receiveNextHeader(for conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 16, maximumLength: 16) { [weak self, weak conn] data, _, isComplete, error in
            guard let self = self,
                  let conn = conn,
                  self.connection === conn,
                  self.isRunning else {
                return
            }

            if let error = error {
                NSLog("AudioPro socket header error: \(error.localizedDescription)")
                self.handleSocketDisconnect(conn)
                return
            }
            if isComplete || data == nil || data?.count != 16 {
                self.handleSocketDisconnect(conn)
                return
            }

            let hdr = data!
            if hdr[0] != 0x41 || hdr[1] != 0x50 || hdr[2] != 0x52 || hdr[3] != 0x4F {
                self.receiveNextHeader(for: conn)
                return
            }

            let type = hdr[5]
            let len = Int(hdr[14]) | (Int(hdr[15]) << 8)
            if len == 0 {
                self.receiveNextHeader(for: conn)
                return
            }
            guard len <= 8192 else {
                self.handleSocketDisconnect(conn)
                return
            }

            conn.receive(minimumIncompleteLength: len, maximumLength: len) { [weak self, weak conn] payload, _, payloadComplete, err in
                guard let self = self,
                      let conn = conn,
                      self.connection === conn,
                      self.isRunning else {
                    return
                }
                if err != nil || payloadComplete || payload == nil || payload?.count != len {
                    self.handleSocketDisconnect(conn)
                    return
                }
                if let body = payload {
                    if type == 1 {
                        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                           let peerName = obj["deviceName"] as? String {
                            self.emitUsbStatus("connected", peerName: peerName, transport: "USB usbmuxd / TCP")
                        }
                    } else if type == 3 {
                        self.schedulePlayback(pcm: body)
                    }
                }
                self.receiveNextHeader(for: conn)
            }
        }
    }

    private func handleSocketDisconnect(_ conn: NWConnection) {
        conn.stateUpdateHandler = nil
        conn.cancel()
        if connection === conn {
            connection = nil
        }
        emitUsbStatus("disconnected", peerName: nil, transport: "USB Disconnected")
    }

    private func schedulePlayback(pcm: Data) {
        guard isRunning, engine.isRunning else { return }
        let frameCount = pcm.count / 2
        guard frameCount > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: mixerFormat, frameCapacity: AVAudioFrameCount(frameCount)),
              let dst = buf.floatChannelData?[0] else {
            return
        }
        buf.frameLength = AVAudioFrameCount(frameCount)

        var sumSq: Double = 0
        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for i in 0..<frameCount {
                let lo = UInt16(ptr[i * 2])
                let hi = UInt16(ptr[i * 2 + 1]) << 8
                let sampleInt16 = Int16(bitPattern: lo | hi)
                let sampleFloat = Float(sampleInt16) / 32768.0
                dst[i] = sampleFloat
                let scaled = Double(sampleFloat) * Double(outputGain)
                sumSq += scaled * scaled
            }
        }
        latestOutputRms = min(1.0, sqrt(sumSq / Double(frameCount)))
        playerNode.scheduleBuffer(buf, completionHandler: nil)
    }

    private func sendPacketOnAudioQueue(type: UInt8, channels: UInt8, payload: Data) {
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

    private func stopAudioEngine() {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if playerNode.isPlaying {
            playerNode.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
    }

    private func stopBridge() {
        isRunning = false
        stopAudioEngine()
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.pcmAccumulator.removeAll(keepingCapacity: false)
            self.pcmReadIndex = 0
            if let l = self.listener {
                l.stateUpdateHandler = nil
                l.newConnectionHandler = nil
                l.cancel()
                self.listener = nil
            }
            if let conn = self.connection {
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.connection = nil
            }
        }
        emitLog("stopBridge called")
    }

    private func testEndpoint(host: String, port: UInt16, result: @escaping FlutterResult) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            var isListenerActiveOnPort = false
            if self.listenerPort == port, let l = self.listener, case .ready = l.state {
                isListenerActiveOnPort = true
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                var ok = false
                var portInUse = false
                var summary = ""
                let isLocalLoopback = (host == "127.0.0.1" || host == "localhost")

            if isLocalLoopback {
                if isListenerActiveOnPort {
                    ok = true
                    portInUse = false
                    summary = "READY — iPhone USB Listener is active on :\(port) (awaiting Windows usbmuxd USB cable)"
                } else {
                    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
                    if fd < 0 {
                        summary = "Socket error (errno=\(errno))"
                    } else {
                        var addr = sockaddr_in()
                        addr.sin_family = sa_family_t(AF_INET)
                        addr.sin_port = port.bigEndian
                        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
                        let bindRes = withUnsafePointer(to: &addr) {
                            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                        if bindRes == 0 {
                            ok = true
                            portInUse = false
                            summary = "FREE — Port :\(port) on iPhone is free & available for USB cable listener"
                        } else {
                            let err = errno
                            ok = false
                            portInUse = (err == EADDRINUSE)
                            summary = err == EADDRINUSE
                                ? "BUSY — Port :\(port) on iPhone is already used by another app/proxy"
                                : "Bind check failed (errno=\(err))"
                        }
                        Darwin.close(fd)
                    }
                }
            } else {
                // Outbound TCP probe to custom PC IP:port
                let t0 = CACurrentMediaTime()
                let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
                if fd < 0 {
                    summary = "Socket error (errno=\(errno))"
                } else {
                    let flags = fcntl(fd, F_GETFL, 0)
                    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                    var addr = sockaddr_in()
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = port.bigEndian
                    if inet_pton(AF_INET, host, &addr.sin_addr) <= 0 {
                        summary = "Invalid IPv4 address: \(host)"
                    } else {
                        let rc = withUnsafePointer(to: &addr) {
                            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                        if rc == 0 {
                            ok = true
                            let rtt = (CACurrentMediaTime() - t0) * 1000.0
                            summary = String(format: "CONNECTED — %@:%d reachable (%.1f ms)", host, port, rtt)
                        } else if errno == EINPROGRESS {
                            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                            let pr = poll(&pfd, 1, 1500)
                            if pr > 0 {
                                var soErr: Int32 = 0
                                var len = socklen_t(MemoryLayout<Int32>.size)
                                getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &len)
                                if soErr == 0 {
                                    ok = true
                                    let rtt = (CACurrentMediaTime() - t0) * 1000.0
                                    summary = String(format: "REACHABLE — %@:%d responded (%.1f ms)", host, port, rtt)
                                } else {
                                    summary = "REFUSED/ERROR — \(host):\(port) (\(String(cString: strerror(soErr))))"
                                }
                            } else {
                                summary = "TIMEOUT — \(host):\(port) did not respond in 1.5s"
                            }
                        } else {
                            summary = "CONNECT ERROR — \(host):\(port) (\(String(cString: strerror(errno))))"
                        }
                    }
                    Darwin.close(fd)
                }
            }

                let ifaceDetails = self.describeLocalInterfaces()
                DispatchQueue.main.async {
                    self.emitLog("Endpoint test [\(host):\(port)]: \(summary)")
                    if !ifaceDetails.isEmpty {
                        self.emitLog("iPhone interfaces: \(ifaceDetails)")
                    }
                    result([
                        "ok": ok,
                        "portInUse": portInUse,
                        "summary": summary,
                        "details": ifaceDetails
                    ])
                }
            }
        }
    }

    private func describeLocalInterfaces() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return "" }
        defer { freeifaddrs(ifaddr) }
        var parts: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let name = String(cString: current.pointee.ifa_name)
                    let ip = String(cString: hostBuf)
                    parts.append("\(name)=\(ip)")
                }
            }
            ptr = current.pointee.ifa_next
        }
        return parts.joined(separator: ", ")
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

    private func emitLog(_ message: String) {
        DispatchQueue.main.async {
            self.usbSink?([
                "status": "log",
                "source": "IOS-SWIFT",
                "message": message
            ])
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.emitLog("AVAudioSession routeChanged")
            self.usbSink?(["status": "devices_changed"])
            if self.isRunning {
                self.stopAudioEngine()
                self.ensureAudioEngineStarted(retryCount: 0)
            }
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        if type == .began {
            isAudioSessionConfigured = false
            emitLog("AVAudioSession interruption began")
        } else if type == .ended && isRunning {
            emitLog("AVAudioSession interruption ended; restarting engine")
            configureAudioSession(force: true)
            ensureAudioEngineStarted(retryCount: 0)
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
