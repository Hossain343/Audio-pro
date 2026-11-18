#ifndef AUDIO_PRO_BRIDGE_H_
#define AUDIO_PRO_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class AudioProWinBridge {
 public:
  explicit AudioProWinBridge(flutter::BinaryMessenger* messenger);
  ~AudioProWinBridge();

  void StartBridge(int port, const std::string& local_name);
  void StopBridge();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::EncodableList EnumerateWasapiEndpoints();
  void AdbUsbWatcherLoop(int port);
  void SocketServerLoop(int port, std::string local_name);
  void EmitStatus(const std::string& status, const std::string& peer_name,
                  const std::string& transport);
  void EmitVu(double in_rms, double in_peak, double out_rms);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> vu_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> usb_channel_;

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> vu_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> usb_sink_;
  std::mutex sink_mutex_;

  std::atomic<bool> running_{false};
  std::atomic<bool> input_muted_{false};
  std::atomic<float> output_gain_{0.85f};
  std::string preferred_render_id_;
  std::string preferred_capture_id_;

  std::thread adb_thread_;
  std::thread server_thread_;
};

#endif  // AUDIO_PRO_BRIDGE_H_
