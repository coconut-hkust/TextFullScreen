import SwiftUI

/// The user's own colors, shown as small squares under the color picker.
///
/// Click a square to use its color, or + to save the current one. To remove a color, right-click it
/// and choose Remove Colour, or drag it away from its spot: once it has moved more than 1.5 times its
/// own size, letting go removes it. A shorter drag snaps back, so a slip doesn't delete anything.
struct SavedColorsView: View {
    private var settings = DisplaySettings()

    /// The square being dragged and how far it has moved.
    @State private var dragging: Int?
    @State private var dragOffset: CGSize = .zero

    private let swatchSize: CGFloat = 26
    /// How far, in swatch sizes, a square must be dragged before letting go removes it.
    private let removeDistance: CGFloat = 1.5

    var body: some View {
        let colors = settings.savedColors

        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: swatchSize, maximum: swatchSize), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                swatch(color, at: index)
            }

            if colors.count < DisplaySettings.maxSavedColors {
                Button(action: saveCurrentColor) {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .overlay(Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary))
                        .frame(width: swatchSize, height: swatchSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Save the current color")
                .accessibilityLabel("Save the current color")
            }
        }
    }

    private func swatch(_ color: TextColor, at index: Int) -> some View {
        let isDragged = dragging == index
        let willRemove = isDragged && isFarEnoughToRemove(dragOffset)
        let isCurrent = color.rawValue == settings.color.rawValue

        return RoundedRectangle(cornerRadius: 5)
            .fill(color.color)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isCurrent ? Color.accentColor : .secondary.opacity(0.4), lineWidth: isCurrent ? 2 : 1)
            )
            .overlay {
                if willRemove {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.system(size: 14))
                        .offset(x: swatchSize / 2, y: -swatchSize / 2)
                }
            }
            .frame(width: swatchSize, height: swatchSize)
            .opacity(willRemove ? 0.4 : 1)
            .scaleEffect(isDragged ? 1.1 : 1)
            .offset(isDragged ? dragOffset : .zero)
            .zIndex(isDragged ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { settings.color = color }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        dragging = index
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        if isFarEnoughToRemove(value.translation) {
                            remove(at: index)
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragging = nil
                            dragOffset = .zero
                        }
                    }
            )
            .contextMenu {
                Button("Remove Colour", systemImage: "trash", role: .destructive) {
                    remove(at: index)
                }
            }
            .help("Use this color. Drag it away or right-click to remove it.")
            .accessibilityLabel("Saved color \(index + 1)")
            .accessibilityAction(named: "Remove Colour") { remove(at: index) }
    }

    /// True once the square has left its spot by more than `removeDistance` of its own size.
    private func isFarEnoughToRemove(_ translation: CGSize) -> Bool {
        max(abs(translation.width), abs(translation.height)) > swatchSize * removeDistance
    }

    private func saveCurrentColor() {
        var colors = settings.savedColors
        colors.removeAll { $0.rawValue == settings.color.rawValue } // No duplicates; move it to the end
        colors.append(settings.color)
        settings.savedColors = colors
    }

    private func remove(at index: Int) {
        var colors = settings.savedColors
        guard colors.indices.contains(index) else { return }
        colors.remove(at: index)
        withAnimation(.easeOut(duration: 0.2)) {
            settings.savedColors = colors
        }
    }
}

#Preview {
    Form {
        SavedColorsView()
    }
    .formStyle(.grouped)
}
