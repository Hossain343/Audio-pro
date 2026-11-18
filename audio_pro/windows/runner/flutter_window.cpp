#include "flutter_window.h"
#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  audio_bridge_.reset();
  flutter_controller_.reset();
}

bool FlutterWindow::Create(const std::wstring& title, const POINT& origin,
                           const SIZE& size) {
  WNDCLASSW wc{};
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = L"FLUTTER_RUNNER_WIN32_WINDOW";
  RegisterClassW(&wc);

  window_handle_ = CreateWindowW(
      wc.lpszClassName, title.c_str(), WS_OVERLAPPEDWINDOW,
      origin.x, origin.y, size.cx, size.cy,
      nullptr, nullptr, wc.hInstance, this);
  if (!window_handle_) return false;

  RECT frame;
  GetClientRect(window_handle_, &frame);
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  RegisterPlugins(flutter_controller_->engine());
  audio_bridge_ = std::make_unique<AudioProWinBridge>(
      flutter_controller_->engine()->messenger());

  SetParent(flutter_controller_->view()->GetNativeWindow(), window_handle_);
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::Show() {
  ShowWindow(window_handle_, SW_SHOWNORMAL);
}

LRESULT CALLBACK FlutterWindow::WndProc(HWND const window, UINT const message,
                                        WPARAM const wparam, LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
  }
  auto* that = reinterpret_cast<FlutterWindow*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (that) {
    return that->MessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT FlutterWindow::MessageHandler(HWND window, UINT const message,
                                      WPARAM const wparam, LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(window, message, wparam, lparam);
    if (result) return *result;
  }
  switch (message) {
    case WM_SIZE:
      if (flutter_controller_ && flutter_controller_->view()) {
        RECT r;
        GetClientRect(window, &r);
        MoveWindow(flutter_controller_->view()->GetNativeWindow(),
                   0, 0, r.right - r.left, r.bottom - r.top, TRUE);
      }
      return 0;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}
