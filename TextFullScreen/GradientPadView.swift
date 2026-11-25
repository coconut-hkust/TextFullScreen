import SwiftUI

/// Chooses the gradient: a pad of color dots, swatches, an opacity wave and a texture dial.
///
/// On the pad, the angle around the middle is the hue and the distance from the middle is the
/// lightness (black in the middle, the pure color halfway out, white at the edge). Click anywhere to
/// place the big main dot, or drag it. The small dots follow it by a color harmony; click one to make
/// it the main dot, or right-click a dot to remove it. + and − add and remove dots (up to three) and
/// the third button steps through the harmonies.
struct GradientPadView: View {
    private var settings = DisplaySettings()
    @Environment(\.colorScheme) private var colorScheme

    /// The pad as being edited; saved to the settings on every change.
    @State private var pad = ColorPadState(colors: [])
    @State private var isDragging = false
    @State private var swatchPage = 0
    @State private var customColor = Color.blue
    @State private var isCustomColorsShown = false

    private let padSize: CGFloat = 300
    private let mainDotSize: CGFloat = 38
    private let otherDotSize: CGFloat = 22
    private let space = "gradientPad"
    private let spring = Animation.spring(response: 0.4, dampingFraction: 0.65)

    var body: some View {
        VStack(spacing: 12) {
            padView
            swatchRow
            HStack(spacing: 14) {
                WaveSlider(value: settings.$gradientOpacity)
                TextureDial(texture: settings.$gradientTexture, amount: settings.$gradientTextureAmount)
            }
            .padding(.horizontal, 4)
            customColors
        }
        .padding(16)
        .frame(width: padSize + 32)
        .onAppear { pad = settings.gradientPad }
        .onChange(of: settings.gradientColors) { _, colors in
            // Only re-read when the colors were changed somewhere else (e.g. a slot was loaded)
            if colors.map(\.rawValue) != pad.colors.map(\.rawValue) { pad = settings.gradientPad }
        }
    }

    // MARK: Pad

    private var isDark: Bool { colorScheme == .dark }

    private var padView: some View {
        ZStack {
            dotGrid

            if pad.count == 0 {
                Text("Click to add a color")
                    .font(.callout.weight(.semibold))
                    .allowsHitTesting(false)
            }

            ForEach(Array(pad.hues.enumerated()).reversed(), id: \.offset) { index, hue in
                dot(index: index, hue: hue)
            }

            VStack {
                schemeButtons
                Spacer()
                padButtons
            }
            .padding(.vertical, 10)
        }
        .frame(width: padSize, height: padSize)
        .coordinateSpace(.named(space))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.secondary.opacity(0.2)))
    }

    /// The light pad with its fine dot grid. Clicking or dragging anywhere places the main dot.
    private var dotGrid: some View {
        Canvas { context, size in
            let spacing: CGFloat = 6
            let shade = isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.12)
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)), with: .color(shade))
                }
            }
        }
        .background(isDark ? Color(white: 0.16) : Color(white: 0.94))
        .contentShape(Rectangle())
        .gesture(mainDotGesture)
    }

    /// Places the main dot where the pointer goes down (springing there), then follows the drag.
    private var mainDotGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if isDragging {
                    placeMainDot(at: value.location)
                } else {
                    isDragging = true
                    withAnimation(spring) { placeMainDot(at: value.location) }
                }
            }
            .onEnded { _ in isDragging = false }
    }

    private func dot(index: Int, hue: Double) -> some View {
        let isMain = index == 0
        let size = isMain ? mainDotSize : otherDotSize
        let color = pad.dotColors.indices.contains(index) ? pad.dotColors[index] : pad.color(hue: hue)
        return Circle()
            .fill(color.color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white, lineWidth: isMain ? 6 : 3))
            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
            .scaleEffect(isMain && isDragging ? 1.15 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .position(position(hue: hue))
            .gesture(isMain ? AnyGesture(mainDotGesture.map { _ in () }) : AnyGesture(TapGesture().onEnded { makeMain(index) }))
            .contextMenu {
                Button("Remove Color", role: .destructive) { edit { $0.removeDot(index) } }
            }
            .help(isMain ? "Drag to change the color" : "Click to make this the main color")
            .accessibilityElement()
            .accessibilityLabel(isMain ? "Main color, \(color.hex)" : "Color \(index + 1), \(color.hex)")
            .accessibilityAction(named: "Remove") { edit { $0.removeDot(index) } }
    }

    private var schemeButtons: some View {
        HStack(spacing: 26) {
            ForEach(AppScheme.allCases) { scheme in
                Button { settings.appScheme = scheme } label: {
                    Image(systemName: scheme.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settings.appScheme == scheme ? Color.primary.opacity(0.1) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.75))
                .help("\(scheme.displayName) appearance")
                .accessibilityLabel("\(scheme.displayName) appearance")
                .accessibilityAddTraits(settings.appScheme == scheme ? .isSelected : [])
            }
        }
    }

    private var padButtons: some View {
        HStack(spacing: 40) {
            padButton("plus", help: "Add a color") { edit { $0.addDot() } }
                .disabled(pad.count >= ColorPadState.maxDots)
            padButton("minus", help: "Remove a color") { edit { $0.removeDot() } }
                .disabled(pad.count == 0)
            padButton("point.3.connected.trianglepath.dotted", help: "Next harmony (now \(pad.harmony.displayName))") { edit { $0.nextHarmony() } }
                .disabled(ColorHarmony.options(for: pad.count).count < 2)
        }
    }

    private func padButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.6))
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Swatches

    private enum Swatch {
        case preset(Preset)
        case saved(TextColor)
    }

    /// The preset pages, then the saved colors, nine to a page.
    private var pages: [[Swatch]] {
        let saved = settings.colorSlots.compactMap { $0 }
        return Preset.pages.map { $0.map(Swatch.preset) }
            + stride(from: 0, to: saved.count, by: 9).map { saved[$0..<min($0 + 9, saved.count)].map(Swatch.saved) }
    }

    private var swatchRow: some View {
        let pages = pages
        let page = min(swatchPage, pages.count - 1)
        return HStack(spacing: 4) {
            Button { withAnimation { swatchPage = max(page - 1, 0) } } label: {
                Image(systemName: "chevron.left").frame(width: 14, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(page == 0)
            .accessibilityLabel("Previous swatches")

            HStack(spacing: 0) {
                ForEach(Array(pages[page].enumerated()), id: \.offset) { _, swatch in
                    swatchButton(swatch).frame(maxWidth: .infinity)
                }
            }
            .id(page)
            .transition(.opacity)

            Button { withAnimation { swatchPage = min(page + 1, pages.count - 1) } } label: {
                Image(systemName: "chevron.right").frame(width: 14, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(page >= pages.count - 1)
            .accessibilityLabel("More swatches")
        }
        .foregroundStyle(.secondary)
    }

    private func swatchButton(_ swatch: Swatch) -> some View {
        let colors: [TextColor]
        switch swatch {
        case .preset(let preset): colors = preset.state.dotColors
        case .saved(let color): colors = [color]
        }
        let preview = TextGradient(colors: colors, style: .whole, anchor: .text, direction: .blend, repeats: false, shadesBetween: 0)
        return Button {
            switch swatch {
            case .preset(let preset): edit { $0.apply(preset) }
            case .saved(let color):
                let hsl = color.hsl
                edit { pad in
                    pad.kind = .standard
                    pad.moveMain(hue: hsl.hue * 360, distance: hsl.lightness)
                }
            }
        } label: {
            GradientFillView(gradient: preview)
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(SwatchButtonStyle())
        .help(colors.map(\.hex).joined(separator: ", "))
        .accessibilityLabel("Use \(colors.map(\.hex).joined(separator: ", "))")
    }

    // MARK: Custom colors

    /// Any exact color, added after the dots' colors. While there are custom colors, a Blend gradient
    /// runs all the colors in a plain slanted line instead.
    private var customColors: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The whole header opens and closes the section, not just its arrow
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isCustomColorsShown.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isCustomColorsShown ? 90 : 0))
                    Text("Custom Colors")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isCustomColorsShown ? .isSelected : [])

            if isCustomColorsShown {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ColorPicker("Custom color", selection: $customColor, supportsOpacity: true)
                        .labelsHidden()
                    Text(TextColor(customColor).hex)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add") { edit { $0.customColors.append(TextColor(customColor).rawValue) } }
                        .controlSize(.small)
                }
                ForEach(Array(pad.custom.enumerated()), id: \.offset) { index, color in
                    HStack {
                        Circle().fill(color.color).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
                        Text(color.hex + (color.opacity < 1 ? " · \(Int((color.opacity * 100).rounded()))%" : ""))
                            .font(.callout.monospaced())
                        Spacer()
                        Button {
                            edit { $0.customColors.remove(at: index) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(color.hex)")
                    }
                }
            }
            .padding(.top, 6)
            }
        }
        .font(.callout)
    }

    // MARK: Positions and editing

    private var center: CGPoint { CGPoint(x: padSize / 2, y: padSize / 2) }
    /// Dots stay inside this circle, a little in from the pad's edge so the main dot stays whole.
    private var radius: CGFloat { padSize / 2 - mainDotSize / 2 - 2 }

    private func position(hue: Double) -> CGPoint {
        let angle = hue * .pi / 180
        let d = pad.distance * radius
        return CGPoint(x: center.x + cos(angle) * d, y: center.y + sin(angle) * d)
    }

    private func placeMainDot(at location: CGPoint) {
        let dx = location.x - center.x, dy = location.y - center.y
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        // Right at the middle the angle means nothing, so the old one is kept
        pad.moveMain(hue: hypot(dx, dy) > 1 ? degrees : nil, distance: hypot(dx, dy) / radius)
        settings.gradientPad = pad
    }

    private func makeMain(_ index: Int) {
        edit { $0.makeMain(index) }
    }

    private func edit(_ change: (inout ColorPadState) -> Void) {
        withAnimation(spring) { change(&pad) }
        settings.gradientPad = pad
    }
}

private struct SwatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Wave slider

/// The opacity slider: a line that becomes a wave as the gradient grows stronger.
private struct WaveSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let inset: CGFloat = 8
            let track = width - inset * 2
            let v = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    var path = Path()
                    let amplitude = (size.height / 2 - 6) * v
                    let waves = 7.0
                    for step in 0...200 {
                        let t = Double(step) / 200
                        let x = inset + track * t
                        let y = size.height / 2 - amplitude * sin(t * waves * 2 * .pi)
                        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                    let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    let split = inset + track * v
                    context.drawLayer { layer in
                        layer.clip(to: Path(CGRect(x: 0, y: 0, width: split, height: size.height)))
                        layer.stroke(path, with: .color(.primary.opacity(0.6)), style: style)
                    }
                    context.drawLayer { layer in
                        layer.clip(to: Path(CGRect(x: split, y: 0, width: size.width - split, height: size.height)))
                        layer.stroke(path, with: .color(.primary.opacity(0.22)), style: style)
                    }
                }
                Capsule()
                    .fill(.primary)
                    .frame(width: 8 + 4 * v, height: 30 + 12 * v)
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .position(x: inset + track * v, y: height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value = min(max(($0.location.x - inset) / track, 0), 1) }
            )
        }
        .frame(height: 50)
        .help("How strongly the gradient shows")
        .accessibilityElement()
        .accessibilityLabel("Gradient strength")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            value = min(max(value + (direction == .increment ? 0.1 : -0.1), 0), 1)
        }
    }
}

// MARK: - Texture dial

/// Click the dial to change the texture; turn it (drag around) to set how strong it is, in 16 steps.
private struct TextureDial: View {
    @Binding var texture: GradientTexture
    @Binding var amount: Double

    private let size: CGFloat = 64
    private let steps = 16

    var body: some View {
        ZStack {
            ForEach(0..<steps, id: \.self) { step in
                let angle = Double(step) / Double(steps) * 2 * .pi - .pi / 2
                let isActive = amount > 0 && Double(step) / Double(steps) <= amount
                Circle()
                    .fill(.primary.opacity(isActive ? 0.55 : 0.18))
                    .frame(width: 4, height: 4)
                    .position(x: size / 2 + cos(angle) * size / 2.2, y: size / 2 + sin(angle) * size / 2.2)
            }

            face

            // The handle, on the ring at the current amount
            let angle = amount * 2 * .pi - .pi / 2
            Capsule()
                .fill(.primary.opacity(0.7))
                .frame(width: 5, height: 11)
                .rotationEffect(.radians(angle + .pi / 2))
                .position(x: size / 2 + cos(angle) * size / 2.2, y: size / 2 + sin(angle) * size / 2.2)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { turn(to: $0.location) }
                .exclusively(before: TapGesture().onEnded { texture = texture.next() })
        )
        .help("Texture: \(texture.displayName). Click to change it, drag around the dial to set its strength.")
        .accessibilityElement()
        .accessibilityLabel("Texture, \(texture.displayName)")
        .accessibilityValue("\(Int((amount * Double(steps)).rounded())) of \(steps)")
        .accessibilityAction { texture = texture.next() }
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / Double(steps)
            amount = min(max(amount + (direction == .increment ? step : -step), 0), 1 - step)
            if amount > 0, texture == .none { texture = .grain }
        }
    }

    /// The middle of the dial: the texture itself, slightly raised.
    private var face: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.35))
            if let image = texture.image {
                // Shown stronger than on the text, so the small face still shows which texture it is
                Image(decorative: image, scale: 2)
                    .resizable(resizingMode: .tile)
                    .interpolation(texture.isPixelated ? .none : .medium)
                    .opacity(min(1, texture.alpha * max(0.5, amount) * 2.5))
            }
            Circle().fill(LinearGradient(colors: [.primary.opacity(0.1), .clear], startPoint: .bottomTrailing, endPoint: .topLeading))
        }
        .frame(width: size * 0.6, height: size * 0.6)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5))
        .overlay {
            if texture == .none {
                Image(systemName: "circle.slash").font(.system(size: 13)).foregroundStyle(.tertiary)
            }
        }
    }

    private func turn(to location: CGPoint) {
        var turns = atan2(location.y - size / 2, location.x - size / 2) / (2 * .pi) + 0.25
        if turns < 0 { turns += 1 }
        var stepped = (turns * Double(steps)).rounded() / Double(steps)
        if stepped >= 1 { stepped = 0 }
        if stepped != amount { amount = stepped }
        if amount > 0, texture == .none { texture = .grain }
    }
}

#Preview {
    GradientPadView()
}
