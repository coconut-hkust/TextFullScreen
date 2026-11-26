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
        .commands {
            // ⌘, opens the settings inside the window when it's full screen
            CommandGroup(replacing: .appSettings) { SettingsMenuItem() }

            // App menu ▸ About TextFullScreen, with a Get Support link under the version
            CommandGroup(replacing: .appInfo) {
                Button("About TextFullScreen") { showAboutPanel() }
            }

            // Help ▸ Get Support opens the app's GitHub page
            CommandGroup(replacing: .help) {
                Link("Get Support", destination: supportURL)
            }
        }
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

/// Where people get help with the app: its GitHub page.
let supportURL = URL(string: "https://github.com/coconut-hkust/TextFullScreen")!

#if os(macOS)
import AppKit

/// The standard About window, with a centred Get Support link to GitHub under the version.
@MainActor
private func showAboutPanel() {
    let centred = NSMutableParagraphStyle()
    centred.alignment = .center
    let credits = NSAttributedString(string: "Get Support", attributes: [
        .link: supportURL,
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .paragraphStyle: centred,
    ])
    NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    NSApplication.shared.activate()
}
#endif
