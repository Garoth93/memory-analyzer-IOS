import Foundation

/// What a block of the map contains. Drives the color of the tile,
/// the icon and the "Tipi" statistics.
public enum FileCategory: String, Codable, CaseIterable, Sendable {
    case video
    case image
    case livePhoto
    case screenshot
    case audio
    case document
    case archive
    case code
    case app
    case data
    case font
    case system
    case folder
    case free
    case other

    /// Italian label used in legends and lists.
    public var label: String {
        switch self {
        case .video: return "Video"
        case .image: return "Immagini"
        case .livePhoto: return "Live Photo"
        case .screenshot: return "Screenshot"
        case .audio: return "Audio"
        case .document: return "Documenti"
        case .archive: return "Archivi"
        case .code: return "Codice"
        case .app: return "App e binari"
        case .data: return "Dati e database"
        case .font: return "Font"
        case .system: return "Sistema e altri dati"
        case .folder: return "Cartelle"
        case .free: return "Spazio libero"
        case .other: return "Altro"
        }
    }

    /// SF Symbol name (resolved by the app).
    public var icon: String {
        switch self {
        case .video: return "film.fill"
        case .image: return "photo.fill"
        case .livePhoto: return "livephoto"
        case .screenshot: return "camera.viewfinder"
        case .audio: return "waveform"
        case .document: return "doc.text.fill"
        case .archive: return "archivebox.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .app: return "app.badge.fill"
        case .data: return "cylinder.split.1x2.fill"
        case .font: return "textformat"
        case .system: return "gearshape.2.fill"
        case .folder: return "folder.fill"
        case .free: return "circle.dashed"
        case .other: return "doc.fill"
        }
    }

    /// Hue (LCh degrees) and chroma of the tonal palette used for this category.
    /// Picked so neighbouring categories stay distinguishable, like WizTree's map.
    public var hue: Double {
        switch self {
        case .video: return 305
        case .image: return 95
        case .livePhoto: return 60
        case .screenshot: return 200
        case .audio: return 350
        case .document: return 265
        case .archive: return 25
        case .code: return 175
        case .app: return 50
        case .data: return 225
        case .font: return 130
        case .system: return 250
        case .folder: return 250
        case .free: return 145
        case .other: return 250
        }
    }

    public var chroma: Double {
        switch self {
        case .system, .folder, .other: return 8
        case .free: return 30
        default: return 62
        }
    }

    public var palette: TonalPalette { TonalPalette(hue: hue, chroma: chroma) }

    // MARK: - Classification

    private static let table: [String: FileCategory] = {
        var t: [String: FileCategory] = [:]
        func add(_ category: FileCategory, _ exts: [String]) { for e in exts { t[e] = category } }
        add(.video, ["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "mts", "m2ts", "ts", "vob", "hevc"])
        add(.image, ["jpg", "jpeg", "heic", "heif", "png", "gif", "bmp", "tif", "tiff", "webp", "raw", "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "svg", "psd", "ico", "avif", "jxl"])
        add(.audio, ["mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "ogg", "opus", "wma", "caf", "amr", "alac", "mid", "midi"])
        add(.document, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf", "txt", "md", "pages", "numbers", "key", "epub", "csv", "tex", "log"])
        add(.archive, ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "iso", "dmg", "img", "wad", "pak", "cab", "lz4"])
        add(.code, ["swift", "c", "h", "cpp", "hpp", "cc", "cs", "java", "kt", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "php", "html", "htm", "css", "scss", "sh", "qml", "m", "mm", "dart", "lua", "sql", "yml", "yaml", "toml", "xml", "json", "plist", "pdb", "obj", "o"])
        add(.app, ["ipa", "app", "apk", "aab", "exe", "dll", "so", "dylib", "a", "lib", "framework", "bin", "msi", "deb", "rpm", "jar", "wasm", "car", "nib", "storyboardc", "appex"])
        add(.data, ["db", "sqlite", "sqlite3", "realm", "sqlite-wal", "sqlite-shm", "wal", "shm", "dat", "cache", "data", "mdb", "ldb", "idx", "pack", "vmdk", "vdi", "qcow2", "sav", "bak", "tmp", "temp", "blob"])
        add(.font, ["ttf", "otf", "ttc", "woff", "woff2"])
        return t
    }()

    /// Category of a file extension (case-insensitive, with or without dot).
    public static func classify(ext: String) -> FileCategory {
        var e = ext.lowercased()
        if e.hasPrefix(".") { e.removeFirst() }
        return table[e] ?? .other
    }

    /// Lowercased extension of a file name ("" when there is none).
    public static func ext(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        let e = name[name.index(after: dot)...]
        guard !e.isEmpty, e.count <= 12, !e.contains(" ") else { return "" }
        return e.lowercased()
    }

    /// WizTree-like "Tipo file" description ("File HEIC", "Video MOV", …).
    public static func describe(ext: String, category: FileCategory) -> String {
        let up = ext.uppercased()
        if up.isEmpty { return "File senza estensione" }
        switch category {
        case .video: return "Video \(up)"
        case .image, .livePhoto, .screenshot: return "Immagine \(up)"
        case .audio: return "Audio \(up)"
        case .document: return "Documento \(up)"
        case .archive: return "Archivio \(up)"
        case .code: return "Sorgente \(up)"
        case .app: return "Binario \(up)"
        case .data: return "Dati \(up)"
        case .font: return "Font \(up)"
        default: return "File \(up)"
        }
    }
}
