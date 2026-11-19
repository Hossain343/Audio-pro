#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include "audio_pro_bridge.h"
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <memory>

class FlutterWindow {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  ~FlutterWindow();

  bool Create(const std::wstring& title, const POINT& origin, const SIZE& size);
  void Show();

 private:
  static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                  WPARAM const wparam, LPARAM const lparam) noexcept;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept;

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<AudioProWinBridge> audio_bridge_;
  HWND window_handle_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
