#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include "audio_pro_bridge.h"

#include <mmdeviceapi.h>
#include <audioclient.h>
#include <mmreg.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <flutter/event_stream_handler_functions.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
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

std::wstring Utf8ToWide(const std::string& str) {
  if (str.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
  if (len <= 1) return L"";
  std::wstring out(len - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, out.data(), len);
  return out;
}

std::string ExtractJsonStringField(const std::string& json, const std::string& key) {
  std::string needle = "\"" + key + "\"";
  size_t pos = json.find(needle);
  if (pos == std::string::npos) return "";
  size_t colon = json.find(':', pos + needle.size());
  if (colon == std::string::npos) return "";
  size_t q1 = json.find('"', colon + 1);
  if (q1 == std::string::npos) return "";
  size_t q2 = json.find('"', q1 + 1);
  if (q2 == std::string::npos) return "";
  return json.substr(q1 + 1, q2 - q1 - 1);
}

bool WaitReadable(SOCKET sock, int timeout_ms) {
  fd_set read_fds;
  FD_ZERO(&read_fds);
  FD_SET(sock, &read_fds);
  timeval tv{};
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;
  int res = select(0, &read_fds, nullptr, nullptr, &tv);
  return res > 0;
}

bool RecvExact(SOCKET sock, uint8_t* dst, int len, const std::atomic<bool>& running) {
  int received = 0;
  while (received < len && running.load()) {
    if (!WaitReadable(sock, 200)) {
      continue;
    }
    int n = recv(sock, reinterpret_cast<char*>(dst + received), len - received, 0);
    if (n <= 0) return false;
    received += n;
  }
  return received == len;
}

bool SendAproPacket(SOCKET sock, std::mutex& send_mutex, uint8_t type, uint8_t channels,
                    uint32_t seq, const uint8_t* payload, uint16_t len) {
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
  std::lock_guard<std::mutex> lock(send_mutex);
  int sent = 0;
  int total = static_cast<int>(frame.size());
  while (sent < total) {
    int n = send(sock, reinterpret_cast<const char*>(frame.data() + sent), total - sent, 0);
    if (n <= 0) return false;
    sent += n;
  }
  return true;
}

bool IsFloatFormat(const WAVEFORMATEX* wfx) {
  if (!wfx) return false;
  if (wfx->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
  if (wfx->wFormatTag == WAVE_FORMAT_EXTENSIBLE && wfx->cbSize >= 22) {
    const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(wfx);
    return ext->SubFormat.Data1 == 0x00000003UL;  // KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
  }
  return false;
}

bool IsPcm16Format(const WAVEFORMATEX* wfx) {
  if (!wfx) return false;
  if (wfx->wFormatTag == WAVE_FORMAT_PCM && wfx->wBitsPerSample == 16) return true;
  if (wfx->wFormatTag == WAVE_FORMAT_EXTENSIBLE && wfx->cbSize >= 22) {
    const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(wfx);
    return ext->SubFormat.Data1 == 0x00000001UL && wfx->wBitsPerSample == 16;
  }
  return false;
}

}  // namespace

AudioProWinBridge::AudioProWinBridge(flutter::BinaryMessenger* messenger, HWND hwnd)
    : hwnd_(hwnd) {
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
  EmitLog("Windows AudioProWinBridge initialized");
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
          std::lock_guard<std::mutex> lock(config_mutex_);
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
          std::lock_guard<std::mutex> lock(config_mutex_);
          preferred_render_id_ = *id;
        }
      }
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "setVirtualEndpoints") {
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      std::lock_guard<std::mutex> lock(config_mutex_);
      auto mic_it = args->find(flutter::EncodableValue("virtualMicName"));
      if (mic_it != args->end()) {
        if (const auto* val = std::get_if<std::string>(&mic_it->second)) {
          virtual_mic_name_ = *val;
        }
      }
      auto spk_it = args->find(flutter::EncodableValue("virtualSpkName"));
      if (spk_it != args->end()) {
        if (const auto* val = std::get_if<std::string>(&spk_it->second)) {
          virtual_spk_name_ = *val;
        }
      }
    }
    result->Success();
  } else if (method == "setLoopbackEnabled") {
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        if (const auto* enabled = std::get_if<bool>(&it->second)) {
          loopback_enabled_.store(*enabled);
        }
      }
    }
    result->Success();
  } else if (method == "triggerHostPulse") {
    // 250 ms at 48,000 Hz = 12,000 samples
    pulse_frames_remaining_.store(12000);
    result->Success();
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
  HRESULT hr_com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);

  // Always offer an explicit "Disabled (VU Meter Only)" render monitor choice
  {
    flutter::EncodableMap none_entry;
    none_entry[flutter::EncodableValue("id")] = flutter::EncodableValue("");
    none_entry[flutter::EncodableValue("name")] =
        flutter::EncodableValue("None (Virtual Bridge Meter Only)");
    none_entry[flutter::EncodableValue("type")] = flutter::EncodableValue("virtualDriver");
    none_entry[flutter::EncodableValue("isInput")] = flutter::EncodableValue(false);
    none_entry[flutter::EncodableValue("isDefault")] = flutter::EncodableValue(true);
    list.push_back(flutter::EncodableValue(none_entry));
  }

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
            std::string friendly =
                is_input ? "Windows Capture Endpoint" : "Windows Render Endpoint";
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
            entry[flutter::EncodableValue("isDefault")] =
                flutter::EncodableValue(is_input && i == 0);
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
  if (SUCCEEDED(hr_com)) {
    CoUninitialize();
  }
  return list;
}

void AudioProWinBridge::StartBridge(int port, const std::string& local_name) {
  StopBridge();
  running_.store(true);
  EmitLog("Starting Windows bridge on TCP:" + std::to_string(port) +
          " (host=" + local_name + ")");
  adb_thread_ = std::thread(&AudioProWinBridge::AdbUsbWatcherLoop, this, port);
  server_thread_ = std::thread(&AudioProWinBridge::SocketServerLoop, this, port, local_name);
}

void AudioProWinBridge::StopBridge() {
  if (running_.exchange(false)) {
    EmitLog("Stopping Windows bridge");
  }
  if (adb_thread_.joinable()) adb_thread_.join();
  if (server_thread_.joinable()) server_thread_.join();
}

void AudioProWinBridge::AdbUsbWatcherLoop(int port) {
  std::string adb_path = "adb.exe";
  char local_app_data[MAX_PATH] = {0};
  if (GetEnvironmentVariableA("LOCALAPPDATA", local_app_data, MAX_PATH) > 0) {
    std::string sdk_adb = std::string(local_app_data) + "\\Android\\Sdk\\platform-tools\\adb.exe";
    if (GetFileAttributesA(sdk_adb.c_str()) != INVALID_FILE_ATTRIBUTES) {
      adb_path = "\"" + sdk_adb + "\"";
    }
  }
  EmitLog("ADB USB watcher active (binary=" + adb_path + ")");
  int last_adb_state = -999;

  while (running_.load()) {
    std::string cmd = adb_path + " reverse tcp:" + std::to_string(port) +
                      " tcp:" + std::to_string(port);
    STARTUPINFOA si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi{};
    std::vector<char> cmd_buf(cmd.begin(), cmd.end());
    cmd_buf.push_back('\0');
    if (CreateProcessA(nullptr, cmd_buf.data(), nullptr, nullptr, FALSE,
                       CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
      WaitForSingleObject(pi.hProcess, 1500);
      DWORD exit_code = 1;
      GetExitCodeProcess(pi.hProcess, &exit_code);
      CloseHandle(pi.hProcess);
      CloseHandle(pi.hThread);
      int state_code = (exit_code == 0) ? 0 : 1;
      if (state_code != last_adb_state) {
        last_adb_state = state_code;
        if (state_code == 0) {
          EmitLog("adb reverse tcp:" + std::to_string(port) + " active (Android USB tunnel ready)");
        } else {
          EmitLog("adb reverse exited with code " + std::to_string(exit_code) +
                  " (no Android USB device or debugging off)");
        }
      }
    } else if (last_adb_state != -1) {
      last_adb_state = -1;
      EmitLog("adb.exe not found in PATH or Android SDK (iPhone/Wi-Fi/manual tunnel unaffected)");
    }
    for (int i = 0; i < 25 && running_.load(); i++) {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
  }
}

void AudioProWinBridge::SocketServerLoop(int port, std::string local_name) {
  SOCKET listen_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listen_sock == INVALID_SOCKET) {
    EmitLog("Socket creation failed, WSA error=" + std::to_string(WSAGetLastError()));
    EmitStatus("disconnected", "Socket Init Failed", "Port Error");
    return;
  }

  int reuse = 1;
  setsockopt(listen_sock, SOL_SOCKET, SO_REUSEADDR,
             reinterpret_cast<const char*>(&reuse), sizeof(reuse));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = INADDR_ANY;
  addr.sin_port = htons(static_cast<u_short>(port));

  if (bind(listen_sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == SOCKET_ERROR ||
      listen(listen_sock, 4) == SOCKET_ERROR) {
    int err = WSAGetLastError();
    closesocket(listen_sock);
    EmitLog("TCP bind/listen failed on port " + std::to_string(port) +
            " WSA error=" + std::to_string(err));
    EmitStatus("disconnected", "Port Busy (" + std::to_string(port) + ")", "Bind Error");
    return;
  }

  EmitLog("TCP server listening on 0.0.0.0:" + std::to_string(port));

  u_long non_block = 1;
  ioctlsocket(listen_sock, FIONBIO, &non_block);

  while (running_.load()) {
    EmitStatus("connecting", "Awaiting USB Device...", "USB ADB / usbmuxd");
    SOCKET client = INVALID_SOCKET;
    sockaddr_in peer_addr{};
    int peer_len = sizeof(peer_addr);
    while (running_.load() && client == INVALID_SOCKET) {
      client = accept(listen_sock, reinterpret_cast<sockaddr*>(&peer_addr), &peer_len);
      if (client == INVALID_SOCKET) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
      }
    }
    if (!running_.load()) {
      if (client != INVALID_SOCKET) closesocket(client);
      break;
    }

    char ip_buf[INET_ADDRSTRLEN] = {0};
    inet_ntop(AF_INET, &peer_addr.sin_addr, ip_buf, sizeof(ip_buf));
    EmitLog("Client TCP connected from " + std::string(ip_buf) + ":" +
            std::to_string(ntohs(peer_addr.sin_port)));

    u_long blocking = 0;
    ioctlsocket(client, FIONBIO, &blocking);
    int nodelay = 1;
    setsockopt(client, IPPROTO_TCP, TCP_NODELAY,
               reinterpret_cast<const char*>(&nodelay), sizeof(nodelay));

    std::atomic<bool> session_active{true};
    std::mutex send_mutex;

    std::string mic_name;
    std::string spk_name;
    {
      std::lock_guard<std::mutex> lock(config_mutex_);
      mic_name = virtual_mic_name_;
      spk_name = virtual_spk_name_;
    }

    std::string ack_json = "{\"deviceName\":\"" + local_name +
                           "\",\"platform\":\"Windows\",\"virtualMicName\":\"" + mic_name +
                           "\",\"virtualSpkName\":\"" + spk_name + "\"}";
    SendAproPacket(client, send_mutex, 1, 1, 0,
                   reinterpret_cast<const uint8_t*>(ack_json.data()),
                   static_cast<uint16_t>(ack_json.size()));
    EmitLog("Sent APRO handshake ACK to client");
    EmitStatus("connected", "Mobile USB Device", "USB Tunnel");

    // TX Thread: Captures Windows system audio via WASAPI Loopback + Test Pulse -> Phone
    std::thread tx_thread([&]() {
      HRESULT hr_com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      DWORD tx_task = 0;
      HANDLE tx_mmcss = AvSetMmThreadCharacteristicsW(L"Pro Audio", &tx_task);

      IMMDeviceEnumerator* enumerator = nullptr;
      IMMDevice* render_dev = nullptr;
      IAudioClient* loopback_client = nullptr;
      IAudioCaptureClient* capture_client = nullptr;
      WAVEFORMATEX* mix_fmt = nullptr;
      bool loopback_ready = false;

      if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                     __uuidof(IMMDeviceEnumerator),
                                     reinterpret_cast<void**>(&enumerator))) &&
          SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &render_dev)) &&
          SUCCEEDED(render_dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                         reinterpret_cast<void**>(&loopback_client))) &&
          SUCCEEDED(loopback_client->GetMixFormat(&mix_fmt))) {
        if (SUCCEEDED(loopback_client->Initialize(
                AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 200000, 0,
                mix_fmt, nullptr)) &&
            SUCCEEDED(loopback_client->GetService(__uuidof(IAudioCaptureClient),
                                                  reinterpret_cast<void**>(&capture_client))) &&
            SUCCEEDED(loopback_client->Start())) {
          loopback_ready = true;
          EmitLog("WASAPI loopback started (" + std::to_string(mix_fmt->nSamplesPerSec) +
                  " Hz, " + std::to_string(mix_fmt->nChannels) + " ch)");
        } else {
          EmitLog("WASAPI loopback Initialize/Start failed");
        }
      } else {
        EmitLog("WASAPI loopback default render endpoint unavailable");
      }

      std::vector<int16_t> out_accum;
      out_accum.reserve(960);
      uint32_t tx_seq = 1;
      double pulse_phase = 0.0;
      double resample_pos = 0.0;

      while (running_.load() && session_active.load()) {
        bool sent_from_loopback = false;
        if (loopback_ready && loopback_enabled_.load() && capture_client && mix_fmt) {
          UINT32 packet_frames = 0;
          while (SUCCEEDED(capture_client->GetNextPacketSize(&packet_frames)) &&
                 packet_frames > 0 && running_.load() && session_active.load()) {
            BYTE* data = nullptr;
            UINT32 frames = 0;
            DWORD flags = 0;
            if (FAILED(capture_client->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) {
              break;
            }

            const bool is_silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr;
            const int channels = (std::max)(1, static_cast<int>(mix_fmt->nChannels));
            const double step = static_cast<double>(mix_fmt->nSamplesPerSec) / 48000.0;
            const bool is_float = IsFloatFormat(mix_fmt);
            const bool is_pcm16 = IsPcm16Format(mix_fmt);

            while (resample_pos < static_cast<double>(frames)) {
              const size_t idx = static_cast<size_t>(resample_pos);
              const size_t ch_count = static_cast<size_t>(channels);
              double mono = 0.0;
              if (!is_silent) {
                if (is_float) {
                  const float* fptr = reinterpret_cast<const float*>(data);
                  for (size_t c = 0; c < ch_count; c++) {
                    mono += static_cast<double>(fptr[idx * ch_count + c]);
                  }
                  mono /= static_cast<double>(channels);
                } else if (is_pcm16) {
                  const int16_t* sptr = reinterpret_cast<const int16_t*>(data);
                  for (size_t c = 0; c < ch_count; c++) {
                    mono += static_cast<double>(sptr[idx * ch_count + c]) / 32768.0;
                  }
                  mono /= static_cast<double>(channels);
                }
              }

              int rem = pulse_frames_remaining_.load();
              if (rem > 0) {
                mono += 0.35 * std::sin(pulse_phase);
                pulse_phase += 2.0 * 3.141592653589793 * 528.0 / 48000.0;
                if (pulse_phase > 6.283185307179586) pulse_phase -= 6.283185307179586;
                pulse_frames_remaining_.fetch_sub(1);
              }

              mono = std::clamp(mono, -1.0, 1.0);
              out_accum.push_back(static_cast<int16_t>(mono * 32767.0));
              resample_pos += step;
            }
            resample_pos -= static_cast<double>(frames);
            capture_client->ReleaseBuffer(frames);
            sent_from_loopback = true;
          }
        }

        // If loopback is off or idle and a host test pulse was triggered, generate 240-sample frames directly
        if (!sent_from_loopback && pulse_frames_remaining_.load() > 0) {
          for (int i = 0; i < 240; i++) {
            double s = 0.0;
            if (pulse_frames_remaining_.load() > 0) {
              s = 0.35 * std::sin(pulse_phase);
              pulse_phase += 2.0 * 3.141592653589793 * 528.0 / 48000.0;
              if (pulse_phase > 6.283185307179586) pulse_phase -= 6.283185307179586;
              pulse_frames_remaining_.fetch_sub(1);
            }
            out_accum.push_back(static_cast<int16_t>(std::clamp(s, -1.0, 1.0) * 32767.0));
          }
        }

        while (out_accum.size() >= 240 && running_.load() && session_active.load()) {
          double sum_sq = 0.0;
          for (size_t i = 0; i < 240; i++) {
            double norm = static_cast<double>(out_accum[i]) / 32768.0;
            sum_sq += norm * norm;
          }
          latest_output_rms_.store(std::clamp(std::sqrt(sum_sq / 240.0), 0.0, 1.0));

          if (!SendAproPacket(client, send_mutex, 3, 1, tx_seq++,
                              reinterpret_cast<const uint8_t*>(out_accum.data()), 480)) {
            session_active.store(false);
            break;
          }
          out_accum.erase(out_accum.begin(), out_accum.begin() + 240);
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(4));
      }

      if (loopback_ready && loopback_client) loopback_client->Stop();
      if (mix_fmt) CoTaskMemFree(mix_fmt);
      if (capture_client) capture_client->Release();
      if (loopback_client) loopback_client->Release();
      if (render_dev) render_dev->Release();
      if (enumerator) enumerator->Release();
      if (tx_mmcss) AvRevertMmThreadCharacteristics(tx_mmcss);
      if (SUCCEEDED(hr_com)) CoUninitialize();
    });

    // Optional WASAPI Render thread for routing incoming phone mic to a chosen Windows device (e.g. VB-Cable)
    std::thread render_thread([&]() {
      HRESULT hr_com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      std::string active_render_id;
      IMMDeviceEnumerator* enumerator = nullptr;
      IMMDevice* target_dev = nullptr;
      IAudioClient* render_client = nullptr;
      IAudioRenderClient* audio_render = nullptr;
      WAVEFORMATEX* mix_fmt = nullptr;
      UINT32 buf_frames = 0;

      auto closeRender = [&]() {
        if (render_client) {
          render_client->Stop();
          render_client->Release();
          render_client = nullptr;
        }
        if (audio_render) {
          audio_render->Release();
          audio_render = nullptr;
        }
        if (target_dev) {
          target_dev->Release();
          target_dev = nullptr;
        }
        if (mix_fmt) {
          CoTaskMemFree(mix_fmt);
          mix_fmt = nullptr;
        }
      };

      CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                       __uuidof(IMMDeviceEnumerator),
                       reinterpret_cast<void**>(&enumerator));

      while (running_.load() && session_active.load()) {
        std::string desired_id;
        {
          std::lock_guard<std::mutex> lock(config_mutex_);
          desired_id = preferred_render_id_;
        }

        if (desired_id != active_render_id) {
          closeRender();
          active_render_id = desired_id;
          if (!desired_id.empty() && enumerator) {
            std::wstring wid = Utf8ToWide(desired_id);
            if (SUCCEEDED(enumerator->GetDevice(wid.c_str(), &target_dev)) &&
                SUCCEEDED(target_dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                               reinterpret_cast<void**>(&render_client))) &&
                SUCCEEDED(render_client->GetMixFormat(&mix_fmt)) &&
                SUCCEEDED(render_client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 200000, 0,
                                                    mix_fmt, nullptr)) &&
                SUCCEEDED(render_client->GetBufferSize(&buf_frames)) &&
                SUCCEEDED(render_client->GetService(__uuidof(IAudioRenderClient),
                                                    reinterpret_cast<void**>(&audio_render))) &&
                SUCCEEDED(render_client->Start())) {
              EmitLog("WASAPI bridge render endpoint active (" +
                      std::to_string(mix_fmt->nSamplesPerSec) + " Hz, " +
                      std::to_string(mix_fmt->nChannels) + " ch)");
            } else {
              EmitLog("WASAPI bridge render endpoint failed to start");
              closeRender();
            }
          }
        }

        if (audio_render && render_client && mix_fmt && buf_frames > 0) {
          UINT32 padding = 0;
          if (SUCCEEDED(render_client->GetCurrentPadding(&padding)) && buf_frames > padding) {
            UINT32 avail = buf_frames - padding;
            std::vector<int16_t> chunk;
            {
              std::lock_guard<std::mutex> rlock(render_ring_mutex_);
              size_t need = (std::min)(static_cast<size_t>(avail), render_ring_.size());
              if (need > 0) {
                chunk.assign(render_ring_.begin(),
                             render_ring_.begin() + static_cast<std::ptrdiff_t>(need));
                render_ring_.erase(render_ring_.begin(),
                                   render_ring_.begin() + static_cast<std::ptrdiff_t>(need));
              }
            }
            if (!chunk.empty()) {
              BYTE* dst = nullptr;
              UINT32 frames_to_write = static_cast<UINT32>(chunk.size());
              if (SUCCEEDED(audio_render->GetBuffer(frames_to_write, &dst)) && dst) {
                const int channels = (std::max)(1, static_cast<int>(mix_fmt->nChannels));
                if (IsFloatFormat(mix_fmt)) {
                  float* fdst = reinterpret_cast<float*>(dst);
                  for (UINT32 i = 0; i < frames_to_write; i++) {
                    float s = static_cast<float>(chunk[i]) / 32768.0f;
                    for (int c = 0; c < channels; c++) {
                      fdst[i * channels + c] = s;
                    }
                  }
                } else if (IsPcm16Format(mix_fmt)) {
                  int16_t* sdst = reinterpret_cast<int16_t*>(dst);
                  for (UINT32 i = 0; i < frames_to_write; i++) {
                    for (int c = 0; c < channels; c++) {
                      sdst[i * channels + c] = chunk[i];
                    }
                  }
                }
                audio_render->ReleaseBuffer(frames_to_write, 0);
              }
            }
          }
        } else {
          std::lock_guard<std::mutex> rlock(render_ring_mutex_);
          if (render_ring_.size() > 4800) {
            render_ring_.clear();
          }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(4));
      }

      closeRender();
      if (enumerator) enumerator->Release();
      if (SUCCEEDED(hr_com)) CoUninitialize();
    });

    DWORD task_idx = 0;
    HANDLE mmcss = AvSetMmThreadCharacteristicsW(L"Pro Audio", &task_idx);

    uint8_t header[16];
    std::vector<uint8_t> payload(8192);
    auto last_vu = std::chrono::steady_clock::now();
    auto last_rate = std::chrono::steady_clock::now();
    int pps_counter = 0;
    int measured_pps = 0;

    while (running_.load() && session_active.load()) {
      if (!RecvExact(client, header, 16, running_)) break;
      if (header[0] != 0x41 || header[1] != 0x50 || header[2] != 0x52 || header[3] != 0x4F) {
        continue;
      }

      uint8_t type = header[5];
      uint16_t len = static_cast<uint16_t>(header[14]) | (static_cast<uint16_t>(header[15]) << 8);
      if (len == 0) continue;
      if (len > payload.size()) break;

      if (!RecvExact(client, payload.data(), len, running_)) break;

      if (type == 0) {  // handshake JSON from mobile
        std::string json(reinterpret_cast<const char*>(payload.data()), len);
        std::string phone_name = ExtractJsonStringField(json, "deviceName");
        std::string platform = ExtractJsonStringField(json, "platform");
        if (phone_name.empty()) phone_name = "Mobile USB Device";
        std::string transport = platform.empty() ? "USB Tunnel" : ("USB · " + platform);
        EmitLog("Handshake received: peer=" + phone_name + " platform=" + platform);
        EmitStatus("connected", phone_name, transport);
      } else if (type == 2) {  // micPcm from phone
        pps_counter++;
        int samples = len / 2;
        double sum_sq = 0.0;
        double peak = 0.0;
        bool muted = input_muted_.load();

        if (!muted) {
          std::lock_guard<std::mutex> rlock(render_ring_mutex_);
          for (int i = 0; i < samples; i++) {
            int16_t s = static_cast<int16_t>(payload[i * 2] | (payload[i * 2 + 1] << 8));
            double n = static_cast<double>(s) / 32768.0;
            peak = (std::max)(peak, std::abs(n));
            sum_sq += n * n;
            if (render_ring_.size() < 9600) {
              render_ring_.push_back(s);
            }
          }
        }
        double rms = (!muted && samples > 0) ? std::sqrt(sum_sq / samples) : 0.0;

        auto now = std::chrono::steady_clock::now();
        if (std::chrono::duration_cast<std::chrono::milliseconds>(now - last_rate).count() >= 1000) {
          measured_pps = pps_counter;
          pps_counter = 0;
          last_rate = now;
        }
        if (std::chrono::duration_cast<std::chrono::milliseconds>(now - last_vu).count() >= 33) {
          last_vu = now;
          double out_rms = latest_output_rms_.exchange(latest_output_rms_.load() * 0.85);
          EmitVu(rms, peak, out_rms, 2.4, measured_pps > 0 ? measured_pps : 200);
        }
      }
    }

    session_active.store(false);
    if (tx_thread.joinable()) tx_thread.join();
    if (render_thread.joinable()) render_thread.join();
    if (mmcss) AvRevertMmThreadCharacteristics(mmcss);
    closesocket(client);
    EmitLog("Client session ended; returning to listen state");
    EmitStatus("disconnected", "Awaiting USB Device...", "USB Disconnected");
  }

  closesocket(listen_sock);
}

void AudioProWinBridge::EnqueueEvent(bool is_vu, flutter::EncodableMap map) {
  {
    std::lock_guard<std::mutex> lock(event_mutex_);
    if (is_vu) {
      // Keep VU stream snappy without unbounded backlog
      if (pending_events_.size() > 16) {
        pending_events_.pop_front();
      }
    }
    pending_events_.push_back(PendingEvent{is_vu, std::move(map)});
  }
  if (hwnd_ != nullptr) {
    PostMessageW(hwnd_, kWmDrainEvents, 0, 0);
  }
}

void AudioProWinBridge::DrainPendingEvents() {
  std::deque<PendingEvent> batch;
  {
    std::lock_guard<std::mutex> lock(event_mutex_);
    batch.swap(pending_events_);
  }

  std::lock_guard<std::mutex> slock(sink_mutex_);
  for (const auto& ev : batch) {
    if (ev.is_vu) {
      if (vu_sink_) {
        vu_sink_->Success(flutter::EncodableValue(ev.payload));
      }
    } else {
      if (usb_sink_) {
        usb_sink_->Success(flutter::EncodableValue(ev.payload));
      }
    }
  }
}

void AudioProWinBridge::EmitStatus(const std::string& status, const std::string& peer_name,
                                   const std::string& transport) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("status")] = flutter::EncodableValue(status);
  map[flutter::EncodableValue("peerName")] = flutter::EncodableValue(peer_name);
  map[flutter::EncodableValue("transport")] = flutter::EncodableValue(transport);
  EnqueueEvent(false, std::move(map));
}

void AudioProWinBridge::EmitLog(const std::string& message) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("status")] = flutter::EncodableValue("log");
  map[flutter::EncodableValue("source")] = flutter::EncodableValue("WIN-C++");
  map[flutter::EncodableValue("message")] = flutter::EncodableValue(message);
  EnqueueEvent(false, std::move(map));
}

void AudioProWinBridge::EmitVu(double in_rms, double in_peak, double out_rms,
                               double jitter_ms, int pps) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("inputRms")] = flutter::EncodableValue(in_rms);
  map[flutter::EncodableValue("inputPeak")] = flutter::EncodableValue(in_peak);
  map[flutter::EncodableValue("outputRms")] = flutter::EncodableValue(out_rms);
  map[flutter::EncodableValue("latencyMs")] = flutter::EncodableValue(19.4);
  map[flutter::EncodableValue("jitterMs")] = flutter::EncodableValue(jitter_ms);
  map[flutter::EncodableValue("packetsPerSecond")] = flutter::EncodableValue(pps);
  map[flutter::EncodableValue("packetLossPct")] = flutter::EncodableValue(0.0);
  EnqueueEvent(true, std::move(map));
}
