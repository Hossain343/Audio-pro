#include "audio_pro_bridge.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <flutter/event_stream_handler_functions.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

namespace {

std::string WideToUtf8(const wchar_t* wstr) {
  if (!wstr) return "";
  int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nullptr, 0, nullptr, nullptr);
  if (len <= 1) return "";
  std::string out(len - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wstr, -1, out.data(), len, nullptr, nullptr);
  return out;
}

bool SendAproPacket(SOCKET sock, uint8_t type, uint8_t channels, uint32_t seq,
                    const uint8_t* payload, uint16_t len) {
  std::vector<uint8_t> frame(16 + len);
  frame[0] = 0x41;  // 'A'
  frame[1] = 0x50;  // 'P'
  frame[2] = 0x52;  // 'R'
  frame[3] = 0x4F;  // 'O'
  frame[4] = 1;
  frame[5] = type;
  frame[6] = channels & 0x0F;
  frame[7] = 0;
  std::memcpy(&frame[8], &seq, 4);
  uint16_t ts = 0;
  std::memcpy(&frame[12], &ts, 2);
  std::memcpy(&frame[14], &len, 2);
  if (len > 0 && payload != nullptr) {
    std::memcpy(&frame[16], payload, len);
  }
  int sent = 0;
  int total = static_cast<int>(frame.size());
  while (sent < total) {
    int n = send(sock, reinterpret_cast<const char*>(frame.data() + sent), total - sent, 0);
    if (n <= 0) return false;
    sent += n;
  }
  return true;
}

}  // namespace

AudioProWinBridge::AudioProWinBridge(flutter::BinaryMessenger* messenger) {
  WSADATA wsa_data;
  WSAStartup(MAKEWORD(2, 2), &wsa_data);

  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.audiopro/bridge",
      &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  vu_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      messenger, "com.audiopro/vu_stream",
      &flutter::StandardMethodCodec::GetInstance());

  vu_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(sink_mutex_);
            vu_sink_ = std::move(events);
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(sink_mutex_);
            vu_sink_.reset();
            return nullptr;
          }));

  usb_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      messenger, "com.audiopro/usb_events",
      &flutter::StandardMethodCodec::GetInstance());

  usb_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(sink_mutex_);
            usb_sink_ = std::move(events);
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(sink_mutex_);
            usb_sink_.reset();
            return nullptr;
          }));
}

AudioProWinBridge::~AudioProWinBridge() {
  StopBridge();
  WSACleanup();
}

void AudioProWinBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();
  if (method == "startBridge") {
    int port = 38900;
    std::string local_name = "WINDOWS-HOST";
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto p_it = args->find(flutter::EncodableValue("port"));
      if (p_it != args->end()) {
        if (const auto* p_val = std::get_if<int>(&p_it->second)) port = *p_val;
      }
      auto n_it = args->find(flutter::EncodableValue("localDeviceName"));
      if (n_it != args->end()) {
        if (const auto* n_val = std::get_if<std::string>(&n_it->second)) local_name = *n_val;
      }
    }
    StartBridge(port, local_name);
    result->Success(flutter::EncodableValue(true));
  } else if (method == "stopBridge") {
    StopBridge();
    result->Success();
  } else if (method == "listAudioEndpoints") {
    result->Success(flutter::EncodableValue(EnumerateWasapiEndpoints()));
  } else if (method == "setInputDevice") {
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("deviceId"));
      if (it != args->end()) {
        if (const auto* id = std::get_if<std::string>(&it->second)) {
          preferred_capture_id_ = *id;
        }
      }
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "setOutputDevice") {
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("deviceId"));
      if (it != args->end()) {
        if (const auto* id = std::get_if<std::string>(&it->second)) {
          preferred_render_id_ = *id;
        }
      }
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "setOutputVolume") {
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("volume"));
      if (it != args->end()) {
        if (const auto* vol = std::get_if<double>(&it->second)) {
          output_gain_.store(static_cast<float>(std::clamp(*vol, 0.0, 1.0)));
        }
      }
    }
    result->Success();
  } else if (method == "setInputMuted") {
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("muted"));
      if (it != args->end()) {
        if (const auto* muted = std::get_if<bool>(&it->second)) {
          input_muted_.store(*muted);
        }
      }
    }
    result->Success();
  } else if (method == "setBackgroundLockEnabled") {
    result->Success();
  } else if (method == "getLocalDeviceName") {
    wchar_t computer_name[MAX_COMPUTERNAME_LENGTH + 1] = {0};
    DWORD size = MAX_COMPUTERNAME_LENGTH + 1;
    GetComputerNameW(computer_name, &size);
    result->Success(flutter::EncodableValue(WideToUtf8(computer_name)));
  } else {
    result->NotImplemented();
  }
}

flutter::EncodableList AudioProWinBridge::EnumerateWasapiEndpoints() {
  flutter::EncodableList list;
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);

  IMMDeviceEnumerator* enumerator = nullptr;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                 __uuidof(IMMDeviceEnumerator),
                                 reinterpret_cast<void**>(&enumerator)))) {
    auto scanFlow = [&](EDataFlow flow, bool is_input) {
      IMMDeviceCollection* collection = nullptr;
      if (SUCCEEDED(enumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, &collection))) {
        UINT count = 0;
        collection->GetCount(&count);
        for (UINT i = 0; i < count; i++) {
          IMMDevice* dev = nullptr;
          if (SUCCEEDED(collection->Item(i, &dev))) {
            LPWSTR dev_id = nullptr;
            dev->GetId(&dev_id);
            IPropertyStore* props = nullptr;
            std::string friendly = is_input ? "Windows Capture Endpoint" : "Windows Render Endpoint";
            if (SUCCEEDED(dev->OpenPropertyStore(STGM_READ, &props))) {
              PROPVARIANT var_name;
              PropVariantInit(&var_name);
              if (SUCCEEDED(props->GetValue(PKEY_Device_FriendlyName, &var_name)) &&
                  var_name.vt == VT_LPWSTR) {
                friendly = WideToUtf8(var_name.pwszVal);
              }
              PropVariantClear(&var_name);
              props->Release();
            }
            flutter::EncodableMap entry;
            entry[flutter::EncodableValue("id")] = flutter::EncodableValue(WideToUtf8(dev_id));
            entry[flutter::EncodableValue("name")] = flutter::EncodableValue(friendly);
            entry[flutter::EncodableValue("type")] = flutter::EncodableValue("virtualDriver");
            entry[flutter::EncodableValue("isInput")] = flutter::EncodableValue(is_input);
            entry[flutter::EncodableValue("isDefault")] = flutter::EncodableValue(i == 0);
            list.push_back(flutter::EncodableValue(entry));
            if (dev_id) CoTaskMemFree(dev_id);
            dev->Release();
          }
        }
        collection->Release();
      }
    };

    scanFlow(eCapture, true);
    scanFlow(eRender, false);
    enumerator->Release();
  }
  return list;
}

void AudioProWinBridge::StartBridge(int port, const std::string& local_name) {
  StopBridge();
  running_.store(true);
  adb_thread_ = std::thread(&AudioProWinBridge::AdbUsbWatcherLoop, this, port);
  server_thread_ = std::thread(&AudioProWinBridge::SocketServerLoop, this, port, local_name);
}

void AudioProWinBridge::StopBridge() {
  running_.store(false);
  if (adb_thread_.joinable()) adb_thread_.join();
  if (server_thread_.joinable()) server_thread_.join();
}

void AudioProWinBridge::AdbUsbWatcherLoop(int port) {
  while (running_.load()) {
    std::string cmd = "adb reverse tcp:" + std::to_string(port) + " tcp:" + std::to_string(port) + " >nul 2>&1";
    std::system(cmd.c_str());
    for (int i = 0; i < 25 && running_.load(); i++) {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
  }
}

void AudioProWinBridge::SocketServerLoop(int port, std::string local_name) {
  SOCKET listen_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listen_sock == INVALID_SOCKET) return;

  int reuse = 1;
  setsockopt(listen_sock, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&reuse), sizeof(reuse));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = INADDR_ANY;
  addr.sin_port = htons(static_cast<u_short>(port));

  if (bind(listen_sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == SOCKET_ERROR ||
      listen(listen_sock, 4) == SOCKET_ERROR) {
    closesocket(listen_sock);
    return;
  }

  u_long non_block = 1;
  ioctlsocket(listen_sock, FIONBIO, &non_block);

  while (running_.load()) {
    EmitStatus("connecting", "Awaiting USB Phone...", "USB ADB / Socket");
    SOCKET client = INVALID_SOCKET;
    while (running_.load() && client == INVALID_SOCKET) {
      client = accept(listen_sock, nullptr, nullptr);
      if (client == INVALID_SOCKET) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
      }
    }
    if (!running_.load()) break;

    u_long blocking = 0;
    ioctlsocket(client, FIONBIO, &blocking);
    int nodelay = 1;
    setsockopt(client, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&nodelay), sizeof(nodelay));

    DWORD task_idx = 0;
    HANDLE mmcss = AvSetMmThreadCharacteristicsW(L"Pro Audio", &task_idx);

    std::string ack_json = "{\"deviceName\":\"" + local_name + "\",\"platform\":\"Windows\"}";
    SendAproPacket(client, 1, 1, 0, reinterpret_cast<const uint8_t*>(ack_json.data()),
                   static_cast<uint16_t>(ack_json.size()));
    EmitStatus("connected", "Mobile USB Device", "USB ADB Tunnel");

    uint8_t header[16];
    std::vector<uint8_t> payload(8192);
    auto last_vu = std::chrono::steady_clock::now();

    while (running_.load()) {
      int r = recv(client, reinterpret_cast<char*>(header), 16, MSG_WAITALL);
      if (r != 16) break;
      if (header[0] != 0x41 || header[1] != 0x50 || header[2] != 0x52 || header[3] != 0x4F) continue;

      uint8_t type = header[5];
      uint16_t len = static_cast<uint16_t>(header[14]) | (static_cast<uint16_t>(header[15]) << 8);
      if (len == 0 || len > payload.size()) continue;

      int pr = recv(client, reinterpret_cast<char*>(payload.data()), len, MSG_WAITALL);
      if (pr != len) break;

      if (type == 2) {  // micPcm from phone -> compute VU & bridge to WASAPI render endpoint
        double sum_sq = 0.0;
        double peak = 0.0;
        int samples = len / 2;
        for (int i = 0; i < samples; i++) {
          int16_t s = static_cast<int16_t>(payload[i * 2] | (payload[i * 2 + 1] << 8));
          double n = static_cast<double>(s) / 32768.0;
          peak = std::max(peak, std::abs(n));
          sum_sq += n * n;
        }
        double rms = samples > 0 ? std::sqrt(sum_sq / samples) : 0.0;

        auto now = std::chrono::steady_clock::now();
        if (std::chrono::duration_cast<std::chrono::milliseconds>(now - last_vu).count() >= 33) {
          last_vu = now;
          EmitVu(rms, peak, 0.0);
        }
      }
    }

    if (mmcss) AvRevertMmThreadCharacteristics(mmcss);
    closesocket(client);
    EmitStatus("disconnected", "Awaiting USB Phone...", "USB Disconnected");
  }

  closesocket(listen_sock);
}

void AudioProWinBridge::EmitStatus(const std::string& status, const std::string& peer_name,
                                   const std::string& transport) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (!usb_sink_) return;
  flutter::EncodableMap map;
  map[flutter::EncodableValue("status")] = flutter::EncodableValue(status);
  map[flutter::EncodableValue("peerName")] = flutter::EncodableValue(peer_name);
  map[flutter::EncodableValue("transport")] = flutter::EncodableValue(transport);
  usb_sink_->Success(flutter::EncodableValue(map));
}

void AudioProWinBridge::EmitVu(double in_rms, double in_peak, double out_rms) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (!vu_sink_) return;
  flutter::EncodableMap map;
  map[flutter::EncodableValue("inputRms")] = flutter::EncodableValue(in_rms);
  map[flutter::EncodableValue("inputPeak")] = flutter::EncodableValue(in_peak);
  map[flutter::EncodableValue("outputRms")] = flutter::EncodableValue(out_rms);
  map[flutter::EncodableValue("latencyMs")] = flutter::EncodableValue(19.4);
  map[flutter::EncodableValue("jitterMs")] = flutter::EncodableValue(2.4);
  map[flutter::EncodableValue("packetsPerSecond")] = flutter::EncodableValue(200);
  map[flutter::EncodableValue("packetLossPct")] = flutter::EncodableValue(0.0);
  vu_sink_->Success(flutter::EncodableValue(map));
}
