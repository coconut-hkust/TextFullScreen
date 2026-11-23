import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The app's own color pad, laid out like the macOS Colors panel: five ways to choose a color at the
/// top, and below them the current color, an eyedropper (Mac) and 40 squares for saved colors.
///
/// Saved squares, unlike the system panel's, can be removed: right-click one and choose Remove
/// Colour, or drag it away from the grid and let go once it's more than 1.5 times its own size from
/// its spot. Drag the big current-color square onto a square to save the color there, and drag one
/// saved square onto another to move it.
struct ColorPadView: View {
    private var settings = DisplaySettings()
    @AppStorage("colorPadTab") private var tab: ColorPadTab = .wheel

    /// Kept apart from the stored color so the hue survives at zero brightness or saturation.
    @State private var hue = 0.0
    @State private var saturation = 0.0
    @State private var brightness = 0.0

    // Dragging the current color onto a square
    @State private var wellDragLocation: CGPoint?
    @State private var slotFrames: [Int: CGRect] = [:]
    // Dragging a saved square
    @State private var draggedSlot: Int?
    @State private var slotDragOffset: CGSize = .zero
    @State private var slotDragLocation: CGPoint = .zero

    #if os(macOS)
    @State private var sampler: NSColorSampler?
    #endif

    private let slotSize: CGFloat = 22
    private let slotSpacing: CGFloat = 4
    private let columns = 10
    private let removeDistance: CGFloat = 1.5
    private let space = "colorPad"

    var body: some View {
        VStack(spacing: 14) {
            Picker("Mode", selection: $tab) {
                ForEach(ColorPadTab.allCases) { tab in
                    Image(systemName: tab.symbol)
                        .help(tab.title)
                        .accessibilityLabel(tab.title)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .wheel:
                    ColorWheelTab(hue: hue, saturation: saturation, brightness: brightness, onChange: setHSB)
                case .sliders:
                    ColorSlidersTab(color: settings.color, hsb: (hue, saturation, brightness), onColor: setColor, onHSB: setHSB)
                case .palette:
                    ColorPaletteTab(selected: settings.color, onColor: setColor)
                case .spectrum:
                    ColorSpectrumTab(hue: hue, saturation: saturation, brightness: brightness, onChange: setHSB)
                case .pencils:
                    ColorPencilsTab(selected: settings.color, onColor: setColor)
                }
            }
            .frame(height: 300)

            Divider()

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    currentColorWell
                    eyedropper
                }
                slotGrid
            }
        }
        .padding(16)
        .frame(width: 340)
        .coordinateSpace(.named(space))
        .overlay(alignment: .topLeading) {
            // The current color following the pointer while it's dragged onto a square
            if let location = wellDragLocation {
                RoundedRectangle(cornerRadius: 4)
                    .fill(settings.color.color)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5)))
                    .frame(width: slotSize + 6, height: slotSize + 6)
                    .position(location)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: syncFromStoredColor)
        .onChange(of: settings.color) { _, newColor in
            // Only re-read when the color changed somewhere else, so dragging stays smooth
            if TextColor(hue: hue, saturation: saturation, brightness: brightness).rawValue != newColor.rawValue {
                syncFromStoredColor()
            }
        }
    }

    // MARK: Current color and eyedropper

    private var currentColorWell: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(settings.color.color)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.5)))
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
                    .onChanged { wellDragLocation = $0.location }
                    .onEnded { value in
                        if let slot = slot(at: value.location) {
                            var slots = settings.colorSlots
                            slots[slot] = settings.color
                            settings.colorSlots = slots
                        }
                        wellDragLocation = nil
                    }
            )
            .help("Drag onto a square to save this color")
            .accessibilityLabel("Current color, \(settings.color.hex)")
            .accessibilityAction(named: "Save to first empty square", saveToFirstEmptySlot)
    }

    @ViewBuilder
    private var eyedropper: some View {
        #if os(macOS)
        Button {
            let sampler = NSColorSampler()
            self.sampler = sampler
            sampler.show { picked in
                if let rgb = picked?.usingColorSpace(.sRGB) {
                    setColor(TextColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
                }
                self.sampler = nil
            }
        } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: 18))
                .frame(width: 48, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Pick a color from anywhere on the screen")
        #endif
    }

    // MARK: Saved squares

    private var slotGrid: some View {
        let slots = settings.colorSlots
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(slotSize), spacing: slotSpacing), count: columns),
            spacing: slotSpacing
        ) {
            ForEach(0..<DisplaySettings.colorSlotCount, id: \.self) { index in
                slotView(slots[index], at: index)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { slotFrames[index] = $0 }
            }
        }
    }

    @ViewBuilder
    private func slotView(_ color: TextColor?, at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        if let color {
            let isDragged = draggedSlot == index
            let willRemove = isDragged && willRemoveDraggedSlot
            let isCurrent = color.rawValue == settings.color.rawValue

            shape
                .fill(color.color)
                .overlay(shape.strokeBorder(isCurrent ? Color.accentColor : .secondary.opacity(0.4), lineWidth: isCurrent ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if willRemove {
                        Image(systemName: "minus.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .font(.system(size: 13))
                            .offset(x: 6, y: -6)
                    }
                }
                .frame(width: slotSize, height: slotSize)
                .opacity(willRemove ? 0.4 : 1)
                .scaleEffect(isDragged ? 1.15 : 1)
                .offset(isDragged ? slotDragOffset : .zero)
                .zIndex(isDragged ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { setColor(color) }
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
                        .onChanged { value in
                            draggedSlot = index
                            slotDragOffset = value.translation
                            slotDragLocation = value.location
                        }
                        .onEnded { value in
                            endSlotDrag(from: index, at: value.location, translation: value.translation)
                        }
                )
                .contextMenu {
                    Button("Remove Colour", systemImage: "trash", role: .destructive) {
                        removeSlot(index)
                    }
                }
                .help("Use this color. Drag it away or right-click to remove it.")
                .accessibilityLabel("Saved color \(color.hex)")
                .accessibilityAction(named: "Remove Colour") { removeSlot(index) }
        } else {
            shape
                .strokeBorder(.secondary.opacity(0.35))
                .frame(width: slotSize, height: slotSize)
                .accessibilityLabel("Empty square")
        }
    }

    /// Dropped on another square: move it there (swapping with what's there). Dropped away from the
    /// squares and more than 1.5 times its size from its spot: remove it. Otherwise it snaps back.
    private func endSlotDrag(from index: Int, at location: CGPoint, translation: CGSize) {
        if let target = slot(at: location), target != index {
            var slots = settings.colorSlots
            slots.swapAt(index, target)
            settings.colorSlots = slots
        } else if slot(at: location) == nil, isFarEnoughToRemove(translation) {
            removeSlot(index)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            draggedSlot = nil
            slotDragOffset = .zero
        }
    }

    private var willRemoveDraggedSlot: Bool {
        slot(at: slotDragLocation) == nil && isFarEnoughToRemove(slotDragOffset)
    }

    private func isFarEnoughToRemove(_ translation: CGSize) -> Bool {
        max(abs(translation.width), abs(translation.height)) > slotSize * removeDistance
    }

    /// The square under a point in the pad, if any.
    private func slot(at point: CGPoint) -> Int? {
        slotFrames.first { $0.value.contains(point) }?.key
    }

    private func removeSlot(_ index: Int) {
        var slots = settings.colorSlots
        slots[index] = nil
        withAnimation(.easeOut(duration: 0.2)) {
            settings.colorSlots = slots
        }
    }

    private func saveToFirstEmptySlot() {
        var slots = settings.colorSlots
        guard let empty = slots.firstIndex(where: { $0 == nil }) else { return }
        slots[empty] = settings.color
        settings.colorSlots = slots
    }

    // MARK: Setting the color

    private func setHSB(_ hue: Double, _ saturation: Double, _ brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
        settings.color = TextColor(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func setColor(_ color: TextColor) {
        settings.color = color
        syncFromStoredColor()
    }

    private func syncFromStoredColor() {
        let hsb = settings.color.hsb
        // Keep the old hue for grays, where the color itself has none
        if hsb.saturation > 0 && hsb.brightness > 0 { hue = hsb.hue }
        if hsb.brightness > 0 { saturation = hsb.saturation }
        brightness = hsb.brightness
    }
}

nonisolated enum ColorPadTab: String, CaseIterable, Identifiable, Sendable {
    case wheel, sliders, palette, spectrum, pencils

    var id: Self { self }

    var title: String {
        switch self {
        case .wheel: "Color Wheel"
        case .sliders: "Color Sliders"
        case .palette: "Color Palettes"
        case .spectrum: "Spectrum"
        case .pencils: "Pencils"
        }
    }

    var symbol: String {
        switch self {
        case .wheel: "circle.circle"
        case .sliders: "slider.horizontal.3"
        case .palette: "list.bullet"
        case .spectrum: "photo"
        case .pencils: "pencil"
        }
    }
}

// MARK: - Wheel

/// Hue around the edge, saturation from the middle outwards, and a brightness slider below.
private struct ColorWheelTab: View {
    let hue: Double
    let saturation: Double
    let brightness: Double
    let onChange: (Double, Double, Double) -> Void

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geometry in
                let diameter = min(geometry.size.width, geometry.size.height)
                let radius = diameter / 2
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let angle = hue * 2 * .pi
                let marker = CGPoint(
                    x: center.x + cos(angle) * saturation * radius,
                    y: center.y - sin(angle) * saturation * radius
                )

                ZStack {
                    ZStack {
                        // Red on the right, then counterclockwise through yellow, green, cyan, blue and magenta
                        Circle().fill(AngularGradient(
                            colors: (0...36).map { Color(hue: 1 - Double($0) / 36, saturation: 1, brightness: 1) },
                            center: .center
                        ))
                        Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                        Circle().fill(Color.black.opacity(1 - brightness))
                    }
                    .frame(width: diameter, height: diameter)
                    .position(center)

                    Crosshair(color: brightness > 0.5 ? .black : .white)
                        .position(marker)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let dx = value.location.x - center.x
                    let dy = center.y - value.location.y
                    var picked = atan2(dy, dx)
                    if picked < 0 { picked += 2 * .pi }
                    // Picking on a black wheel would show nothing, so bring the brightness up
                    onChange(picked / (2 * .pi), min(hypot(dx, dy) / radius, 1), brightness == 0 ? 1 : brightness)
                })
            }

            GradientSlider(
                value: 1 - brightness,
                colors: [Color(hue: hue, saturation: saturation, brightness: 1), .black],
                onChange: { onChange(hue, saturation, 1 - $0) }
            )
            .accessibilityLabel("Brightness")
        }
    }
}

/// A slider drawn over a gradient, like the brightness bar in the macOS Colors panel.
private struct GradientSlider: View {
    /// 0...1 from left to right.
    let value: Double
    let colors: [Color]
    let onChange: (Double) -> Void

    private let height: CGFloat = 26

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - height, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .shadow(radius: 1)
                    .frame(width: height, height: height)
                    .offset(x: value * travel)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(max((drag.location.x - height / 2) / travel, 0), 1))
            })
        }
        .frame(height: height)
    }
}

private struct Crosshair: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: 1.5).frame(width: 14, height: 14)
            Rectangle().fill(color).frame(width: 1.5, height: 22)
            Rectangle().fill(color).frame(width: 22, height: 1.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Sliders

private struct ColorSlidersTab: View {
    let color: TextColor
    let hsb: (hue: Double, saturation: Double, brightness: Double)
    let onColor: (TextColor) -> Void
    let onHSB: (Double, Double, Double) -> Void

    @AppStorage("colorPadSliderMode") private var mode: SliderMode = .rgb
    @State private var hexText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Sliders", selection: $mode) {
                ForEach(SliderMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()

            switch mode {
            case .rgb:
                row("Red", value: color.red * 255, range: 255) { var c = color; c.red = $0 / 255; onColor(c) }
                row("Green", value: color.green * 255, range: 255) { var c = color; c.green = $0 / 255; onColor(c) }
                row("Blue", value: color.blue * 255, range: 255) { var c = color; c.blue = $0 / 255; onColor(c) }
            case .hsb:
                row("Hue", value: hsb.hue * 360, range: 360) { onHSB($0 / 360, hsb.saturation, hsb.brightness) }
                row("Saturation", value: hsb.saturation * 100, range: 100) { onHSB(hsb.hue, $0 / 100, hsb.brightness) }
                row("Brightness", value: hsb.brightness * 100, range: 100) { onHSB(hsb.hue, hsb.saturation, $0 / 100) }
            case .gray:
                row("Brightness", value: (color.red + color.green + color.blue) / 3 * 100, range: 100) {
                    onColor(TextColor(red: $0 / 100, green: $0 / 100, blue: $0 / 100))
                }
            }

            HStack {
                Text("Hex Color #")
                TextField("Hex", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit {
                        if let parsed = TextColor(hex: hexText) { onColor(parsed) } else { hexText = color.hex }
                    }
            }

            Spacer(minLength: 0)
        }
        .onAppear { hexText = color.hex }
        .onChange(of: color) { _, newColor in hexText = newColor.hex }
    }

    private func row(_ title: String, value: Double, range: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Slider(value: Binding(get: { value }, set: set), in: 0...range)
                TextField(title, value: Binding(get: { Int(value.rounded()) }, set: { set(min(max(Double($0), 0), range)) }), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .frame(width: 52)
            }
        }
    }

    enum SliderMode: String, CaseIterable, Identifiable {
        case rgb = "RGB Sliders", hsb = "HSB Sliders", gray = "Gray Scale Slider"
        var id: Self { self }
    }
}

// MARK: - Palette

private struct ColorPaletteTab: View {
    let selected: TextColor
    let onColor: (TextColor) -> Void

    @State private var search = ""

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)

            let matches = ColorLibrary.palette.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(matches, id: \.name) { entry in
                        let isSelected = entry.color.rawValue == selected.rawValue
                        Button { onColor(entry.color) } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(entry.color.color)
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.4)))
                                    .frame(width: 22, height: 22)
                                Text(entry.name)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isSelected ? Color.secondary.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Spectrum

/// Every hue from left to right, pale at the top and dark at the bottom.
private struct ColorSpectrumTab: View {
    let hue: Double
    let saturation: Double
    let brightness: Double
    let onChange: (Double, Double, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // Top half runs from white to full color, bottom half from full color to black
            let y = brightness >= 1
                ? saturation / 2
                : 0.5 + (1 - brightness) / 2
            ZStack(alignment: .topLeading) {
                Rectangle().fill(LinearGradient(
                    colors: (0...36).map { Color(hue: Double($0) / 36, saturation: 1, brightness: 1) },
                    startPoint: .leading, endPoint: .trailing
                ))
                Rectangle().fill(LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0), location: 0.5),
                        .init(color: .black.opacity(0), location: 0.5),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                Crosshair(color: y < 0.5 ? .black : .white)
                    .position(x: hue * size.width, y: y * size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let x = min(max(value.location.x / size.width, 0), 0.9999)
                let yN = min(max(value.location.y / size.height, 0), 1)
                if yN < 0.5 {
                    onChange(x, yN * 2, 1)
                } else {
                    onChange(x, 1, 1 - (yN - 0.5) * 2)
                }
            })
        }
    }
}

// MARK: - Pencils

private struct ColorPencilsTab: View {
    let selected: TextColor
    let onColor: (TextColor) -> Void

    var body: some View {
        let selectedName = ColorLibrary.pencils.first { $0.color.rawValue == selected.rawValue }?.name

        VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 10) {
                ForEach(ColorLibrary.pencils, id: \.name) { pencil in
                    let isSelected = pencil.name == selectedName
                    Button { onColor(pencil.color) } label: {
                        Pencil()
                            .fill(pencil.color.color)
                            .overlay(Pencil().stroke(.secondary.opacity(0.5), lineWidth: 0.75))
                            .frame(width: 14, height: 36)
                            .offset(y: isSelected ? -5 : 0)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(pencil.name)
                    .accessibilityLabel(pencil.name)
                }
            }
            Text(selectedName ?? " ")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

/// A colored pencil seen from the side: a sharpened tip on top of the body.
private struct Pencil: Shape {
    func path(in rect: CGRect) -> Path {
        let tip = rect.height * 0.3
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tip))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tip))
        path.closeSubpath()
        return path
    }
}

// MARK: - Named colors

nonisolated enum ColorLibrary {
    struct Entry: Sendable {
        let name: String
        let color: TextColor
    }

    private static func entries(_ list: [(String, String)]) -> [Entry] {
        list.compactMap { name, hex in TextColor(hex: hex).map { Entry(name: name, color: $0) } }
    }

    static let palette = entries([
        ("Black", "000000"), ("Blue", "0000FF"), ("Brown", "996633"), ("Cyan", "00FFFF"),
        ("Gray", "808080"), ("Green", "00FF00"), ("Magenta", "FF00FF"), ("Orange", "FF8000"),
        ("Purple", "800080"), ("Red", "FF0000"), ("Yellow", "FFFF00"), ("White", "FFFFFF"),
    ])

    static let pencils = entries([
        ("Cayenne", "800000"), ("Asparagus", "808000"), ("Clover", "008000"), ("Teal", "008080"),
        ("Midnight", "000080"), ("Plum", "800080"), ("Tin", "7F7F7F"), ("Nickel", "808080"),
        ("Mocha", "804000"), ("Fern", "408000"), ("Moss", "008040"), ("Ocean", "004080"),
        ("Eggplant", "400080"), ("Maroon", "800040"), ("Steel", "666666"), ("Aluminum", "999999"),
        ("Maraschino", "FF0000"), ("Lemon", "FFFF00"), ("Spring", "00FF00"), ("Turquoise", "00FFFF"),
        ("Blueberry", "0000FF"), ("Magenta", "FF00FF"), ("Iron", "4C4C4C"), ("Magnesium", "B3B3B3"),
        ("Tangerine", "FF8000"), ("Lime", "80FF00"), ("Sea Foam", "00FF80"), ("Aqua", "0080FF"),
        ("Grape", "8000FF"), ("Strawberry", "FF0080"), ("Tungsten", "333333"), ("Silver", "CCCCCC"),
        ("Salmon", "FF6666"), ("Banana", "FFFF66"), ("Flora", "66FF66"), ("Ice", "66FFFF"),
        ("Orchid", "6666FF"), ("Bubblegum", "FF66FF"), ("Lead", "191919"), ("Mercury", "E6E6E6"),
        ("Cantaloupe", "FFCC66"), ("Honeydew", "CCFF66"), ("Spindrift", "66FFCC"), ("Sky", "66CCFF"),
        ("Lavender", "CC66FF"), ("Carnation", "FF6FCF"), ("Licorice", "000000"), ("Snow", "FFFFFF"),
    ])
}

#Preview {
    ColorPadView()
}
