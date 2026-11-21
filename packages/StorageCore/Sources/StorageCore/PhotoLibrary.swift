import Foundation

/// Kind of a photo library asset (from PHAsset media type + subtypes).
public enum PhotoMediaKind: String, Codable, CaseIterable, Sendable {
    case photo
    case livePhoto
    case screenshot
    case panorama
    case video
    case slowMotion
    case timelapse

    public var label: String {
        switch self {
        case .photo: return "Foto"
        case .livePhoto: return "Live Photo"
        case .screenshot: return "Screenshot"
        case .panorama: return "Panoramiche"
        case .video: return "Video"
        case .slowMotion: return "Slow motion"
        case .timelapse: return "Time-lapse"
        }
    }

    public var icon: String {
        switch self {
        case .photo: return "photo.fill"
        case .livePhoto: return "livephoto"
        case .screenshot: return "camera.viewfinder"
        case .panorama: return "pano.fill"
        case .video: return "video.fill"
        case .slowMotion: return "slowmo"
        case .timelapse: return "timelapse"
        }
    }

    public var category: FileCategory {
        switch self {
        case .photo, .panorama: return .image
        case .livePhoto: return .livePhoto
        case .screenshot: return .screenshot
        case .video, .slowMotion, .timelapse: return .video
        }
    }

    public var isVideo: Bool { category == .video }
}

/// One asset of the photo library as measured by the scan.
public struct PhotoItem: Codable, Equatable, Sendable, Identifiable {
    /// PHAsset.localIdentifier.
    public var id: String
    public var filename: String
    public var kind: PhotoMediaKind
    public var date: Date?
    /// Sum of all the asset resources (original, edits, paired video).
    public var size: Int64
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var duration: Double
    public var isFavorite: Bool
    public var isHidden: Bool

    public init(id: String, filename: String, kind: PhotoMediaKind, date: Date?, size: Int64,
                pixelWidth: Int = 0, pixelHeight: Int = 0, duration: Double = 0,
                isFavorite: Bool = false, isHidden: Bool = false) {
        self.id = id
        self.filename = filename
        self.kind = kind
        self.date = date
        self.size = size
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.isFavorite = isFavorite
        self.isHidden = isHidden
    }

    /// "4032×3024" (+ " · 1:05" for videos).
    public var detail: String {
        var s = "\(pixelWidth)×\(pixelHeight)"
        if kind.isVideo { s += " · " + Fmt.duration(duration) }
        return s
    }

    public var leaf: StorageNode {
        StorageNode(id: id, name: filename.isEmpty ? kind.label : filename, kind: .asset, size: size,
                    modified: date, category: kind.category, ext: FileCategory.ext(of: filename),
                    ref: id, detail: detail)
    }
}

public enum PhotoGrouping: String, Codable, CaseIterable, Sendable {
    /// Year → month → assets.
    case date
    /// Kind → year → assets.
    case kind

    public var label: String {
        switch self {
        case .date: return "Anno e mese"
        case .kind: return "Tipo e anno"
        }
    }
}

public enum PhotoTreeBuilder {
    public static let rootID = "photos"

    /// Tree of the library for the map.
    public static func build(_ items: [PhotoItem], grouping: PhotoGrouping, timeZone: TimeZone = .current) -> StorageNode {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let children: [StorageNode]
        switch grouping {
        case .date:
            children = byYear(items, prefix: rootID, cal: cal, months: true)
        case .kind:
            let groups = Dictionary(grouping: items, by: \.kind)
            children = groups.map { kind, list in
                let id = "\(rootID)/\(kind.rawValue)"
                return StorageNode.container(id: id, name: kind.label, kind: .group, children: byYear(list, prefix: id, cal: cal, months: list.count > 400))
            }
        }
        return .container(id: rootID, name: "Foto e video", kind: .group, children: children)
    }

    private static func byYear(_ items: [PhotoItem], prefix: String, cal: Calendar, months: Bool) -> [StorageNode] {
        let groups = Dictionary(grouping: items) { item -> Int in
            item.date.map { cal.component(.year, from: $0) } ?? 0
        }
        return groups.map { year, list in
            let id = "\(prefix)/\(year)"
            let name = year == 0 ? "Senza data" : String(year)
            guard months, year != 0 else {
                return StorageNode.container(id: id, name: name, kind: .group, children: list.map(\.leaf))
            }
            let byMonth = Dictionary(grouping: list) { cal.component(.month, from: $0.date ?? Date()) }
            let monthNodes = byMonth.map { month, assets in
                StorageNode.container(id: "\(id)/\(month)", name: "\(Fmt.monthNames[max(1, min(12, month)) - 1]) \(year)", kind: .group, children: assets.map(\.leaf))
            }
            return StorageNode.container(id: id, name: name, kind: .group, children: monthNodes)
        }
    }
}

/// Totals of the library per kind.
public struct PhotoSummary: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public var kind: PhotoMediaKind
        public var count: Int
        public var size: Int64
        public var id: PhotoMediaKind { kind }
    }

    public var rows: [Row]
    public var totalSize: Int64
    public var totalCount: Int
    public var photoCount: Int
    public var videoCount: Int
    public var favoriteCount: Int
    public var hiddenCount: Int
    public var oldest: Date?
    public var newest: Date?

    public init(_ items: [PhotoItem]) {
        var map: [PhotoMediaKind: Row] = [:]
        var total: Int64 = 0, videos = 0, favorites = 0, hidden = 0
        var oldest: Date?, newest: Date?
        for i in items {
            var r = map[i.kind] ?? Row(kind: i.kind, count: 0, size: 0)
            r.count += 1
            r.size += i.size
            map[i.kind] = r
            total += i.size
            if i.kind.isVideo { videos += 1 }
            if i.isFavorite { favorites += 1 }
            if i.isHidden { hidden += 1 }
            if let d = i.date {
                if oldest.map({ d < $0 }) ?? true { oldest = d }
                if newest.map({ d > $0 }) ?? true { newest = d }
            }
        }
        rows = map.values.sorted { $0.size != $1.size ? $0.size > $1.size : $0.kind.rawValue < $1.kind.rawValue }
        totalSize = total
        totalCount = items.count
        videoCount = videos
        photoCount = items.count - videos
        favoriteCount = favorites
        hiddenCount = hidden
        self.oldest = oldest
        self.newest = newest
    }
}
