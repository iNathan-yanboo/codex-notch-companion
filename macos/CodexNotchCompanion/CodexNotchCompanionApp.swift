import SwiftUI

@main
struct CodexNotchCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Keep a Settings scene so the App protocol is satisfied; the real UI
        // is a dedicated NSWindow opened from the notch panel gear button.
        Settings {
            EmptyView()
        }
    }
}
