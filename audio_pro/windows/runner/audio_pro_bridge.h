#ifndef AUDIO_PRO_BRIDGE_H_
#define AUDIO_PRO_BRIDGE_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class AudioProWinBridge {
 public:
  static constexpr UINT kWmDrainEvents = WM_APP + 101;

  explicit AudioProWinBridge(flutter::BinaryMessenger* messenger, HWND hwnd = nullptr);
  ~AudioProWinBridge();

  void StartBridge(const std::string& bind_ip, int port, const std::string& local_name);
  void StopBridge();
  void DrainPendingEvents();

 private:
  struct PendingEvent {
    bool is_vu;
    flutter::EncodableMap payload;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::EncodableList EnumerateWasapiEndpoints();
  flutter::EncodableList GetLocalIpv4Adapters();
  flutter::EncodableMap TestEndpointAvailability(const std::string& ip, int port);
  void AdbUsbWatcherLoop(int port);
  void UsbmuxdUsbWatcherLoop(int port, std::string local_name);
  void SocketServerLoop(std::string bind_ip, int port, std::string local_name);
  void RunBridgeSession(uintptr_t sock_handle, const std::string& local_name,
                        const std::string& transport_hint);

  void EmitStatus(const std::string& status, const std::string& peer_name,
                  const std::string& transport);
  void EmitLog(const std::string& message);
  void EmitVu(double in_rms, double in_peak, double out_rms, double jitter_ms, int pps);
  void EnqueueEvent(bool is_vu, flutter::EncodableMap map);

  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> vu_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> usb_channel_;

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> vu_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> usb_sink_;
  std::mutex sink_mutex_;

  std::mutex event_mutex_;
  std::deque<PendingEvent> pending_events_;

  std::mutex config_mutex_;
  std::string bind_ip_ = "0.0.0.0";
  int active_port_ = 38900;
  std::string preferred_render_id_;
  std::string preferred_capture_id_;
  std::string virtual_mic_name_ = "AudioPro Virtual Mic";
  std::string virtual_spk_name_ = "AudioPro Virtual Speaker";

  std::mutex render_ring_mutex_;
  std::deque<int16_t> render_ring_;

  std::atomic<bool> running_{false};
  std::atomic<bool> listener_active_{false};
  std::atomic<bool> session_busy_{false};
  std::atomic<bool> input_muted_{false};
  std::atomic<bool> loopback_enabled_{true};
  std::atomic<float> output_gain_{0.85f};
  std::atomic<int> pulse_frames_remaining_{0};
  std::atomic<double> latest_output_rms_{0.0};

  std::thread adb_thread_;
  std::thread usbmux_thread_;
  std::thread server_thread_;
};

#endif  // AUDIO_PRO_BRIDGE_H_
