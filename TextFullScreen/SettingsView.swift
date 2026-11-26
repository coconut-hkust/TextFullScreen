import SwiftUI

/// The app's settings: the typeface, and whether text that doesn't fit shrinks or scrolls.
/// On macOS this fills the Settings window (⌘,). On iPhone and iPad, `SettingsButton` shows it in a sheet.
struct SettingsView: View {
    private var settings = DisplaySettings()
    @State private var isColorPadShown = false
    @State private var isGradientPadShown = false
    @State private var isConfirmingDefaults = false
    @State private var showsAllWallpapers = false
    @Environment(\.colorScheme) private var colorScheme

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
                            .fill(shownTextColor.color)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.5)))
                            .frame(width: 44, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Choose the text color")
                    .accessibilityLabel("Text color, \(shownTextColor.hex)")
                    .popover(isPresented: $isColorPadShown, arrowEdge: .trailing) {
                        ColorPadView()
                            .fittedSheetOnPhone()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Colors")
                    SavedColorsView()
                    if settings.showsDescriptions {
                        Text(savedColorsHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                previewText("The quick brown fox")
                    .font(settings.font.font(size: 34, weight: settings.weight))
                    .textFill(settings.gradient, plain: shownTextColor.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Font preview")
            }

            gradientSection

            Section {
                Toggle("Separate maximum size for moving", isOn: settings.$separateScrollSize)

                // Shared by both layouts unless moving has its own, shown in the Moving section
                if !settings.scrollEnabled || !settings.separateScrollSize {
                    percentControl("Maximum size", value: settings.$fillPercent, in: DisplaySettings.fillPercentRange)
                }
            } header: {
                Text("Layout")
            } footer: {
                descriptionText(layoutFooter)
            }

            scrollingSection

            wallpaperSection

            droppedTextSection

            savedSection

            aboutSection
        }
        .formStyle(.grouped)
        .appAppearance(settings.appScheme)
        #if os(macOS)
        // A set height, with the settings scrolling inside it. The window can be dragged taller or shorter.
        .frame(width: 460)
        .frame(minHeight: 360, idealHeight: 620, maxHeight: .infinity)
        #endif
    }

    /// Automatic, Light or Dark, for the whole app. Also set with the buttons on the gradient pad.
    private var appearancePicker: some View {
        Picker("Appearance", selection: settings.$appScheme) {
            ForEach(AppScheme.allCases) { scheme in
                Label(scheme.displayName, systemImage: scheme.symbol).tag(scheme)
            }
        }
        .pickerStyle(.segmented)
    }

    /// A section's explanation, shown only while Show descriptions is on.
    @ViewBuilder
    private func descriptionText(_ text: String) -> some View {
        if settings.showsDescriptions {
            Text(text)
        }
    }

    /// The text color as it shows on the plain page in the current appearance.
    private var shownTextColor: TextColor {
        settings.textColor(in: colorScheme, onPlainBackground: true)
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
            descriptionText(gradientFooter)
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

    /// The Moving switch, and below it while it's on: pan or rise, which way, how fast and how big.
    private var scrollingSection: some View {
        Section {
            Toggle("Moving", isOn: settings.$scrollEnabled)

            if settings.scrollEnabled {
                movingControls
            }
        } header: {
            Text("Moving")
        } footer: {
            descriptionText(movingFooter)
        }
    }

    /// The Wallpaper switch, and below it while it's on: Add Photo… and the photos added so far.
    private var wallpaperSection: some View {
        Section {
            Toggle("Wallpaper", isOn: settings.$wallpaperEnabled)

            if settings.wallpaperEnabled {
                WallpaperPicker(showsAll: $showsAllWallpapers)

                if settings.wallpaperID == WallpaperBackground.gradientID {
                    Picker("Direction", selection: settings.$wallpaperGradientDirection) {
                        ForEach(GradientDirection.allCases) { direction in
                            Text(direction.displayName)
                                .accessibilityLabel(direction.accessibilityName)
                                .tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        } header: {
            HStack {
                Text("Wallpaper")
                Spacer()
                let count = settings.wallpapers.count + settings.wallpaperFills.count
                if settings.wallpaperEnabled && count > 3 {
                    Button(showsAllWallpapers ? "Show Less" : "Show All (\(count))") {
                        withAnimation(.easeInOut(duration: 0.2)) { showsAllWallpapers.toggle() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
        } footer: {
            descriptionText(wallpaperFooter)
        }
    }

    /// What happens to text dragged onto the main window from another app.
    private var droppedTextSection: some View {
        Section {
            Toggle("Convert Markdown to plain text", isOn: settings.$dropConvertsMarkdown)
        } header: {
            Text("Dropped Text")
        } footer: {
            descriptionText(settings.dropConvertsMarkdown
                 ? "Drag selected text or a text file from another app onto the big text to show it. Markdown that's dropped or pasted (a .md file, or text with # headings, **bold**, [links] and the like) loses its formatting symbols and shows as plain words. Code and escaped symbols are kept."
                 : "Drag selected text or a text file from another app onto the big text to show it. Dropped or pasted Markdown is shown exactly as written, symbols and all.")
        }
    }

    private var wallpaperFooter: String {
        guard settings.wallpaperEnabled else { return "Shows a photo, a color or a gradient behind the text, in place of the plain background." }
        #if os(macOS)
        return "Click a tile to use it; Color and Gradient open their pads, and right-clicking either one saves it as a tile of its own or downloads it as a picture the size of your screen. Right-click a photo to crop and zoom it again, or any saved tile to remove it. To add a photo, click Add Photo… or drop a picture on it."
        #else
        return "Tap a tile to use it; Color and Gradient open their pads, and touching and holding either one saves it as a tile of its own or downloads it as a picture the size of your screen. Touch and hold a photo to crop and zoom it again, or any saved tile to remove it."
        #endif
    }

    private var movingFooter: String {
        guard settings.scrollEnabled else { return "Text stays large and moves across the screen." }
        if settings.gradientMoves {
            return "The text stays still and fills the screen, and the gradient flows through the letters in the direction and at the speed set here."
        }
        return settings.motion == .pan
            ? (settings.panKeepsRows
               ? "Each row pans on its own line, all at the same time. Start a new row with \(newRowKey). At 100% the rows together are as tall as the screen allows."
               : "Pan runs the text along one line, joining the rows. At 100% it's as tall as the screen allows.")
            : "Rise wraps the text to the screen width. At 100%, the longest word just fits across the screen."
    }

    @ViewBuilder
    private var movingControls: some View {
        // With a gradient on, the text can stay still while the gradient flows through it
        if settings.gradientEnabled {
            Picker("Moves", selection: settings.$scrollMover) {
                ForEach(ScrollMover.allCases) { mover in
                    Text(mover.displayName).tag(mover)
                }
            }
            .pickerStyle(.segmented)
        }

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

            if !settings.gradientMoves {
                Toggle("Keep rows", isOn: settings.$panKeepsRows)
            }
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

    /// How to save and remove colors, in the words of the device: click and right-click on the
    /// Mac, tap and touch and hold on iPhone and iPad (where a drag scrolls the row instead).
    private var savedColorsHint: String {
        #if os(macOS)
        "Click + to save the current color. To remove one, right-click it, or drag it away from its spot and let go. These are the same colors as in the color pad."
        #else
        "Tap + to save the current color. To remove one, touch and hold it, then tap Remove Colour. These are the same colors as in the color pad."
        #endif
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
            ? "Maximum size is how big the text may get."
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
                        Text("The font, color, gradient, size and moving settings go back to how the app first starts, and all saved colors are removed. Your saved slots and the wallpaper are kept.")
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
            descriptionText("Save keeps a copy of the current font, color, saved colors, gradient, size and moving settings. Load brings them back. The wallpaper is kept apart and doesn't change.")
        }
    }

    /// The appearance, the app's version, where its code lives, its licence, who made it and where to send ideas.
    private var aboutSection: some View {
        Section {
            appearancePicker

            Toggle("Show descriptions", isOn: settings.$showsDescriptions)

            LabeledContent("Version", value: appVersion)

            aboutLink("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: supportURL)
            aboutLink("Licence: PolyForm Noncommercial 1.0.0", systemImage: "doc.text", url: licenseURL)
            aboutLink("Developer: coconut-hkust", systemImage: "person.crop.circle", url: developerURL)
            aboutLink("Send Feedback or Ideas", systemImage: "lightbulb", url: feedbackURL)
        } header: {
            Text("About")
        } footer: {
            Text("Copyright 2026 coconut-hkust. Free for noncommercial use; commercial use needs permission from the author. Feedback opens a short Google Form; no account needed.")
        }
    }

    private func aboutLink(_ title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }

    /// For example "1.010 (10)", from the app's Info.plist.
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
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
