import SwiftUI

/// The saved colors as one row in Settings. It shows the same squares as the color pad, so a color
/// saved, moved or removed in either place shows up in both.
///
/// Click a color to use it, or + to save the current one. To remove a color, right-click it and
/// choose Remove Colour, or (on the Mac) drag it away and let go once it has moved more than 1.5
/// times its own size; a shorter drag snaps back. When there are more colors than fit across
/// Settings, the row scrolls sideways.
struct SavedColorsView: View {
    private var settings = DisplaySettings()

    /// The slot being dragged and how far it has moved.
    @State private var dragging: Int?
    @State private var dragOffset: CGSize = .zero

    private let swatchSize: CGFloat = 26
    private let removeDistance: CGFloat = 1.5

    var body: some View {
        let slots = settings.colorSlots
        let saved = slots.indices.compactMap { index in slots[index].map { (slot: index, color: $0) } }
        let isFull = !slots.contains { $0 == nil }

        HStack(spacing: 8) {
            // Stays put while the colors scroll
            Button(action: saveCurrentColor) {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .overlay(Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary))
                    .frame(width: swatchSize, height: swatchSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isFull)
            .help(isFull ? "All 40 squares are full" : "Save the current color")
            .accessibilityLabel("Save the current color")

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(saved, id: \.slot) { entry in
                        swatch(entry.color, slot: entry.slot)
                    }
                }
                .padding(.vertical, 6) // Room for the selection ring and the remove badge
                .padding(.trailing, 6)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func swatch(_ color: TextColor, slot: Int) -> some View {
        let isDragged = dragging == slot
        let willRemove = isDragged && isFarEnoughToRemove(dragOffset)
        let isCurrent = color.rawValue == settings.color.rawValue

        return RoundedRectangle(cornerRadius: 5)
            .fill(color.color)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isCurrent ? Color.accentColor : .secondary.opacity(0.4), lineWidth: isCurrent ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if willRemove {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.system(size: 14))
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: swatchSize, height: swatchSize)
            .opacity(willRemove ? 0.4 : 1)
            .scaleEffect(isDragged ? 1.1 : 1)
            .offset(isDragged ? dragOffset : .zero)
            .zIndex(isDragged ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { settings.color = color }
            #if os(macOS)
            // On iPhone and iPad a sideways drag scrolls the row, so there removal is by the menu only
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        dragging = slot
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        if isFarEnoughToRemove(value.translation) {
                            remove(slot)
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragging = nil
                            dragOffset = .zero
                        }
                    }
            )
            #endif
            .contextMenu {
                Button("Remove Colour", systemImage: "trash", role: .destructive) {
                    remove(slot)
                }
            }
            .help("Use this color. Drag it away or right-click to remove it.")
            .accessibilityLabel("Saved color \(color.hex)")
            .accessibilityAction(named: "Remove Colour") { remove(slot) }
    }

    /// True once the color has left its spot by more than `removeDistance` of its own size.
    private func isFarEnoughToRemove(_ translation: CGSize) -> Bool {
        max(abs(translation.width), abs(translation.height)) > swatchSize * removeDistance
    }

    /// Puts the current color in the first empty square, unless it's already saved.
    private func saveCurrentColor() {
        var slots = settings.colorSlots
        guard !slots.contains(where: { $0?.rawValue == settings.color.rawValue }),
              let empty = slots.firstIndex(where: { $0 == nil }) else { return }
        slots[empty] = settings.color
        settings.colorSlots = slots
    }

    private func remove(_ slot: Int) {
        var slots = settings.colorSlots
        slots[slot] = nil
        withAnimation(.easeOut(duration: 0.2)) {
            settings.colorSlots = slots
        }
    }
}

#Preview {
    Form {
        SavedColorsView()
    }
    .formStyle(.grouped)
    .frame(width: 460)
}
