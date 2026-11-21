import Foundation

public enum Appearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var label: String {
        switch self {
        case .system: return "Automatico"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }
}

/// How the blocks of the map are colored.
public enum TreemapColorMode: String, Codable, CaseIterable, Sendable {
    /// By file type, like WizTree.
    case type
    /// One hue per top-level block, shades for its content.
    case folder

    public var label: String {
        switch self {
        case .type: return "Per tipo di file"
        case .folder: return "Per cartella"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var appearance: Appearance
    public var seed: String
    public var units: ByteUnits
    public var colorMode: TreemapColorMode
    /// Levels drawn inside the map (1…4).
    public var depth: Int
    /// 3D "cushion" shading of the blocks.
    public var cushion: Bool
    public var labels: Bool
    /// Thumbnails on photo blocks.
    public var thumbnails: Bool
    public var photoGrouping: PhotoGrouping
    public var includeHidden: Bool
    /// Haptic feedback when zooming.
    public var haptics: Bool

    public init(
        appearance: Appearance = .system, seed: String = Palette.defaultAccent, units: ByteUnits = .decimal,
        colorMode: TreemapColorMode = .type, depth: Int = 3, cushion: Bool = true, labels: Bool = true,
        thumbnails: Bool = true, photoGrouping: PhotoGrouping = .date, includeHidden: Bool = true, haptics: Bool = true
    ) {
        self.appearance = appearance
        self.seed = seed
        self.units = units
        self.colorMode = colorMode
        self.depth = min(4, max(1, depth))
        self.cushion = cushion
        self.labels = labels
        self.thumbnails = thumbnails
        self.photoGrouping = photoGrouping
        self.includeHidden = includeHidden
        self.haptics = haptics
    }

    /// Lenient: unknown or missing keys fall back to the defaults.
    public init(from decoder: Decoder) throws {
        let d = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
        seed = (try? c.decodeIfPresent(String.self, forKey: .seed)).flatMap { RGBColor(hex: $0) != nil ? $0 : nil } ?? d.seed
        units = (try? c.decodeIfPresent(ByteUnits.self, forKey: .units)) ?? d.units
        colorMode = (try? c.decodeIfPresent(TreemapColorMode.self, forKey: .colorMode)) ?? d.colorMode
        depth = min(4, max(1, (try? c.decodeIfPresent(Int.self, forKey: .depth)) ?? d.depth))
        cushion = (try? c.decodeIfPresent(Bool.self, forKey: .cushion)) ?? d.cushion
        labels = (try? c.decodeIfPresent(Bool.self, forKey: .labels)) ?? d.labels
        thumbnails = (try? c.decodeIfPresent(Bool.self, forKey: .thumbnails)) ?? d.thumbnails
        photoGrouping = (try? c.decodeIfPresent(PhotoGrouping.self, forKey: .photoGrouping)) ?? d.photoGrouping
        includeHidden = (try? c.decodeIfPresent(Bool.self, forKey: .includeHidden)) ?? d.includeHidden
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? d.haptics
    }
}

/// Last photo library scan (items are kept, the tree is rebuilt on load).
public struct PhotoScanRecord: Codable, Equatable, Sendable {
    public var date: Date
    public var items: [PhotoItem]
    /// Seconds the scan took.
    public var elapsed: Double

    public init(date: Date, items: [PhotoItem], elapsed: Double) {
        self.date = date
        self.items = items
        self.elapsed = elapsed
    }
}

/// A folder chosen in Files and its last scan.
public struct FolderScanRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Security-scoped bookmark to reopen the folder.
    public var bookmark: Data
    public var date: Date
    public var elapsed: Double
    public var root: StorageNode
    /// True when the folder is on this iPhone (counted in the device map).
    public var isLocal: Bool

    public init(id: UUID = UUID(), name: String, bookmark: Data, date: Date, elapsed: Double, root: StorageNode, isLocal: Bool) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.date = date
        self.elapsed = elapsed
        self.root = root
        self.isLocal = isLocal
    }
}

public enum FolderLocation {
    /// "On my iPhone" and the app containers are local; iCloud Drive and
    /// File Provider extensions (Drive, OneDrive, SMB…) are not.
    public static func isLocal(path: String) -> Bool {
        let p = path.lowercased()
        if p.contains("/mobile documents/") || p.contains("/library/cloudstorage/") || p.contains("fileprovider") { return false }
        return true
    }
}
