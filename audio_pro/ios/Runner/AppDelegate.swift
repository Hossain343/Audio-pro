import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var audioBridge: AudioEngineBridge?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        ensureBridgeInitialized()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        ensureBridgeInitialized()
    }

    private func ensureBridgeInitialized() {
        guard audioBridge == nil,
              let controller = window?.rootViewController as? FlutterViewController else {
            return
        }
        audioBridge = AudioEngineBridge(messenger: controller.binaryMessenger)
    }
}
