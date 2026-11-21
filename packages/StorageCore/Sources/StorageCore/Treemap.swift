import Foundation

/// Plain rectangle (points), independent from CoreGraphics so it works on Linux.
public struct TMRect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = max(0, w)
        self.h = max(0, h)
    }

    public static let zero = TMRect(x: 0, y: 0, w: 0, h: 0)

    public var area: Double { w * h }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public var minSide: Double { min(w, h) }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= maxX && py >= y && py <= maxY
    }

    public func insetBy(_ d: Double) -> TMRect {
        TMRect(x: x + d, y: y + d, w: w - 2 * d, h: h - 2 * d)
    }

    /// Removes `top` points from the top edge (label header).
    public func droppingTop(_ top: Double) -> TMRect {
        TMRect(x: x, y: y + top, w: w, h: h - top)
    }

    /// Aspect ratio ≥ 1 (1 = square).
    public var aspect: Double {
        guard w > 0, h > 0 else { return .infinity }
        return max(w / h, h / w)
    }
}

/// Squarified treemap (Bruls, Huizing, van Wijk 2000).
public enum Treemap {
    /// Rectangles for `values` (same order as the input), filling `rect`.
    /// Areas are proportional to the values; zero or negative values get `.zero`.
    public static func squarify(_ values: [Double], in rect: TMRect) -> [TMRect] {
        var result = Array(repeating: TMRect.zero, count: values.count)
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }
        let total = order.reduce(0.0) { $0 + values[$1] }
        guard total > 0, rect.w > 0, rect.h > 0 else { return result }
        let scale = rect.area / total
        let areas = order.map { values[$0] * scale }

        var remaining = rect
        var i = 0
        while i < areas.count {
            let side = remaining.minSide
            guard side > 0 else { break }
            var rowSum = areas[i]
            var rowMin = areas[i], rowMax = areas[i]
            var current = worst(sum: rowSum, min: rowMin, max: rowMax, side: side)
            var j = i + 1
            while j < areas.count {
                let a = areas[j]
                let candidate = worst(sum: rowSum + a, min: Swift.min(rowMin, a), max: Swift.max(rowMax, a), side: side)
                if candidate > current { break }
                rowSum += a
                rowMin = Swift.min(rowMin, a)
                rowMax = Swift.max(rowMax, a)
                current = candidate
                j += 1
            }
            let isLast = j >= areas.count
            if remaining.w >= remaining.h {
                // Column on the left, items stacked top to bottom.
                let thickness = isLast ? remaining.w : rowSum / remaining.h
                var y = remaining.y
                for k in i..<j {
                    let h = k == j - 1 ? remaining.maxY - y : areas[k] / thickness
                    result[order[k]] = TMRect(x: remaining.x, y: y, w: thickness, h: h)
                    y += h
                }
                remaining = TMRect(x: remaining.x + thickness, y: remaining.y, w: remaining.w - thickness, h: remaining.h)
            } else {
                // Row on the top, items left to right.
                let thickness = isLast ? remaining.h : rowSum / remaining.w
                var x = remaining.x
                for k in i..<j {
                    let w = k == j - 1 ? remaining.maxX - x : areas[k] / thickness
                    result[order[k]] = TMRect(x: x, y: remaining.y, w: w, h: thickness)
                    x += w
                }
                remaining = TMRect(x: remaining.x, y: remaining.y + thickness, w: remaining.w, h: remaining.h - thickness)
            }
            i = j
        }
        return result
    }

    /// Worst aspect ratio of a row with total area `sum` laid along `side`.
    static func worst(sum: Double, min: Double, max: Double, side: Double) -> Double {
        guard sum > 0, min > 0 else { return .infinity }
        let s2 = sum * sum, w2 = side * side
        return Swift.max(w2 * max / s2, s2 / (w2 * min))
    }
}

/// One drawn block of the map.
public struct TreemapTile: Equatable, Sendable, Identifiable {
    public var id: String
    /// Index path from the node being displayed.
    public var path: [Int]
    public var rect: TMRect
    /// 1 = direct child of the displayed node.
    public var depth: Int
    public var name: String
    public var size: Int64
    public var category: FileCategory
    public var kind: NodeKind
    public var ext: String
    /// True when the tile is a container whose children are drawn inside it.
    public var hasNestedTiles: Bool
    /// Rect reserved for the label of an expanded container (header strip).
    public var header: TMRect?

    public var isLeaf: Bool { kind != .folder && kind != .group }
    /// Index of the depth-1 ancestor (for "per cartella" colors).
    public var topIndex: Int { path.first ?? 0 }
}

public struct TreemapOptions: Equatable, Sendable {
    /// Levels drawn below the displayed node (1 = only its children).
    public var maxDepth: Int
    /// Gap between a container and its nested tiles.
    public var padding: Double
    /// Header strip for container labels (0 = no header).
    public var headerHeight: Double
    /// Tiles smaller than this (both sides) are not emitted.
    public var minSide: Double
    /// Containers smaller than this are not expanded.
    public var minExpandSide: Double

    public init(maxDepth: Int = 3, padding: Double = 2, headerHeight: Double = 16, minSide: Double = 1.5, minExpandSide: Double = 28) {
        self.maxDepth = max(1, maxDepth)
        self.padding = padding
        self.headerHeight = headerHeight
        self.minSide = minSide
        self.minExpandSide = minExpandSide
    }
}

public enum TreemapLayout {
    /// Tiles in drawing order (parents before their children).
    public static func tiles(for node: StorageNode, in rect: TMRect, options: TreemapOptions = TreemapOptions()) -> [TreemapTile] {
        var out: [TreemapTile] = []
        layout(node, in: rect, depth: 1, prefix: [], options: options, into: &out)
        return out
    }

    private static func layout(_ node: StorageNode, in rect: TMRect, depth: Int, prefix: [Int], options: TreemapOptions, into out: inout [TreemapTile]) {
        guard !node.children.isEmpty, rect.w > 0, rect.h > 0 else { return }
        let rects = Treemap.squarify(node.children.map { Double($0.size) }, in: rect)
        for (i, child) in node.children.enumerated() {
            let r = rects[i]
            guard r.w >= options.minSide, r.h >= options.minSide else { continue }
            let path = prefix + [i]
            let canExpand = depth < options.maxDepth && child.isContainer && !child.children.isEmpty
                && r.minSide >= options.minExpandSide && child.size > 0
            var header: TMRect?
            var inner = r.insetBy(options.padding)
            if canExpand, options.headerHeight > 0, r.h >= options.headerHeight * 3, r.w >= 48 {
                header = TMRect(x: r.x, y: r.y, w: r.w, h: options.headerHeight)
                inner = TMRect(x: r.x + options.padding, y: r.y + options.headerHeight, w: r.w - 2 * options.padding, h: r.h - options.headerHeight - options.padding)
            }
            out.append(TreemapTile(
                id: child.id, path: path, rect: r, depth: depth, name: child.name, size: child.size,
                category: child.category, kind: child.kind, ext: child.ext,
                hasNestedTiles: canExpand, header: canExpand ? header : nil
            ))
            if canExpand {
                layout(child, in: inner, depth: depth + 1, prefix: path, options: options, into: &out)
            }
        }
    }

    /// Deepest tile containing the point.
    public static func hit(_ tiles: [TreemapTile], x: Double, y: Double) -> TreemapTile? {
        var best: TreemapTile?
        for t in tiles where t.rect.contains(x: x, y: y) {
            if best == nil || t.depth >= best!.depth { best = t }
        }
        return best
    }

    /// Depth-1 tile containing the point (the block a tap drills into).
    public static func hitTop(_ tiles: [TreemapTile], x: Double, y: Double) -> TreemapTile? {
        tiles.first { $0.depth == 1 && $0.rect.contains(x: x, y: y) }
    }
}
