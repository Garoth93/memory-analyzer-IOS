import SwiftUI
import StorageCore

/// Squarified treemap drawn with Canvas (thousands of blocks stay smooth).
/// A tap reports the top-level block under the finger.
struct TreemapView: View {
    @Environment(\.m3) private var m3
    @Environment(\.colorScheme) private var colorScheme
    let node: StorageNode
    let depth: Int
    let colorMode: TreemapColorMode
    let cushion: Bool
    let labels: Bool
    var units: ByteUnits = .decimal
    var thumbnails = false
    var corner: CGFloat = 20
    let onTap: (TreemapTile) -> Void

    @State private var tiles: [TreemapTile] = []
    @State private var layoutKey = ""
    @State private var pressed: String?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let key = "\(node.id)|\(node.size)|\(node.fileCount)|\(Int(size.width))x\(Int(size.height))|\(depth)|\(labels)"
            let colorizer = TileColorizer(mode: colorMode, dark: colorScheme == .dark, seed: seedHex)
            ZStack(alignment: .topLeading) {
                Canvas(rendersAsynchronously: false) { ctx, _ in
                    draw(in: &ctx, colorizer: colorizer)
                }
                if thumbnails {
                    thumbnailLayer(colorizer: colorizer)
                }
                if let pressed, let t = tiles.first(where: { $0.id == pressed && $0.depth == 1 }) {
                    RoundedRectangle(cornerRadius: tileCorner(t), style: .continuous)
                        .strokeBorder(m3.onSurface.opacity(0.9), lineWidth: 2.5)
                        .frame(width: t.rect.w, height: t.rect.h)
                        .offset(x: t.rect.x, y: t.rect.y)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let tile = TreemapLayout.hitTop(tiles, x: value.location.x, y: value.location.y) else { return }
                        pressed = tile.id
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(120))
                            pressed = nil
                            onTap(tile)
                        }
                    }
            )
            .onChange(of: key, initial: true) { _, newKey in
                guard newKey != layoutKey else { return }
                layoutKey = newKey
                tiles = TreemapLayout.tiles(
                    for: node,
                    in: TMRect(x: 0, y: 0, w: size.width, h: size.height),
                    options: TreemapOptions(maxDepth: depth, padding: 2, headerHeight: labels ? 17 : 0, minSide: 1.2, minExpandSide: 30)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mappa di \(node.name)")
        .accessibilityValue(node.children.prefix(5).map { "\($0.name) \(Fmt.bytes($0.size, units: units))" }.joined(separator: ", "))
    }

    @Environment(AppModel.self) private var model
    private var seedHex: String { model.settings.seed }

    private func tileCorner(_ t: TreemapTile) -> CGFloat {
        min(t.depth == 1 ? 10 : 6, CGFloat(t.rect.minSide) / 4)
    }

    private func cgRect(_ r: TMRect) -> CGRect {
        CGRect(x: r.x, y: r.y, width: r.w, height: r.h)
    }

    // MARK: - Drawing

    private func draw(in ctx: inout GraphicsContext, colorizer: TileColorizer) {
        for t in tiles {
            let gap: CGFloat = t.depth == 1 ? 1.5 : 1
            let rect = cgRect(t.rect).insetBy(dx: gap / 2, dy: gap / 2)
            guard rect.width > 0.4, rect.height > 0.4 else { continue }
            let path = Path(roundedRect: rect, cornerRadius: tileCorner(t), style: .continuous)
            if t.hasNestedTiles {
                let c = colorizer.container(depth: t.depth)
                ctx.fill(path, with: .color(c.base))
                if labels, let header = t.header {
                    drawHeader(in: &ctx, tile: t, header: cgRect(header), colors: c)
                }
                continue
            }
            let c = colorizer.leaf(category: t.category, ext: t.ext, topIndex: t.topIndex, depth: t.depth, id: t.id)
            if cushion && rect.width > 3 && rect.height > 3 {
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [c.light, c.base, c.dark]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ))
                // Soft highlight like WizTree's cushions.
                if rect.width > 14 && rect.height > 14 {
                    ctx.fill(path, with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18), .clear]),
                        center: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.25),
                        startRadius: 0,
                        endRadius: max(rect.width, rect.height) * 0.8
                    ))
                }
            } else {
                ctx.fill(path, with: .color(c.base))
            }
            if t.category == .free {
                ctx.stroke(path, with: .color(c.dark.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if labels && !(thumbnails && t.kind == .asset && rect.width >= 44 && rect.height >= 44) {
                drawLabel(in: &ctx, tile: t, rect: rect, colors: c)
            }
        }
    }

    private func drawHeader(in ctx: inout GraphicsContext, tile: TreemapTile, header: CGRect, colors: TileColors) {
        let r = header.insetBy(dx: 6, dy: 1)
        guard r.width > 24 else { return }
        let name = Text(tile.name).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(colors.text)
        let size = Text(Fmt.bytes(tile.size, units: units)).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(colors.secondaryText)
        let text = Text("\(name)  \(size)")
        ctx.draw(text, in: r)
    }

    private func drawLabel(in ctx: inout GraphicsContext, tile: TreemapTile, rect: CGRect, colors: TileColors) {
        guard rect.width >= 46, rect.height >= 24 else { return }
        let big = rect.width >= 130 && rect.height >= 72
        let nameSize: CGFloat = big ? 15 : (rect.width >= 80 && rect.height >= 40 ? 12 : 10)
        let inner = rect.insetBy(dx: big ? 10 : 5, dy: big ? 8 : 4)
        let name = Text(tile.name)
            .font(.system(size: nameSize, weight: .bold, design: .rounded))
            .foregroundStyle(colors.text)
        let size = Text(Fmt.bytes(tile.size, units: units))
            .font(.system(size: nameSize - 1, weight: .medium, design: .rounded))
            .foregroundStyle(colors.secondaryText)
        if rect.height >= (big ? 56 : 34) {
            ctx.draw(Text("\(name)\n\(size)"), in: inner)
        } else {
            ctx.draw(name, in: inner)
        }
    }

    // MARK: - Photo thumbnails

    @ViewBuilder
    private func thumbnailLayer(colorizer: TileColorizer) -> some View {
        let shown = tiles.filter { $0.kind == .asset && $0.rect.w >= 44 && $0.rect.h >= 44 }.prefix(150)
        ForEach(Array(shown), id: \.id) { t in
            let c = colorizer.leaf(category: t.category, ext: t.ext, topIndex: t.topIndex, depth: t.depth, id: t.id)
            AssetThumbnail(id: t.id, pixels: CGFloat(max(t.rect.w, t.rect.h)) * 2)
                .frame(width: max(0, t.rect.w - 2), height: max(0, t.rect.h - 2))
                .clipShape(RoundedRectangle(cornerRadius: tileCorner(t), style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if t.rect.w >= 70 && t.rect.h >= 50 {
                        Text(Fmt.bytes(t.size, units: units))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(c.text)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(c.base, in: Capsule())
                            .padding(5)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: tileCorner(t), style: .continuous)
                        .strokeBorder(c.base, lineWidth: 2)
                }
                .offset(x: t.rect.x + 1, y: t.rect.y + 1)
                .allowsHitTesting(false)
        }
    }
}

/// Square photo thumbnail loaded from PhotoKit.
struct AssetThumbnail: View {
    @Environment(\.m3) private var m3
    let id: String
    var pixels: CGFloat = 200
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            m3.surfaceContainerHighest
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: id) {
            let img = await ThumbnailLoader.shared.image(for: id, pixels: pixels)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}
