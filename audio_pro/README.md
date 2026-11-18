# AudioPro — Cross-Platform USB Virtual Sound Card

**AudioPro** transforms an Android or iOS smartphone into a bi-directional, ultra-low-latency (`< 50ms`) **USB Virtual Sound Card** for Windows PCs. It bridges a **Virtual Microphone** (Phone Mic / Bluetooth AirPods -> Windows Input) and a **Virtual Speaker** (Windows Output -> Phone Speaker / Earbuds) simultaneously over USB.

## Architecture Overview

| Layer | Technology | Role |
| :--- | :--- | :--- |
| **UI & Control** | Flutter (Dart 3, Null-Safe) | Adaptive Mobile Transmitter UI & Windows Host Console |
| **Transport** | Raw TCP over USB (`TCP_NODELAY`) | `ADB reverse/forward` (Android), `usbmuxd` / USB Tether (iOS), Winsock2 (Windows) |
| **Android Audio** | Kotlin + Low-Latency `AudioRecord`/`AudioTrack` + Foreground Service | Persistent wake-locked capture/playback, Bluetooth SCO/A2DP routing, USB attach auto-start |
| **iOS Audio** | Swift + `AVAudioEngine` + `AVAudioSession` + `NWConnection` | 5ms IO buffer (`setPreferredIOBufferDuration`), background audio/VoIP resilience, AirPods routing |
| **Windows Host** | C++20 Win32 + WASAPI (`MMCSS Pro Audio`) + SPSC Ring Buffer | Captures Windows Virtual Speaker & feeds Windows Virtual Microphone (`AudioPro` / VB-Cable) |

## Wire Protocol (`APRO` v1)

- **Format**: 48,000 Hz, 16-bit signed PCM (`240` samples = `5 ms` per frame)
- **Header**: 16 bytes (`APRO` magic, version, packet type, sequence uint32, timestamp uint32, payload length uint16)
- **Zero-Allocation Jitter Buffer**: Adaptive lock-free ring buffer targeting 10–15 ms host buffer + 5 ms USB socket + 10 ms mobile audio I/O = **~25–35 ms end-to-end latency**.

## USB Auto-Connection Setup

1. **Android**: Enable **USB Debugging**. Plug the phone into Windows. The Windows AudioPro host automatically detects the device via `adb` and establishes `adb reverse tcp:38900 tcp:38900`. The Android `AudioProService` connects immediately on USB attach without manual taps.
2. **iOS**: Plug iPhone/iPad via Lightning/USB-C (with Personal Hotspot USB or `usbmuxd` relay). `AudioEngineBridge` probes `127.0.0.1:38900` and USB tether gateway `172.20.10.x:38900` automatically.
3. **Windows Virtual Driver**: Install [VB-Cable](https://vb-audio.com/Cable/) or the AudioPro WDM Virtual Audio Driver so `AudioPro Virtual Mic (CABLE Input)` and `AudioPro Virtual Speaker (CABLE Output)` appear in Windows Sound settings.

## GitHub Actions CI/CD

Pushing to `main` or `master` automatically triggers `.github/workflows/build.yml` to run:
- `flutter analyze` & `flutter test`
- Android Release APK & AAB (`ubuntu-latest`)
- Windows x64 Release Bundle (`windows-latest`)
- iOS Unsigned Release Archive (`macos-latest`)
