import SwiftUI

/// The app's settings: the typeface, and whether text that doesn't fit shrinks or scrolls.
/// On macOS this fills the Settings window (⌘,). On iPhone and iPad, `SettingsButton` shows it in a sheet.
struct SettingsView: View {
    private var settings = DisplaySettings()
    @State private var isColorPadShown = false
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
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Colors")
                    SavedColorsView()
                    Text("Click + to save the current color. To remove one, right-click it, or drag it away from its spot and let go. These are the same colors as in the color pad.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("The quick brown fox")
                    .font(settings.font.font(size: 34, weight: settings.weight))
                    .foregroundStyle(settings.color.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Font preview")
            }

            Section {
                Toggle("Scroll text off screen", isOn: settings.$scrollEnabled)

                if !settings.scrollEnabled {
                    titled("Maximum size") {
                        HStack(spacing: 12) {
                            Slider(value: fillPercentForSlider, in: Double(DisplaySettings.fillPercentRange.lowerBound)...Double(DisplaySettings.fillPercentRange.upperBound), step: 1) {
                                Text("Maximum size")
                            }

                            HStack(spacing: 2) {
                                TextField("Percent", value: fillPercentClamped, format: .number)
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
            } header: {
                Text("Layout")
            } footer: {
                Text(settings.scrollEnabled
                     ? "Text stays large and moves across the screen."
                     : "Text shrinks until all of it fits on the screen. Maximum size is how much of the screen's width and height it may fill.")
            }

            if settings.scrollEnabled {
                scrollingSection
            }

            savedSection
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true) // Window grows and shrinks with the scrolling section
        #endif
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

            titled("Size") {
                Slider(value: settings.$scrollTextSize, in: DisplaySettings.scrollTextSizeRange) {
                    Text("Size")
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller")
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger")
                }
            }
        } header: {
            Text("Scrolling")
        } footer: {
            Text(settings.motion == .pan
                 ? "Pan runs the text along one line. At full size it's as tall as the screen allows."
                 : "Rise wraps the text to the screen width. At full size, the longest word just fits across the screen.")
        }
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
                    Text("SF Pro · Black · 80% · no saved colors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Load") { isConfirmingDefaults = true }
                    .confirmationDialog("Load the default settings?", isPresented: $isConfirmingDefaults) {
                        Button("Load Defaults", role: .destructive) { settings.loadDefaults() }
                    } message: {
                        Text("The font, color, size and scrolling settings go back to how the app first starts, and all saved colors are removed. Your saved slots are kept.")
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
            Text("Save keeps a copy of the current font, color, saved colors, size and scrolling settings. Load brings them back.")
        }
    }

    private var fillPercentForSlider: Binding<Double> {
        Binding(
            get: { Double(settings.fillPercent) },
            set: { settings.fillPercent = Int($0.rounded()) }
        )
    }

    /// The typed percentage, kept within 80–100%.
    private var fillPercentClamped: Binding<Int> {
        Binding(
            get: { settings.fillPercent },
            set: { settings.fillPercent = min(max($0, DisplaySettings.fillPercentRange.lowerBound), DisplaySettings.fillPercentRange.upperBound) }
        )
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
    @ViewBuilder var label: () -> Label

    #if !os(macOS)
    @State private var isPresented = false
    #endif

    var body: some View {
        #if os(macOS)
        SettingsLink(label: label)
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

#Preview {
    SettingsView()
}
