import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @State private var text: String = ""
    @State private var isInputVisible: Bool = true
    @FocusState private var isFocused: Bool
    #if os(macOS)
    @State private var isFullScreen: Bool = false
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
                    Color.white
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
                        // Centered Placeholder
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("Type something...")
                                    .font(settings.font.font(size: 80, weight: .bold)) // Adjusted size, in the chosen typeface
                                    .foregroundColor(.secondary.opacity(0.3))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.3) // On a narrow iPhone screen, shrink rather than split a word
                                    .fixedSize(horizontal: false, vertical: true) // Allow wrapping if needed
                                Spacer()
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if settings.scrollEnabled {
                        // Text keeps a large size and scrolls across (and off) the screen
                        ScrollingTextView(
                            text: text,
                            font: settings.font,
                            weight: settings.weight,
                            direction: settings.scrollDirection,
                            speed: settings.scrollSpeed,
                            sizeScale: settings.scrollTextSize
                        )
                        .id(settings.scrollDirection) // Start again from the edge when the direction changes
                        .foregroundColor(.black)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: toggleInputPanel)
                        .ignoresSafeArea() // Run edge to edge: under the iPhone's notch and home indicator, and behind the keyboard
                    } else {
                        // Text fills the entire available space, measured by the glyphs themselves
                        FillingTextView(text: text, font: settings.font, weight: settings.weight)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: toggleInputPanel)
                    }
                }
            }
            // On the white full-screen background, use Light Mode colors even in Dark Mode
            .environment(\.colorScheme, isFullScreen ? .light : colorScheme)

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
                        SettingsButton {
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
                    .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 10)
                    .padding(.bottom, 50)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 700)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
        // Style this view's own window. (NSApp.windows.first could be the Settings window.)
        .background(HostingWindowReader { window in
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true

            // Initial check
            let startsFullScreen = window.styleMask.contains(.fullScreen)
            DispatchQueue.main.async { isFullScreen = startsFullScreen }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            withAnimation { isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation { isFullScreen = false }
        }
        #else
        // Use the whole screen: no status bar, and the home indicator fades when not in use
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
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

    // Tapping the big text shows or hides the input panel
    private func toggleInputPanel() {
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
