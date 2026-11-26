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

            // Help ▸ Get Support opens the app's GitHub page; Send Feedback opens the feedback form
            CommandGroup(replacing: .help) {
                Link("Get Support", destination: supportURL)
                Link("Send Feedback", destination: feedbackURL)
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

/// The app's licence text on GitHub.
let licenseURL = URL(string: "https://github.com/coconut-hkust/TextFullScreen/blob/main/LICENSE.md")!

/// The developer's GitHub profile.
let developerURL = URL(string: "https://github.com/coconut-hkust")!

/// Where people send ideas and problems: the TextFullScreen Feedback Google Form.
let feedbackURL = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSedmBLQH6dR3TXbgIk9d6yJqk8UNzXldvfZYBfv9NcqmSQ2CA/viewform")!

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
