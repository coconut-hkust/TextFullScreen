import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @State private var text: String = ""
    @State private var isInputVisible: Bool = true
    /// Where the top of the input panel is on screen (in the window's coordinates), once laid out
    @State private var inputPanelTop: CGFloat?
    @FocusState private var isFocused: Bool
    #if os(macOS)
    @State private var isFullScreen: Bool = false
    /// The settings shown inside this window, as they are while it's full screen.
    @State private var isSettingsSheetShown = false
    @State private var hostWindow: NSWindow?
    @State private var windowHeight: CGFloat = 600
    #else
    @State private var isFullScreen: Bool = true // iPhone and iPad apps always fill the screen, so they get the full-screen look
    #endif
    @Environment(\.colorScheme) private var colorScheme
    /// Font and scrolling preferences, shared with the Settings window.
    private var settings = DisplaySettings()

    var body: some View {
        ZStack {
            // 1. Background Handling
            Group {
                if isFullScreen {
                    settings.appScheme == .dark ? Color(white: 0.075) : Color.white
                } else {
                    ZStack {
                        // "Liquid Glass" Transparent Effect
                        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                        Color.white.opacity(0.1)
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            // 2. Main Content (The Large Text)
            GeometryReader { geometry in
                ZStack {
                    if text.isEmpty {
                        // The placeholder, centered by its drawn letters (from the top of "T" to the
                        // bottom of "g"), so there's as much space above it as below. Centering a
                        // Text by its line boxes left it low, as they hold room above capitals and
                        // below the last baseline. It breaks onto two rows on a narrow screen.
                        FillingTextView(
                            text: geometry.size.width < geometry.size.height ? "type\nsomething..." : "type something...",
                            font: .standard, // Always SF Pro, whatever typeface is chosen for the text
                            weight: .bold,
                            fill: 0.9,
                            color: placeholderColor,
                            maxFontSize: 80
                        )
                        .offset(y: -placeholderLift(in: geometry.frame(in: .global)))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        #if !os(macOS)
                        // With nothing typed yet, a tap only puts the keyboard away
                        .contentShape(Rectangle())
                        .onTapGesture { isFocused = false }
                        #endif
                    } else if settings.scrollEnabled {
                        // Text keeps a large size and scrolls across (and off) the screen
                        ScrollingTextView(
                            text: text,
                            font: settings.font,
                            weight: settings.weight,
                            direction: settings.scrollDirection,
                            speed: settings.scrollSpeed,
                            sizeScale: settings.scrollSizeInUse,
                            keepsRows: settings.panKeepsRows,
                            gradient: settings.gradient
                        )
                        .id(settings.scrollDirection) // Start again from the edge when the direction changes
                        .foregroundColor(settings.color.color)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: toggleInputPanel)
                        .ignoresSafeArea() // Run edge to edge: under the iPhone's notch and home indicator, and behind the keyboard
                    } else {
                        // Text fills the entire available space, measured by the glyphs themselves
                        FillingTextView(
                            text: text,
                            font: settings.font,
                            weight: settings.weight,
                            fill: CGFloat(settings.fillPercent) / 100,
                            color: settings.color.color,
                            gradient: settings.gradient
                        )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: toggleInputPanel)
                    }
                }
            }
            #if !os(macOS)
            // Measure from the very top of the screen (above the camera) to the very bottom (below
            // the home indicator), in either orientation, so the text fills the whole screen and the
            // placeholder sits in its true middle. The keyboard is still kept clear of.
            .ignoresSafeArea(.container)
            #endif
            // On the white full-screen background, use Light Mode colors even in Dark Mode, unless
            // the appearance is set to Light or Dark on the color pad
            .environment(\.colorScheme, textColorScheme)

            // 3. The Floating Glass Input Panel
            if isInputVisible {
                VStack {
                    Spacer() // Push to bottom
                    
                    HStack(alignment: .center, spacing: 0) {
                        // Input Area
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty && !isFocused {
                                Text("Write something...")
                                    .font(.system(size: 18, weight: .medium, design: .default))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 5)
                                    .padding(.top, textEditorInset)
                                    .offset(x: 0, y: 0)
                            }
                            
                            TextEditor(text: $text)
                                .focused($isFocused)
                                .font(.system(size: 18, weight: .medium, design: .default))
                                .foregroundColor(.primary)
                                .scrollContentBackground(.hidden)
                                .frame(height: inputFrameHeight)
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading) // Take the free width, keeping the buttons at the right edge

                        // Clear Button
                        if !text.isEmpty {
                            Button(action: {
                                withAnimation {
                                    text = ""
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 15)
                                    .padding(.trailing, 12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Settings Button (font, scrolling)
                        SettingsButton(openInWindow: settingsInWindowAction) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                                .padding([.vertical, .trailing], 15)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Settings")
                    }
                    .background(
                        ZStack {
                            VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
                            Color.white.opacity(0.2)
                        }
                    )
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { inputPanelTop = $0 }
                    .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 10)
                    .padding(.bottom, 50)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 700)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .preferredColorScheme(settings.appScheme.colorScheme)
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
        // Style this view's own window. (NSApp.windows.first could be the Settings window.)
        .background(HostingWindowReader { window in
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            DispatchQueue.main.async { hostWindow = window }

            // Initial check. A window brought back in full screen when the app reopens only becomes
            // full screen a moment later, and gets no "did enter" notice, so look again shortly after.
            for delay in [0.0, 0.5, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
                    guard let window else { return }
                    let fullScreen = window.styleMask.contains(.fullScreen)
                    if fullScreen != isFullScreen { isFullScreen = fullScreen }
                }
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            withAnimation { isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation { isFullScreen = false }
        }
        // A window the system brings back in full screen (when the app reopens) gets no "did enter"
        // notice, so check again whenever this window changes size or comes to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
            recheckFullScreen(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            recheckFullScreen(note)
        }
        // ⌘, while this window is full screen
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsInWindow)) { note in
            if let window = note.object as? NSWindow, window === hostWindow {
                isSettingsSheetShown = true
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { windowHeight = $0 }
        .sheet(isPresented: $isSettingsSheetShown) {
            SettingsSheet(windowHeight: windowHeight)
        }
        #else
        // Use the whole screen: no status bar, and the home indicator fades when not in use
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }
    
    #if os(macOS)
    private func recheckFullScreen(_ note: Notification) {
        guard let window = note.object as? NSWindow, window === hostWindow else { return }
        let fullScreen = window.styleMask.contains(.fullScreen)
        if fullScreen != isFullScreen { isFullScreen = fullScreen }
    }
    #endif

    /// How far to raise the placeholder from the middle of `area`. On iPhone it's centered in the
    /// space between the top of the screen and the top of the input panel, so it doesn't look low
    /// above the panel. With the panel hidden, and on iPad and Mac, it stays in the middle.
    private func placeholderLift(in area: CGRect) -> CGFloat {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .phone, isInputVisible,
              let panelTop = inputPanelTop, panelTop > area.minY, panelTop < area.maxY else { return 0 }
        return area.midY - (area.minY + panelTop) / 2
        #else
        0
        #endif
    }

    /// The system's secondary label color, faded, for the placeholder
    private var placeholderColor: Color {
        textColorScheme == .dark
            ? Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.6 * 0.3)
            : Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.6 * 0.3)
    }

    private var textColorScheme: ColorScheme {
        switch settings.appScheme {
        case .auto: isFullScreen ? .light : colorScheme
        case .light: .light
        case .dark: .dark
        }
    }

    /// In full screen the settings open inside this window; otherwise in the Settings window.
    private var settingsInWindowAction: (() -> Void)? {
        #if os(macOS)
        let windowIsFullScreen = isFullScreen || hostWindow?.styleMask.contains(.fullScreen) == true
        return windowIsFullScreen ? { isSettingsSheetShown = true } : nil
        #else
        nil
        #endif
    }

    // Dynamic height calculation for the input box
    private var inputFrameHeight: CGFloat {
        let lineCount = text.filter { $0 == "\n" }.count + 1
        let insets = 2 * textEditorInset
        if lineCount == 1 { return 24 + insets }
        if lineCount == 2 { return 48 + insets }
        return 72 + insets // Max height for 3 lines
    }

    // Space the text editor leaves above (and below) its text
    private var textEditorInset: CGFloat {
        #if os(macOS)
        return 0
        #else
        return 8 // UIKit's text view leaves 8 points above and below the text
        #endif
    }

    // Tapping the big text shows or hides the input panel. On iPhone and iPad, while the keyboard
    // is up, the first tap only puts the keyboard away (an iPhone keyboard has no key for it), and
    // the next tap hides the panel.
    private func toggleInputPanel() {
        #if !os(macOS)
        if isFocused {
            isFocused = false
            return
        }
        #endif
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            isInputVisible.toggle()
        }
    }
}

#if os(macOS)
// MARK: - Hosting Window Access
/// Hands over the window this view is placed in, once it's in one.
struct HostingWindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class ReportingView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
#endif

#if os(macOS)
// MARK: - Visual Effect Blur (The Glass Engine)
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        visualEffectView.isEmphasized = true
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#else
// MARK: - Visual Effect Blur (iPhone and iPad)
/// The UIKit version of the glass. It takes the same material names as the Mac version, so the
/// views above work unchanged. UIKit can only blur what's inside the app itself, so the blending
/// mode makes no difference here.
struct VisualEffectBlur: UIViewRepresentable {
    enum Material { case hudWindow, popover }
    enum BlendingMode { case behindWindow, withinWindow }

    var material: Material
    var blendingMode: BlendingMode

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: blurEffect)
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = blurEffect
    }

    private var blurEffect: UIBlurEffect {
        switch material {
        case .hudWindow: UIBlurEffect(style: .systemThinMaterial)
        case .popover: UIBlurEffect(style: .systemMaterial)
        }
    }
}
#endif

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
