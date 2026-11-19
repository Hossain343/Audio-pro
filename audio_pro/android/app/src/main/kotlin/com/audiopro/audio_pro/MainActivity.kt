package com.audiopro.audio_pro

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.audiopro/bridge"
    private val vuChannelName = "com.audiopro/vu_stream"
    private val usbChannelName = "com.audiopro/usb_events"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var audioManager: AudioManager? = null
    private var usbReceiver: BroadcastReceiver? = null
    private var audioDeviceCallback: AudioDeviceCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, vuChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    AudioProService.vuSink = events
                }

                override fun onCancel(arguments: Any?) {
                    AudioProService.vuSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, usbChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    AudioProService.usbSink = events
                    registerUsbAndDeviceCallbacks()
                }

                override fun onCancel(arguments: Any?) {
                    AudioProService.usbSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBridge" -> {
                        val port = call.argument<Int>("port") ?: 38900
                        val host = call.argument<String>("host")
                        val name = call.argument<String>("localDeviceName") ?: Build.MODEL
                        val intent = Intent(this, AudioProService::class.java).apply {
                            action = AudioProService.ACTION_START
                            putExtra(AudioProService.EXTRA_PORT, port)
                            putExtra(AudioProService.EXTRA_HOST, host)
                            putExtra(AudioProService.EXTRA_DEVICE_NAME, name)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopBridge" -> {
                        val intent = Intent(this, AudioProService::class.java).apply {
                            action = AudioProService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "listAudioEndpoints" -> {
                        result.success(enumerateEndpoints())
                    }
                    "setInputDevice" -> {
                        val id = call.argument<String>("deviceId")
                        result.success(selectDeviceById(id, isInput = true))
                    }
                    "setOutputDevice" -> {
                        val id = call.argument<String>("deviceId")
                        result.success(selectDeviceById(id, isInput = false))
                    }
                    "setOutputVolume" -> {
                        val vol = call.argument<Double>("volume") ?: 0.85
                        AudioProService.outputGain = vol.toFloat().coerceIn(0f, 1f)
                        result.success(null)
                    }
                    "setInputMuted" -> {
                        val muted = call.argument<Boolean>("muted") ?: false
                        AudioProService.isInputMuted = muted
                        result.success(null)
                    }
                    "setTestToneEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        AudioProService.isTestToneEnabled = enabled
                        result.success(null)
                    }
                    "setBackgroundLockEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        AudioProService.wakeLockDesired = enabled
                        result.success(null)
                    }
                    "getLocalDeviceName" -> {
                        result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun enumerateEndpoints(): List<Map<String, Any>> {
        val manager = audioManager ?: return emptyList()
        val list = mutableListOf<Map<String, Any>>()

        val inputs = manager.getDevices(AudioManager.GET_DEVICES_INPUTS)
        for (dev in inputs) {
            list.add(
                mapOf(
                    "id" to dev.id.toString(),
                    "name" to formatDeviceLabel(dev, isInput = true),
                    "type" to mapEndpointType(dev.type, isInput = true),
                    "isInput" to true,
                    "isDefault" to (dev.type == AudioDeviceInfo.TYPE_BUILTIN_MIC)
                )
            )
        }

        val outputs = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        for (dev in outputs) {
            list.add(
                mapOf(
                    "id" to dev.id.toString(),
                    "name" to formatDeviceLabel(dev, isInput = false),
                    "type" to mapEndpointType(dev.type, isInput = false),
                    "isInput" to false,
                    "isDefault" to (dev.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
                )
            )
        }
        return list
    }

    private fun formatDeviceLabel(dev: AudioDeviceInfo, isInput: Boolean): String {
        val product = dev.productName?.toString()?.trim().orEmpty()
        val role = when (dev.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth HFP/SCO"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth A2DP"
            AudioDeviceInfo.TYPE_BLE_HEADSET -> "BLE Audio Headset"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
            AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> "USB-C Audio"
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in Studio Mic"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Phone Earpiece"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Loudspeaker"
            else -> if (isInput) "Input #${dev.id}" else "Output #${dev.id}"
        }
        return if (product.isNotEmpty() && !product.equals(Build.MODEL, ignoreCase = true)) {
            "$product ($role)"
        } else {
            role
        }
    }

    private fun mapEndpointType(type: Int, isInput: Boolean): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetoothSco"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetoothA2dp"
            AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wiredHeadset"
            AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> "usbAudio"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speakerphone"
            else -> if (isInput) "builtInMic" else "speakerphone"
        }
    }

    private fun selectDeviceById(deviceId: String?, isInput: Boolean): Boolean {
        val manager = audioManager ?: return false
        val targetId = deviceId?.toIntOrNull() ?: return false
        val flags = if (isInput) AudioManager.GET_DEVICES_INPUTS else AudioManager.GET_DEVICES_OUTPUTS
        val target = manager.getDevices(flags).firstOrNull { it.id == targetId } ?: return false

        if (isInput) {
            AudioProService.preferredInputDevice = target
            if (target.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
                manager.mode = AudioManager.MODE_IN_COMMUNICATION
                @Suppress("DEPRECATION")
                manager.startBluetoothSco()
                @Suppress("DEPRECATION")
                manager.isBluetoothScoOn = true
            }
        } else {
            AudioProService.preferredOutputDevice = target
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.setCommunicationDevice(target)
            }
        }
        return true
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun registerUsbAndDeviceCallbacks() {
        if (usbReceiver == null) {
            usbReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == "android.hardware.usb.action.USB_STATE") {
                        val connected = intent.getBooleanExtra("connected", false)
                        if (connected) {
                            mainHandler.post {
                                AudioProService.usbSink?.success(
                                    mapOf("status" to "usb_attached")
                                )
                            }
                        }
                    }
                }
            }
            val filter = IntentFilter("android.hardware.usb.action.USB_STATE")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(usbReceiver, filter)
            }
        }

        if (audioDeviceCallback == null) {
            val callback = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                    mainHandler.post {
                        AudioProService.usbSink?.success(mapOf("status" to "devices_changed"))
                    }
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                    mainHandler.post {
                        AudioProService.usbSink?.success(mapOf("status" to "devices_changed"))
                    }
                }
            }
            audioDeviceCallback = callback
            audioManager?.registerAudioDeviceCallback(callback, mainHandler)
        }
    }

    override fun onDestroy() {
        usbReceiver?.let { unregisterReceiver(it) }
        usbReceiver = null
        audioDeviceCallback?.let { audioManager?.unregisterAudioDeviceCallback(it) }
        audioDeviceCallback = null
        super.onDestroy()
    }
}
