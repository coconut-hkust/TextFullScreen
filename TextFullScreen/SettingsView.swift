import SwiftUI

/// The app's settings: the typeface, and whether text that doesn't fit shrinks or scrolls.
/// On macOS this fills the Settings window (⌘,). On iPhone and iPad, `SettingsButton` shows it in a sheet.
struct SettingsView: View {
    private var settings = DisplaySettings()
    @State private var isColorPadShown = false
    @State private var isGradientPadShown = false
    @State private var isConfirmingDefaults = false

    var body: some View {
        Form {
            Section("Font") {
                FontPicker(selection: settings.$font)

                Picker("Weight", selection: settings.$weight) {
                    ForEach(TextWeight.allCases) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                }

                LabeledContent("Color") {
                    Button { isColorPadShown.toggle() } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(settings.color.color)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.5)))
                            .frame(width: 44, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Choose the text color")
                    .accessibilityLabel("Text color, \(settings.color.hex)")
                    .popover(isPresented: $isColorPadShown, arrowEdge: .trailing) {
                        ColorPadView()
                            .fittedSheetOnPhone()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Colors")
                    SavedColorsView()
                    Text("Click + to save the current color. To remove one, right-click it, or drag it away from its spot and let go. These are the same colors as in the color pad.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                previewText("The quick brown fox")
                    .font(settings.font.font(size: 34, weight: settings.weight))
                    .textFill(settings.gradient, plain: settings.color.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Font preview")
            }

            gradientSection

            Section {
                Toggle("Separate maximum size for moving", isOn: settings.$separateScrollSize)

                Toggle("Moving", isOn: settings.$scrollEnabled)

                // Shared by both layouts unless scrolling has its own, shown in the Scrolling section
                if !settings.scrollEnabled || !settings.separateScrollSize {
                    percentControl("Maximum size", value: settings.$fillPercent, in: DisplaySettings.fillPercentRange)
                }
            } header: {
                Text("Layout")
            } footer: {
                Text(layoutFooter)
            }

            if settings.scrollEnabled {
                scrollingSection
            }

            savedSection
        }
        .formStyle(.grouped)
        .preferredColorScheme(settings.appScheme.colorScheme)
        #if os(macOS)
        // A set height, with the settings scrolling inside it. The window can be dragged taller or shorter.
        .frame(width: 460)
        .frame(minHeight: 360, idealHeight: 620, maxHeight: .infinity)
        #endif
    }

    /// The preview line, colored per character or word when the gradient does that.
    private func previewText(_ string: String) -> Text {
        if let gradient = settings.gradient, gradient.style != .whole {
            Text(gradient.attributedString(string))
        } else {
            Text(verbatim: string)
        }
    }

    /// A switch for painting the text with a gradient, and how the gradient is laid over it.
    private var gradientSection: some View {
        Section {
            Toggle("Gradient", isOn: settings.$gradientEnabled)

            if settings.gradientEnabled {
                LabeledContent("Colors") {
                    Button { isGradientPadShown.toggle() } label: {
                        Capsule()
                            .fill(settings.gradientColors.isEmpty
                                  ? AnyShapeStyle(.quaternary)
                                  : AnyShapeStyle(LinearGradient(colors: settings.gradientColors.map(\.color), startPoint: .leading, endPoint: .trailing)))
                            .overlay(Capsule().strokeBorder(.secondary.opacity(0.5)))
                            .frame(width: 96, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Choose the gradient colors")
                    .accessibilityLabel("Gradient colors, \(settings.gradientColors.map(\.hex).joined(separator: ", "))")
                    .popover(isPresented: $isGradientPadShown, arrowEdge: .trailing) {
                        GradientPadView()
                            .fittedSheetOnPhone()
                    }
                }

                Picker("Style", selection: settings.$gradientStyle) {
                    ForEach(GradientStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if settings.gradientStyle == .whole {
                    Picker("Background", selection: settings.$gradientAnchor) {
                        ForEach(GradientAnchor.allCases) { anchor in
                            Text(anchor.displayName).tag(anchor)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Direction", selection: settings.$gradientDirection) {
                        ForEach(GradientDirection.allCases) { direction in
                            Text(direction.displayName)
                                .accessibilityLabel(direction.accessibilityName)
                                .tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Toggle("Repeat the gradient", isOn: settings.$gradientRepeats)

                    if settings.gradientRepeats {
                        shadesBetweenControl
                    }
                }
            }
        } header: {
            Text("Gradient")
        } footer: {
            Text(gradientFooter)
        }
    }

    /// The number of in-between shades: typed into the box, or nudged with the arrows.
    private var shadesBetweenControl: some View {
        let range = TextGradient.shadesBetweenRange
        let clamped = Binding<Int>(
            get: { settings.gradientShadesBetween },
            set: { settings.gradientShadesBetween = min(max($0, range.lowerBound), range.upperBound) }
        )
        return LabeledContent("Shades between colors") {
            HStack(spacing: 6) {
                TextField("Shades", value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                    #if !os(macOS)
                    .keyboardType(.numberPad)
                    #endif
                Stepper("Shades between colors", value: clamped, in: range)
                    .labelsHidden()
            }
        }
    }

    private var gradientFooter: String {
        guard settings.gradientEnabled else { return "Paints the text with several colors instead of one." }
        guard !settings.gradientColors.isEmpty else { return "Click Colors and add a color to the pad. Until then the text keeps its plain color." }
        let unit = settings.gradientStyle == .perWord ? "word" : "character"
        switch settings.gradientStyle {
        case .whole:
            return settings.gradientAnchor == .screen
                ? "One big gradient fills the screen behind the text, and only shows through the letters. Moving letters pass over its colors."
                : "One gradient is stretched over the text and moves along with it."
        case .perCharacter, .perWord:
            return settings.gradientRepeats
                ? "Each \(unit) has one color. There are \(settings.gradientShadesBetween) in-between shades from one chosen color to the next, then the colors start over."
                : "Each \(unit) has one color, spread once from the first color to the last over all the text."
        }
    }

    /// Shown only while scrolling is on: pan or rise, which way, how fast and how big.
    private var scrollingSection: some View {
        Section {
            Picker("Motion", selection: settings.$motion) {
                ForEach(ScrollMotion.allCases) { motion in
                    Text(motion.displayName).tag(motion)
                }
            }
            .pickerStyle(.segmented)

            switch settings.motion {
            case .pan:
                Picker("Direction", selection: settings.$panDirection) {
                    ForEach(PanDirection.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Keep rows", isOn: settings.$panKeepsRows)
            case .rise:
                Picker("Direction", selection: settings.$riseDirection) {
                    ForEach(RiseDirection.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
            }

            titled("Speed") {
                Slider(value: speedOnDoublingScale, in: log2(DisplaySettings.scrollSpeedRange.lowerBound)...log2(DisplaySettings.scrollSpeedRange.upperBound)) {
                    Text("Speed")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
            }

            if settings.separateScrollSize {
                percentControl("Maximum size", value: scrollSizePercent, in: scrollSizePercentRange)
            }
        } header: {
            Text("Moving")
        } footer: {
            Text(settings.motion == .pan
                 ? (settings.panKeepsRows
                    ? "Each row pans on its own line, all at the same time. Start a new row with \(newRowKey). At 100% the rows together are as tall as the screen allows."
                    : "Pan runs the text along one line, joining the rows. At 100% it's as tall as the screen allows.")
                 : "Rise wraps the text to the screen width. At 100%, the longest word just fits across the screen.")
        }
    }

    /// A percentage picked with a slider, or typed into the box on its right. Typed values are kept
    /// within `range`.
    private func percentControl(_ title: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        let clamped = Binding<Int>(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
        let sliderValue = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { clamped.wrappedValue = Int($0.rounded()) }
        )
        return titled(title) {
            HStack(spacing: 12) {
                Slider(value: sliderValue, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
                    Text(title)
                }

                HStack(spacing: 2) {
                    TextField("Percent", value: clamped, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .textFieldStyle(.roundedBorder)
                        #if !os(macOS)
                        .keyboardType(.numberPad)
                        #endif
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The key that starts a new row in the text box.
    private var newRowKey: String {
        #if os(macOS)
        "Shift-Return"
        #else
        "Return"
        #endif
    }

    private var layoutFooter: String {
        let mode = settings.scrollEnabled
            ? "Text stays large and moves across the screen."
            : "Text shrinks until all of it fits on the screen. Maximum size is how much of the screen's width and height it may fill."
        let sharing = settings.separateScrollSize
            ? "Moving text has its own maximum size."
            : "The same maximum size is used whether the text moves or not."
        return mode + " " + sharing
    }

    /// The scrolling text size as a whole percentage (stored as a fraction of the largest size).
    private var scrollSizePercent: Binding<Int> {
        Binding(
            get: { Int((settings.scrollTextSize * 100).rounded()) },
            set: { settings.scrollTextSize = Double($0) / 100 }
        )
    }

    private var scrollSizePercentRange: ClosedRange<Int> {
        Int(DisplaySettings.scrollTextSizeRange.lowerBound * 100)...Int(DisplaySettings.scrollTextSizeRange.upperBound * 100)
    }

    /// A slider row with its name showing. The Mac shows a slider's own label beside it; iPhone
    /// and iPad don't show it at all, so there the name goes above the slider.
    @ViewBuilder
    private func titled<Content: View>(_ title: LocalizedStringKey, @ViewBuilder slider: () -> Content) -> some View {
        #if os(macOS)
        slider()
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            slider()
        }
        #endif
    }

    /// The app's defaults, then three slots that each keep a copy of every setting above.
    private var savedSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Settings")
                    Text("SF Pro · Black · 100% · no saved colors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Load") { isConfirmingDefaults = true }
                    .confirmationDialog("Load the default settings?", isPresented: $isConfirmingDefaults) {
                        Button("Load Defaults", role: .destructive) { settings.loadDefaults() }
                    } message: {
                        Text("The font, color, gradient, size and moving settings go back to how the app first starts, and all saved colors are removed. Your saved slots are kept.")
                    }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            ForEach(1...DisplaySettings.slotCount, id: \.self) { slot in
                let saved = settings.saved(inSlot: slot)
                HStack(spacing: 10) {
                    Circle()
                        .fill(saved.flatMap { TextColor(rawValue: $0.color) }?.color ?? .clear)
                        .overlay(Circle().stroke(.secondary.opacity(0.4)))
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Slot \(slot)")
                        Text(saved?.summary ?? "Empty")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Load") { settings.load(fromSlot: slot) }
                        .disabled(saved == nil)
                    Button("Save") { settings.save(toSlot: slot) }
                    Button(role: .destructive) {
                        settings.clear(slot: slot)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(saved == nil)
                    .help("Clear slot \(slot)")
                    .accessibilityLabel("Clear slot \(slot)")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } header: {
            Text("Saved Settings")
        } footer: {
            Text("Save keeps a copy of the current font, color, saved colors, gradient, size and moving settings. Load brings them back.")
        }
    }

    /// The speed slider moves on a doubling scale, so the middle of the track is normal speed,
    /// the left end a quarter of it and the right end four times it.
    private var speedOnDoublingScale: Binding<Double> {
        Binding(
            get: { log2(settings.scrollSpeed) },
            set: { settings.scrollSpeed = pow(2, $0) }
        )
    }
}

/// A menu of typefaces: Apple's system fonts, some classic families, and every installed family in a submenu.
private struct FontPicker: View {
    @Binding var selection: TextFont

    var body: some View {
        LabeledContent("Font") {
            Menu {
                Picker("Apple Fonts", selection: $selection) {
                    ForEach(SystemTypeface.allCases) { typeface in
                        Text(typeface.displayName).tag(TextFont.system(typeface))
                    }
                }

                Picker("Classic Fonts", selection: $selection) {
                    ForEach(FontLibrary.classicFamilies, id: \.self) { family in
                        Text(family).tag(TextFont.family(family))
                    }
                }

                Menu("All Fonts") {
                    Picker("All Fonts", selection: $selection) {
                        ForEach(FontLibrary.allFamilies, id: \.self) { family in
                            Text(family).tag(TextFont.family(family))
                        }
                    }
                }
            } label: {
                Text(selection.displayName)
            }
            .pickerStyle(.inline)
            .fixedSize()
        }
    }
}

/// Opens the settings: the Settings window on macOS, or a sheet on iPhone and iPad.
struct SettingsButton<Label: View>: View {
    /// Mac only: when set, the button calls this instead of opening the Settings window, so the
    /// settings can be shown inside the current window (used in full screen).
    var openInWindow: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    #if !os(macOS)
    @State private var isPresented = false
    #endif

    var body: some View {
        #if os(macOS)
        if let openInWindow {
            Button(action: openInWindow, label: label)
        } else {
            SettingsLink(label: label)
        }
        #else
        Button(action: { isPresented = true }, label: label)
            .keyboardShortcut(",", modifiers: .command) // ⌘, on an iPad keyboard, as on the Mac
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isPresented = false }
                            }
                        }
                }
            }
        #endif
    }
}

#if os(macOS)
/// The settings shown as a sheet on the main window, used while it's full screen. In full screen the
/// separate Settings window would open on another Space, away from the text.
struct SettingsSheet: View {
    var windowHeight: CGFloat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsView()
                .frame(height: max(300, min(620, windowHeight - 140)))
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }
}

extension Notification.Name {
    /// Asks the window passed as the object to show the settings inside itself.
    static let showSettingsInWindow = Notification.Name("showSettingsInWindow")
}

/// App menu ▸ Settings… (⌘,). Opens the Settings window, except when the front window is full
/// screen: then the settings open inside that window.
struct SettingsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.styleMask.contains(.fullScreen) {
                NotificationCenter.default.post(name: .showSettingsInWindow, object: window)
            } else {
                openSettings()
            }
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
#endif

#if os(iOS)
/// On iPhone a popover becomes a full-height sheet, which left the small pads floating in a large
/// empty panel. This sizes the sheet to the pad instead, so a swipe down anywhere outside the pad
/// (or on the grabber) goes back to the settings. Used on iPhone only; iPad keeps its popover.
private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 400

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12) // Room for the grabber
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .frame(maxWidth: .infinity)
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
    }
}
#endif

extension View {
    /// See `FittedSheet`. Only on iPhone: an iPad popover and the Mac are left as they are.
    @ViewBuilder
    func fittedSheetOnPhone() -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            modifier(FittedSheet())
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#Preview {
    SettingsView()
}
