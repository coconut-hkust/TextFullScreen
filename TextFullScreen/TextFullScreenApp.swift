import SwiftUI

@main
struct TextFullScreenApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .onAppear {
                    // Optional: Set window to transparent or specific style if needed
                    // For standard app, default is fine.
                }
                #endif
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle()) // Modern frameless look
        #endif

        #if os(macOS)
        // App menu ▸ Settings… (⌘,): font and scrolling options
        Settings {
            SettingsView()
        }
        .defaultSize(width: 460, height: 620)
        .windowResizability(.contentSize) // Fixed width; height between the view's minimum and maximum
        #endif
    }
}
