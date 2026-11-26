import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable
#if os(macOS)
import AppKit
#else
import PhotosUI
import UIKit
#endif

// MARK: - Model

/// Which part of a photo the wallpaper shows: the point of the photo at the middle of the screen
/// (0...1 across and down) and how far it's zoomed in. At zoom 1 the photo just covers the screen.
/// Keeping a centre and zoom, not a rectangle, lets the same crop fit a window of any shape.
nonisolated struct WallpaperCrop: Codable, Hashable, Sendable {
    var centerX = 0.5
    var centerY = 0.5
    var zoom = 1.0

    static let zoomRange = 1.0...8.0
}

/// A photo added as a wallpaper. Its picture is kept in a file named after its id.
nonisolated struct Wallpaper: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var crop: WallpaperCrop
}

/// What the wallpaper shows: a photo, a plain color or a gradient.
enum WallpaperBackground {
    case photo(Wallpaper)
    case color(TextColor)
    case gradient(TextGradient)

    var isPhoto: Bool {
        if case .photo = self { return true }
        return false
    }

    /// Stand-ins for a photo's id in `DisplaySettings.wallpaperID`, for the color and gradient tiles.
    static let colorID = "color"
    static let gradientID = "gradient"
}

/// A color or gradient saved as a wallpaper tile of its own. Exactly one of `color` and
/// `gradientPad` is set. Values are kept in their stored (raw) forms.
nonisolated struct WallpaperFill: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var color: String?
    var gradientPad: String?
    var opacity: Double?
    var texture: String?
    var textureAmount: Double?
    var direction: String?

    /// How it's drawn, or nil if it can't be read back.
    var background: WallpaperBackground? {
        if let color, let value = TextColor(rawValue: color) { return .color(value) }
        guard let gradientPad, let pad = ColorPadState.decode(gradientPad), !pad.colors.isEmpty else { return nil }
        return .gradient(TextGradient(
            colors: pad.colors, style: .whole, anchor: .screen,
            direction: direction.flatMap(GradientDirection.init(rawValue:)) ?? .blend,
            repeats: false, shadesBetween: 0, opacity: opacity ?? GradientOpacity.standard,
            texture: texture.flatMap(GradientTexture.init(rawValue:)) ?? .none,
            textureAmount: textureAmount ?? 0, usesCustomColors: !pad.customColors.isEmpty
        ))
    }

    /// True when both would look the same (their ids aside). Gradients are compared by their
    /// decoded dots, as the same dots can be written out as JSON with its keys in another order.
    func sameLook(as other: WallpaperFill) -> Bool {
        guard color == other.color, opacity == other.opacity, texture == other.texture,
              textureAmount == other.textureAmount, direction == other.direction else { return false }
        if gradientPad == other.gradientPad { return true }
        guard let mine = gradientPad.flatMap(ColorPadState.decode),
              let theirs = other.gradientPad.flatMap(ColorPadState.decode) else { return false }
        return mine == theirs
    }
}

/// Draws a wallpaper filling its space. `placeholder` shows while a photo is still loading.
struct WallpaperBackgroundView<Placeholder: View>: View {
    var background: WallpaperBackground
    var thumbnail = false
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        switch background {
        case .photo(let wallpaper):
            WallpaperImage(wallpaper: wallpaper, thumbnail: thumbnail, placeholder: placeholder)
        case .color(let color):
            color.color
        case .gradient(let gradient):
            // The wave slider fades the gradient into the plain background behind it
            ZStack {
                placeholder()
                GradientFillView(gradient: gradient).opacity(gradient.alpha)
            }
        }
    }
}

// MARK: - Downloading

/// A color or gradient wallpaper drawn as a picture the size of the screen, ready to save.
struct ExportedWallpaper: Identifiable {
    let id = UUID()
    var image: CGImage
    var name: String

    var pngData: Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Draws the wallpaper at the full screen's size and pixel density. `dark` picks the plain
    /// background a see-through gradient shows over, as in full screen.
    @MainActor
    init?(_ background: WallpaperBackground, dark: Bool) {
        let name: String
        switch background {
        case .photo: return nil // Photos are the user's own pictures already
        case .color(let color): name = "Wallpaper \(color.hex.dropFirst())"
        case .gradient: name = "Wallpaper Gradient"
        }
        let (size, scale) = Self.screen
        let content = WallpaperBackgroundView(background: background) {
            dark ? Color(white: 0.075) : Color.white
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        self.image = image
        self.name = name
    }

    /// The screen's size in points and its pixels per point.
    @MainActor
    private static var screen: (CGSize, CGFloat) {
        #if os(macOS)
        if let screen = NSApp.keyWindow?.screen ?? NSScreen.main {
            return (screen.frame.size, screen.backingScaleFactor)
        }
        #elseif os(iOS)
        if let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first {
            return (screen.bounds.size, screen.scale)
        }
        #endif
        return (CGSize(width: 1920, height: 1080), 2)
    }
}

#if os(macOS)
/// A PNG for the Mac's save panel.
private struct PNGDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#else
/// The share sheet, which offers Save Image (to Photos) and Save to Files. Presented straight from
/// UIKit on top of whatever is showing (a SwiftUI sheet wrapping it closed again at once).
@MainActor
private func presentShareSheet(_ image: CGImage, onDone: @escaping () -> Void) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else {
        onDone()
        return
    }
    while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
    let controller = UIActivityViewController(activityItems: [UIImage(cgImage: image)], applicationActivities: nil)
    controller.completionWithItemsHandler = { _, _, _, _ in onDone() }
    // On iPad it's a popover, pointing at the middle of the screen
    if let popover = controller.popoverPresentationController {
        popover.sourceView = top.view
        popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
    }
    top.present(controller, animated: true)
}
#endif

/// Saves a wallpaper picture: a save panel on the Mac, the share sheet on iPhone and iPad.
private struct WallpaperExporter: ViewModifier {
    @Binding var item: ExportedWallpaper?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.fileExporter(
            isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
            document: item?.pngData.map(PNGDocument.init(data:)),
            contentType: .png,
            defaultFilename: item?.name ?? "Wallpaper"
        ) { _ in item = nil }
        #else
        content.onChange(of: item?.id) { _, id in
            guard id != nil, let image = item?.image else { return }
            presentShareSheet(image) { item = nil }
        }
        #endif
    }
}

extension View {
    /// Shows the save panel (Mac) or share sheet (iPhone, iPad) while `item` is set.
    func wallpaperExporter(_ item: Binding<ExportedWallpaper?>) -> some View {
        modifier(WallpaperExporter(item: item))
    }
}

// MARK: - Files

/// The wallpaper pictures on disk, in Application Support, plus a small cache of decoded images.
nonisolated enum WallpaperFiles {
    /// Photos are shrunk to this many pixels on their long side: enough for a 5K display.
    static let maxPixel = 5120
    static let thumbnailPixel = 720

    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 300_000_000 // bytes of decoded pixels
        return cache
    }()

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appending(path: "Wallpapers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func url(for id: UUID, thumbnail: Bool) -> URL {
        folder.appending(path: id.uuidString + (thumbnail ? "-thumb" : "") + ".heic")
    }

    /// Decodes a picture the right way up, shrunk to at most `maxPixel` on its long side.
    static func makeImage(from data: Data, maxPixel: Int = maxPixel) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return makeImage(from: source, maxPixel: maxPixel)
    }

    private static func makeImage(from source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Writes the picture and its thumbnail. Returns false if it couldn't be written.
    static func save(_ image: CGImage, id: UUID) -> Bool {
        guard write(image, to: url(for: id, thumbnail: false)) else { return false }
        if let data = encoded(image), let thumbnail = makeImage(from: data, maxPixel: thumbnailPixel) {
            _ = write(thumbnail, to: url(for: id, thumbnail: true))
            remember(thumbnail, id: id, thumbnail: true)
        }
        remember(image, id: id, thumbnail: false)
        return true
    }

    static func remove(id: UUID) {
        for thumbnail in [false, true] {
            try? FileManager.default.removeItem(at: url(for: id, thumbnail: thumbnail))
            cache.removeObject(forKey: key(id, thumbnail))
        }
    }

    /// The picture if it's already decoded, without touching the disk.
    static func cachedImage(id: UUID, thumbnail: Bool) -> CGImage? {
        cache.object(forKey: key(id, thumbnail))
    }

    /// The picture, read from disk if needed. A missing thumbnail is made from the full picture.
    static func loadImage(id: UUID, thumbnail: Bool) -> CGImage? {
        if let image = cachedImage(id: id, thumbnail: thumbnail) { return image }
        let maxSize = thumbnail ? thumbnailPixel : maxPixel
        var image: CGImage?
        if let source = CGImageSourceCreateWithURL(url(for: id, thumbnail: thumbnail) as CFURL, nil) {
            image = makeImage(from: source, maxPixel: maxSize)
        } else if thumbnail, let source = CGImageSourceCreateWithURL(url(for: id, thumbnail: false) as CFURL, nil) {
            image = makeImage(from: source, maxPixel: maxSize)
        }
        if let image { remember(image, id: id, thumbnail: thumbnail) }
        return image
    }

    private static func key(_ id: UUID, _ thumbnail: Bool) -> NSString {
        (id.uuidString + (thumbnail ? "-thumb" : "")) as NSString
    }

    private static func remember(_ image: CGImage, id: UUID, thumbnail: Bool) {
        cache.setObject(image, forKey: key(id, thumbnail), cost: image.bytesPerRow * image.height)
    }

    /// HEIC keeps transparency and stays small. PNG if HEIC can't be written here.
    private static func encoded(_ image: CGImage) -> Data? {
        for type in [UTType.heic, .png] {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            if CGImageDestinationFinalize(destination) { return data as Data }
        }
        return nil
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let data = encoded(image) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

/// The shape of the whole screen (width ÷ height), which new crops are made for.
@MainActor
func fullScreenAspect() -> CGFloat {
    #if os(macOS)
    let size = (NSApp.keyWindow?.screen ?? NSScreen.main)?.frame.size
    #elseif os(iOS)
    let size = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds.size }.first
    #else
    let size: CGSize? = nil
    #endif
    guard let size, size.width > 0, size.height > 0 else { return 16 / 10 }
    return size.width / size.height
}

// MARK: - Drawing

/// Where a cropped photo is drawn in an area: its size, and where its centre goes.
nonisolated struct CroppedLayout {
    var imageSize: CGSize
    var center: CGPoint
    /// The crop, nudged so the photo covers the whole area.
    var crop: WallpaperCrop

    init(imagePixels: CGSize, area: CGSize, crop: WallpaperCrop) {
        let fill = max(area.width / max(imagePixels.width, 1), area.height / max(imagePixels.height, 1))
        var crop = crop
        crop.zoom = min(max(crop.zoom, WallpaperCrop.zoomRange.lowerBound), WallpaperCrop.zoomRange.upperBound)
        let size = CGSize(width: imagePixels.width * fill * crop.zoom, height: imagePixels.height * fill * crop.zoom)
        let halfX = size.width > 0 ? area.width / (2 * size.width) : 0.5
        let halfY = size.height > 0 ? area.height / (2 * size.height) : 0.5
        crop.centerX = min(max(crop.centerX, halfX), 1 - halfX)
        crop.centerY = min(max(crop.centerY, halfY), 1 - halfY)
        self.imageSize = size
        self.crop = crop
        self.center = CGPoint(
            x: area.width / 2 + (0.5 - crop.centerX) * size.width,
            y: area.height / 2 + (0.5 - crop.centerY) * size.height
        )
    }
}

/// A photo filling its area, showing the part the crop picks.
struct CroppedImage: View {
    var image: CGImage
    var crop: WallpaperCrop

    var body: some View {
        GeometryReader { geometry in
            let layout = CroppedLayout(imagePixels: CGSize(width: image.width, height: image.height), area: geometry.size, crop: crop)
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: layout.imageSize.width, height: layout.imageSize.height)
                .position(layout.center)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// A saved wallpaper, cropped, read from disk in the background. Shows `placeholder` until it's ready.
struct WallpaperImage<Placeholder: View>: View {
    var wallpaper: Wallpaper
    var thumbnail = false
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var loaded: CGImage?
    @State private var loadedID: UUID?

    var body: some View {
        let image = loadedID == wallpaper.id ? loaded : WallpaperFiles.cachedImage(id: wallpaper.id, thumbnail: thumbnail)
        Group {
            if let image {
                CroppedImage(image: image, crop: wallpaper.crop)
            } else {
                placeholder()
            }
        }
        .task(id: wallpaper.id) {
            let id = wallpaper.id, thumbnail = thumbnail
            let image = await Task.detached(priority: .userInitiated) {
                WallpaperFiles.loadImage(id: id, thumbnail: thumbnail)
            }.value
            loaded = image
            loadedID = id
        }
    }
}

// MARK: - Importing

/// An image dragged in from Finder, Photos, a browser or another app.
nonisolated struct DroppedImage: Transferable {
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedImage(data: $0) }
        FileRepresentation(importedContentType: .image) { received in
            DroppedImage(data: try Data(contentsOf: received.file))
        }
        ProxyRepresentation(importing: { (url: URL) in DroppedImage(data: try Data(contentsOf: url)) })
    }
}

/// A photo open in the crop editor: a new one (not saved until it's added) or one already added.
struct WallpaperEdit: Identifiable {
    let id = UUID()
    var image: CGImage
    var crop: WallpaperCrop
    /// Nil for a photo being added.
    var wallpaperID: UUID?
}

// MARK: - Settings row

/// The Add Photo… tile and the added photos, in Settings. Click (or tap) a photo to use it;
/// right-click it (or touch and hold) to crop and zoom it again or remove it.
struct WallpaperPicker: View {
    @Binding var showsAll: Bool
    private var settings = DisplaySettings()

    @State private var edit: WallpaperEdit?
    @State private var isDropTargeted = false
    @State private var isImportFailed = false
    @State private var isLoading = false
    @State private var isColorPadShown = false
    @State private var isGradientPadShown = false
    @State private var export: ExportedWallpaper?
    #if os(macOS)
    @State private var isFileImporterShown = false
    #else
    @State private var photoItem: PhotosPickerItem?
    #endif

    init(showsAll: Binding<Bool>) {
        _showsAll = showsAll
    }

    var body: some View {
        let tile = tileSize
        Group {
            if showsAll {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tile.width, maximum: tile.width * 1.4), spacing: 10)], alignment: .leading, spacing: 10) {
                    tiles(size: tile)
                }
                .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        tiles(size: tile)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.automatic)
            }
        }
        // Drop an image anywhere on the row, the Add Photo… tile lights up
        .dropDestination(for: DroppedImage.self) { items, _ in
            guard let first = items.first else { return false }
            importPhoto(first.data)
            return true
        } isTargeted: { isDropTargeted = $0 }
        #if os(macOS)
        .fileImporter(isPresented: $isFileImporterShown, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                importPhoto(data)
            } else {
                isImportFailed = true
            }
        }
        .sheet(item: $edit) { edit in
            WallpaperCropEditor(edit: edit, onDone: finish)
        }
        #else
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            isLoading = true
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                isLoading = false
                if let data { importPhoto(data) } else { isImportFailed = true }
            }
        }
        .fullScreenCover(item: $edit) { edit in
            WallpaperCropEditor(edit: edit, onDone: finish)
        }
        #endif
        .wallpaperExporter($export)
        .alert("This picture couldn't be opened.", isPresented: $isImportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try another photo, or a file in a common picture format such as JPEG, HEIC or PNG.")
        }
    }

    @ViewBuilder
    private func tiles(size: CGSize) -> some View {
        addTile(size: size)
        colorTile(size: size)
        gradientTile(size: size)
        ForEach(settings.wallpaperFills) { fill in
            fillTile(fill, size: size)
        }
        ForEach(settings.wallpapers) { wallpaper in
            photoTile(wallpaper, size: size)
        }
    }

    private func addTile(size: CGSize) -> some View {
        let label = RoundedRectangle(cornerRadius: 8)
            .fill(isDropTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quaternary))
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                }
            }
            .overlay {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: min(size.height, size.width) * 0.32))
                        // Two lines on a narrow (portrait) tile
                        Text(size.width < 80 ? "Add\nPhoto…" : "Add Photo…")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.secondary)
                    .padding(4)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())

        #if os(macOS)
        return Button { isFileImporterShown = true } label: { label }
            .buttonStyle(.plain)
            .help("Choose a picture, or drop one here")
            .accessibilityLabel("Add Photo")
        #else
        return PhotosPicker(selection: $photoItem, matching: .images) { label }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Photo")
        #endif
    }

    /// A plain color. Tap (or click) to use it and open the color pad.
    private func colorTile(size: CGSize) -> some View {
        let isSelected = settings.wallpaperID == WallpaperBackground.colorID
        return Button {
            choose(WallpaperBackground.colorID)
            isColorPadShown = true
        } label: {
            swatchTile(title: "Color", size: size, isSelected: isSelected) {
                settings.wallpaperColor.color
            }
        }
        .buttonStyle(.plain)
        .help("Use a plain color, chosen on the color pad")
        .accessibilityLabel(isSelected ? "Color wallpaper, chosen, \(settings.wallpaperColor.hex)" : "Color wallpaper, \(settings.wallpaperColor.hex)")
        .modifier(SwatchTileMenu(size: size, actions: [
            saveAction(forTile: WallpaperBackground.colorID, name: "Color"),
            TileMenuAction(title: "Download Image…", symbol: "square.and.arrow.down") { download(.color(settings.wallpaperColor)) },
        ]))
        .popover(isPresented: $isColorPadShown, arrowEdge: .bottom) {
            ColorPadView(target: .wallpaper)
                .fittedSheetOnPhone()
        }
    }

    /// A gradient. Tap (or click) to use it and open the gradient pad.
    private func gradientTile(size: CGSize) -> some View {
        let isSelected = settings.wallpaperID == WallpaperBackground.gradientID
        return Button {
            choose(WallpaperBackground.gradientID)
            isGradientPadShown = true
        } label: {
            swatchTile(title: "Gradient", size: size, isSelected: isSelected) {
                if let gradient = settings.wallpaperGradient {
                    WallpaperBackgroundView(background: .gradient(gradient)) { Color.white }
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Use a gradient, chosen on the gradient pad")
        .accessibilityLabel(isSelected ? "Gradient wallpaper, chosen" : "Gradient wallpaper")
        .modifier(SwatchTileMenu(size: size, actions: [
            saveAction(forTile: WallpaperBackground.gradientID, name: "Gradient"),
            TileMenuAction(title: "Download Image…", symbol: "square.and.arrow.down", isDisabled: settings.wallpaperGradient == nil) {
                settings.wallpaperGradient.map { download(.gradient($0)) }
            },
        ]))
        .popover(isPresented: $isGradientPadShown, arrowEdge: .bottom) {
            GradientPadView(target: .wallpaper)
                .fittedSheetOnPhone()
        }
    }

    /// A tile filled with a color or gradient, named at the bottom, ringed while it's the wallpaper.
    private func swatchTile<Fill: View>(title: String, size: CGSize, isSelected: Bool, showsTitle: Bool = true, @ViewBuilder fill: () -> Fill) -> some View {
        fill()
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) {
                if showsTitle {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.35), lineWidth: 1))
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0))
            .contentShape(Rectangle())
    }

    /// A saved color or gradient. Tap (or click) to use it; right-click or touch and hold to remove it.
    private func fillTile(_ fill: WallpaperFill, size: CGSize) -> some View {
        let isSelected = settings.wallpaperID == fill.id.uuidString
        let isColor = fill.color != nil
        let face = swatchTile(title: "", size: size, isSelected: isSelected, showsTitle: false) {
            if let background = fill.background {
                WallpaperBackgroundView(background: background) { Color.white }
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .onTapGesture { choose(fill.id.uuidString) }

        #if os(iOS)
        let tile = TileMenu(content: face, cornerRadius: 11, actions: [
            TileMenuAction(title: "Download Image…", symbol: "square.and.arrow.down") { fill.background.map(download) },
            TileMenuAction(title: isColor ? "Remove Color" : "Remove Gradient", symbol: "trash", isDestructive: true) { removeFill(fill) },
        ])
        .frame(width: size.width + 6, height: size.height + 6)
        #else
        let tile = face
            .contextMenu {
                Button("Download Image…", systemImage: "square.and.arrow.down") { fill.background.map(download) }
                Button(isColor ? "Remove Color" : "Remove Gradient", systemImage: "trash", role: .destructive) { removeFill(fill) }
            }
            .help("Use this \(isColor ? "color" : "gradient"). Right-click to remove it.")
        #endif

        return tile
            .accessibilityElement()
            .accessibilityLabel("Saved \(isColor ? "color" : "gradient")\(isSelected ? ", chosen" : "")")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { choose(fill.id.uuidString) }
            .accessibilityAction(named: "Download Image") { fill.background.map(download) }
            .accessibilityAction(named: "Remove") { removeFill(fill) }
    }

    /// Save Color / Save Gradient: keeps the tile's current color or gradient as a tile of its own.
    /// Greyed out as "Color Saved" / "Gradient Saved" once that exact look is already saved.
    private func saveAction(forTile id: String, name: String) -> TileMenuAction {
        let fill = settings.fill(forTile: id)
        let isSaved = fill.map { fill in settings.wallpaperFills.contains { $0.sameLook(as: fill) } } ?? true
        return TileMenuAction(title: isSaved ? "\(name) Saved" : "Save \(name)", symbol: isSaved ? "checkmark" : "plus", isDisabled: isSaved) {
            guard let fill = settings.fill(forTile: id),
                  !settings.wallpaperFills.contains(where: { $0.sameLook(as: fill) }) else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                settings.wallpaperFills = [fill] + settings.wallpaperFills
            }
        }
    }

    private func download(_ background: WallpaperBackground) {
        export = ExportedWallpaper(background, dark: settings.appScheme == .dark)
    }

    private func removeFill(_ fill: WallpaperFill) {
        if settings.wallpaperID == fill.id.uuidString {
            // Back to the Color or Gradient tile it was made from
            settings.wallpaperID = fill.color != nil ? WallpaperBackground.colorID : WallpaperBackground.gradientID
        }
        withAnimation(.easeOut(duration: 0.2)) {
            settings.wallpaperFills = settings.wallpaperFills.filter { $0.id != fill.id }
        }
    }

    private func choose(_ id: String) {
        settings.wallpaperID = id
        settings.wallpaperEnabled = true
    }

    private func photoTile(_ wallpaper: Wallpaper, size: CGSize) -> some View {
        let isSelected = wallpaper.id.uuidString == settings.wallpaperID
        let face = WallpaperImage(wallpaper: wallpaper, thumbnail: true) {
            Rectangle().fill(.quaternary)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.secondary.opacity(0.35), lineWidth: 1)
        )
        .padding(3)
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            settings.wallpaperID = wallpaper.id.uuidString
            settings.wallpaperEnabled = true
        }

        #if os(iOS)
        // Touch and hold lifts just this photo. A SwiftUI context menu inside a Form row lifts
        // the whole row, so the menu is attached through UIKit here.
        let tile = TileMenu(content: face, cornerRadius: 11, actions: [
            TileMenuAction(title: "Crop & Zoom…", symbol: "crop") { editAgain(wallpaper) },
            TileMenuAction(title: "Remove Photo", symbol: "trash", isDestructive: true) { remove(wallpaper) },
        ])
        .frame(width: size.width + 6, height: size.height + 6)
        #else
        let tile = face
            .contextMenu {
                Button("Crop & Zoom…", systemImage: "crop") { editAgain(wallpaper) }
                Button("Remove Photo", systemImage: "trash", role: .destructive) { remove(wallpaper) }
            }
            .help("Use this photo. Right-click to crop and zoom it, or to remove it.")
        #endif

        return tile
            .accessibilityElement()
            .accessibilityLabel(isSelected ? "Wallpaper photo, chosen" : "Wallpaper photo")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { settings.wallpaperID = wallpaper.id.uuidString; settings.wallpaperEnabled = true }
            .accessibilityAction(named: "Crop & Zoom") { editAgain(wallpaper) }
            .accessibilityAction(named: "Remove Photo") { remove(wallpaper) }
    }

    /// Thumbnails have the screen's shape, so each shows what its crop puts on screen.
    private var tileSize: CGSize {
        let aspect = min(max(fullScreenAspect(), 0.4), 2.4)
        if aspect >= 1 {
            return CGSize(width: (64 * aspect).rounded(), height: 64)
        }
        return CGSize(width: 60, height: min(60 / aspect, 120).rounded())
    }

    // MARK: Actions

    private func importPhoto(_ data: Data) {
        isLoading = true
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                WallpaperFiles.makeImage(from: data)
            }.value
            isLoading = false
            guard let image else {
                isImportFailed = true
                return
            }
            // Starts centred, just covering the screen
            edit = WallpaperEdit(image: image, crop: WallpaperCrop(), wallpaperID: nil)
        }
    }

    private func editAgain(_ wallpaper: Wallpaper) {
        Task {
            let id = wallpaper.id
            let image = await Task.detached(priority: .userInitiated) {
                WallpaperFiles.loadImage(id: id, thumbnail: false)
            }.value
            guard let image else {
                isImportFailed = true
                return
            }
            edit = WallpaperEdit(image: image, crop: wallpaper.crop, wallpaperID: id)
        }
    }

    /// The editor closed: `crop` is nil when it was cancelled.
    private func finish(_ edit: WallpaperEdit, crop: WallpaperCrop?) {
        self.edit = nil
        guard let crop else { return }
        if let id = edit.wallpaperID {
            var wallpapers = settings.wallpapers
            if let index = wallpapers.firstIndex(where: { $0.id == id }) {
                wallpapers[index].crop = crop
                settings.wallpapers = wallpapers
            }
            return
        }
        let id = UUID()
        let image = edit.image
        Task {
            let saved = await Task.detached(priority: .userInitiated) {
                WallpaperFiles.save(image, id: id)
            }.value
            guard saved else {
                isImportFailed = true
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                settings.wallpapers = [Wallpaper(id: id, crop: crop)] + settings.wallpapers
            }
            settings.wallpaperID = id.uuidString
            settings.wallpaperEnabled = true
        }
    }

    private func remove(_ wallpaper: Wallpaper) {
        let remaining = settings.wallpapers.filter { $0.id != wallpaper.id }
        if settings.wallpaperID == wallpaper.id.uuidString {
            settings.wallpaperID = remaining.first?.id.uuidString ?? ""
        }
        withAnimation(.easeOut(duration: 0.2)) {
            settings.wallpapers = remaining
        }
        let id = wallpaper.id
        Task.detached { WallpaperFiles.remove(id: id) }
    }
}

// MARK: - Crop editor

/// Moves and zooms a photo inside a frame shaped like the screen. Drag to move it; pinch, or use
/// the slider, to zoom. The photo always covers the whole frame.
struct WallpaperCropEditor: View {
    var edit: WallpaperEdit
    var onDone: (WallpaperEdit, WallpaperCrop?) -> Void

    @State private var crop: WallpaperCrop
    @State private var dragStart: WallpaperCrop?
    @State private var zoomStart: Double?
    @State private var aspect: CGFloat
    @State private var isAdjusting = false

    init(edit: WallpaperEdit, onDone: @escaping (WallpaperEdit, WallpaperCrop?) -> Void) {
        self.edit = edit
        self.onDone = onDone
        _crop = State(initialValue: edit.crop)
        _aspect = State(initialValue: fullScreenAspect())
    }

    private var isNew: Bool { edit.wallpaperID == nil }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("Crop & Zoom")
                    .font(.headline)
                Text("Drag to move the photo. Pinch or use the slider to zoom.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            viewport
                .frame(width: viewportSize.width, height: viewportSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.4)))
                .onScrollWheelZoom { factor in setZoom(crop.zoom * factor) }

            zoomSlider
                .frame(maxWidth: 320)

            HStack {
                Button("Reset") { withAnimation(.easeOut(duration: 0.2)) { crop = WallpaperCrop() } }
                    .disabled(crop == WallpaperCrop())
                Spacer()
                Button("Cancel", role: .cancel) { onDone(edit, nil) }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Wallpaper" : "Done") { onDone(edit, crop) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: viewportSize.width + 40)
        #else
        ZStack {
            Color.black
            viewport
                .aspectRatio(aspect, contentMode: .fit)
        }
        .ignoresSafeArea()
        // A mouse wheel, or two fingers on a Magic Keyboard trackpad, zooms (a trackpad pinch works too)
        .onScrollWheelZoom { factor in setZoom(crop.zoom * factor) }
        // The controls stay clear of the Dynamic Island and the home indicator
        .overlay {
            VStack {
                HStack {
                    Button("Cancel", role: .cancel) { onDone(edit, nil) }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction) // Esc on an iPad keyboard
                    Spacer()
                    Button(isNew ? "Add" : "Done") { onDone(edit, crop) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction) // Return on an iPad keyboard
                }
                .controlSize(.large)

                Spacer()

                VStack(spacing: 8) {
                    if !isAdjusting {
                        Text("Drag to move. Pinch to zoom.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    HStack(spacing: 10) {
                        zoomSlider
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { crop = WallpaperCrop() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .disabled(crop == WallpaperCrop())
                        .accessibilityLabel("Reset")
                    }
                    .frame(maxWidth: 480)
                }
            }
            .padding()
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        // The frame keeps the screen's shape when the device turns
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in aspect = fullScreenAspect() }
        #endif
    }

    /// The photo as it will fill the screen, with thirds lines while it's being moved.
    private var viewport: some View {
        GeometryReader { geometry in
            let area = geometry.size
            let layout = CroppedLayout(imagePixels: imagePixels, area: area, crop: crop)
            CroppedImage(image: edit.image, crop: crop)
                .overlay { if isAdjusting { ThirdsGrid() } }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = dragStart ?? layout.crop
                            dragStart = start
                            isAdjusting = true
                            var moved = start
                            moved.zoom = crop.zoom // A pinch may be zooming at the same time
                            moved.centerX -= value.translation.width / max(layout.imageSize.width, 1)
                            moved.centerY -= value.translation.height / max(layout.imageSize.height, 1)
                            crop = CroppedLayout(imagePixels: imagePixels, area: area, crop: moved).crop
                        }
                        .onEnded { _ in
                            dragStart = nil
                            isAdjusting = false
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = zoomStart ?? crop.zoom
                            zoomStart = start
                            isAdjusting = true
                            setZoom(start * value.magnification, in: area)
                        }
                        .onEnded { _ in
                            zoomStart = nil
                            isAdjusting = false
                        }
                )
        }
    }

    private var zoomSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(value: zoomOnDoublingScale, in: 0...log2(WallpaperCrop.zoomRange.upperBound)) {
                Text("Zoom")
            }
            .labelsHidden()
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    /// The slider moves on a doubling scale, so each step zooms by the same amount.
    private var zoomOnDoublingScale: Binding<Double> {
        Binding(
            get: { log2(crop.zoom) },
            set: { setZoom(pow(2, $0)) }
        )
    }

    private func setZoom(_ zoom: Double, in area: CGSize? = nil) {
        var zoomed = crop
        zoomed.zoom = min(max(zoom, WallpaperCrop.zoomRange.lowerBound), WallpaperCrop.zoomRange.upperBound)
        let area = area ?? viewportSize
        crop = CroppedLayout(imagePixels: imagePixels, area: area, crop: zoomed).crop
    }

    private var imagePixels: CGSize { CGSize(width: edit.image.width, height: edit.image.height) }

    /// The frame's size on the Mac: as wide as fits nicely in a sheet, with the screen's shape.
    /// Elsewhere only its shape is used (to keep the photo covering it while zooming).
    private var viewportSize: CGSize {
        #if os(macOS)
        let maxWidth: CGFloat = 560, maxHeight: CGFloat = 420
        var size = CGSize(width: maxWidth, height: maxWidth / aspect)
        if size.height > maxHeight { size = CGSize(width: maxHeight * aspect, height: maxHeight) }
        return CGSize(width: size.width.rounded(), height: size.height.rounded())
        #else
        CGSize(width: aspect, height: 1)
        #endif
    }
}

/// Lines dividing the frame in thirds, to help line the photo up.
private struct ThirdsGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let size = geometry.size
                for i in 1...2 {
                    let x = size.width * CGFloat(i) / 3, y = size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.55), lineWidth: 0.5)
            .shadow(color: .black.opacity(0.4), radius: 1)
        }
        .allowsHitTesting(false)
    }
}

#if os(macOS)
/// Zooms with the scroll wheel (or two fingers up and down on a trackpad) over the photo.
private struct ScrollWheelZoom: ViewModifier {
    var onZoom: (Double) -> Void
    @State private var monitor: Any?
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard isHovering else { return event }
                    let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 200 : event.scrollingDeltaY / 20
                    onZoom(pow(2, delta))
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

private extension View {
    func onScrollWheelZoom(_ onZoom: @escaping (Double) -> Void) -> some View {
        modifier(ScrollWheelZoom(onZoom: onZoom))
    }
}
#else
/// On iPad with a mouse or trackpad: scrolling zooms, as on the Mac. Touches are left alone (the
/// recogniser only takes scroll events), so dragging and pinching the photo still work.
private struct ScrollWheelZoom: UIViewRepresentable {
    var onZoom: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        let recognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scrolled(_:)))
        recognizer.allowedScrollTypesMask = .all
        recognizer.allowedTouchTypes = [] // Scroll events only
        recognizer.cancelsTouchesInView = false
        context.coordinator.recognizer = recognizer
        context.coordinator.onZoom = onZoom
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onZoom = onZoom
        // Listen on the view that holds the photo, once this one is placed in it
        DispatchQueue.main.async {
            guard let recognizer = context.coordinator.recognizer, recognizer.view == nil,
                  let host = view.superview else { return }
            host.addGestureRecognizer(recognizer)
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
    }

    final class Coordinator: NSObject {
        var recognizer: UIPanGestureRecognizer?
        var onZoom: (Double) -> Void = { _ in }
        private var last: CGFloat = 0

        @objc func scrolled(_ recognizer: UIPanGestureRecognizer) {
            let y = recognizer.translation(in: recognizer.view).y
            if recognizer.state == .began { last = 0 }
            let delta = y - last
            last = y
            if recognizer.state == .changed, delta != 0 { onZoom(pow(2, Double(delta) / 200)) }
        }
    }
}

private extension View {
    func onScrollWheelZoom(_ onZoom: @escaping (Double) -> Void) -> some View {
        background(ScrollWheelZoom(onZoom: onZoom))
    }
}
#endif

/// One item in a tile's right-click or touch-and-hold menu.
struct TileMenuAction {
    var title: String
    var symbol: String
    var isDestructive = false
    var isDisabled = false
    var perform: () -> Void
}

#if os(iOS)

/// A SwiftUI view with a UIKit touch-and-hold menu, so the lifted preview is exactly this view
/// (with rounded corners) rather than the whole list row it sits in.
private struct TileMenu<Content: View>: UIViewRepresentable {
    var content: Content
    var cornerRadius: CGFloat
    var actions: [TileMenuAction]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = .clear
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        context.coordinator.host = host
        context.coordinator.cornerRadius = cornerRadius
        context.coordinator.actions = actions
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.host?.rootView = content
        context.coordinator.cornerRadius = cornerRadius
        context.coordinator.actions = actions
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var host: UIHostingController<Content>?
        var cornerRadius: CGFloat = 0
        var actions: [TileMenuAction] = []

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            let actions = actions
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: actions.map { action in
                    UIAction(title: action.title, image: UIImage(systemName: action.symbol),
                             attributes: Self.attributes(of: action)) { _ in action.perform() }
                })
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            preview(for: interaction)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            preview(for: interaction)
        }

        private static func attributes(of action: TileMenuAction) -> UIMenuElement.Attributes {
            var attributes: UIMenuElement.Attributes = []
            if action.isDestructive { attributes.insert(.destructive) }
            if action.isDisabled { attributes.insert(.disabled) }
            return attributes
        }

        /// The tile itself, clipped to its rounded corners.
        private func preview(for interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let view = interaction.view else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(roundedRect: view.bounds, cornerRadius: cornerRadius)
            return UITargetedPreview(view: view, parameters: parameters)
        }
    }
}
#endif

/// The menu of a Color or Gradient tile (Save, Download Image…): on right-click on the Mac, and
/// on touch and hold on iPhone and iPad (lifting just the tile, as with photos).
private struct SwatchTileMenu: ViewModifier {
    var size: CGSize
    var actions: [TileMenuAction]

    func body(content: Content) -> some View {
        #if os(iOS)
        accessible(
            TileMenu(content: content, cornerRadius: 11, actions: actions)
                .frame(width: size.width + 6, height: size.height + 6)
        )
        #else
        accessible(
            content.contextMenu {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title, systemImage: action.symbol, role: action.isDestructive ? .destructive : nil, action: action.perform)
                        .disabled(action.isDisabled)
                }
            }
        )
        #endif
    }

    private func accessible<V: View>(_ view: V) -> AnyView {
        actions.filter { !$0.isDisabled }.reduce(AnyView(view)) { view, action in
            AnyView(view.accessibilityAction(named: action.title, action.perform))
        }
    }
}
