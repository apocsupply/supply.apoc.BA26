import SwiftUI

// MARK: - BA26App
/// Entry point.  Registers the AppDelegate (for audio-session configuration)
/// and presents the full-screen RootView.

@main
struct BA26App: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
