import Foundation

public struct ScanProgress: Equatable, Sendable {
    public var files: Int
    public var folders: Int
    public var bytes: Int64
    /// Folders whose content could not be listed.
    public var unreadable: Int
    /// Path (relative to the root) of the folder being read.
    public var current: String

    public init(files: Int = 0, folders: Int = 0, bytes: Int64 = 0, unreadable: Int = 0, current: String = "") {
        self.files = files
        self.folders = folders
        self.bytes = bytes
        self.unreadable = unreadable
        self.current = current
    }
}

public struct ScanCancelled: Error, Equatable {
    public init() {}
}

/// The chosen folder itself cannot be listed.
public struct FolderUnreadable: Error, Equatable, LocalizedError {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    public var errorDescription: String? {
        "Non riesco a leggere il contenuto della cartella (\(reason))."
    }
}

/// Recursive folder scan with FileManager (works on iOS and Linux).
/// Symbolic links are not followed; folders that cannot be listed become
/// empty nodes marked with `unreadableDetail`.
public final class DirectoryScanner {
    /// Lists the direct children of a folder. The app passes one that falls
    /// back to NSFileCoordinator for File Provider folders (iCloud Drive…).
    public typealias Lister = (URL) throws -> [URL]

    public static let unreadableDetail = "Cartella non leggibile"

    public static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey
    ]
    private static let keySet = Set(resourceKeys)

    /// Plain FileManager listing (hidden files included).
    public static func defaultLister(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [])
    }

    private let fm = FileManager.default
    private let progress: ((ScanProgress) -> Void)?
    private let isCancelled: () -> Bool
    private let lister: Lister
    private var state = ScanProgress()
    private var lastReport = 0

    public init(progress: ((ScanProgress) -> Void)? = nil, isCancelled: @escaping () -> Bool = { false }, lister: Lister? = nil) {
        self.progress = progress
        self.isCancelled = isCancelled
        self.lister = lister ?? DirectoryScanner.defaultLister
    }

    /// Final counters of the last scan.
    public var lastProgress: ScanProgress { state }

    /// Scans `url`; the root node is named `name` (default: the folder name).
    public func scan(_ url: URL, name: String? = nil) throws -> StorageNode {
        state = ScanProgress()
        lastReport = 0
        let entries: [URL]
        do {
            entries = try lister(url)
        } catch {
            throw FolderUnreadable(path: url.path, reason: (error as NSError).localizedDescription)
        }
        var root = try folder(url, relative: "", entries: entries)
        root.name = name ?? url.lastPathComponent
        progress?(state)
        return root
    }

    /// What we need to know about one entry.
    struct EntryInfo: Equatable {
        var isDirectory: Bool
        var isSymbolicLink: Bool
        var size: Int64
        var allocated: Int64
        var modified: Date?
    }

    /// Resource values with a POSIX fallback: on iOS the values of File
    /// Provider items (folders not yet materialized, iCloud placeholders)
    /// can be missing, and a missing `isDirectory` must not turn a folder
    /// into a 0-byte file.
    func info(_ url: URL) -> EntryInfo {
        let v = try? url.resourceValues(forKeys: Self.keySet)
        var isDir = v?.isDirectory
        var isLink = v?.isSymbolicLink
        var size = v?.fileSize.map(Int64.init)
        var modified = v?.contentModificationDate
        if isDir == nil || isLink == nil || (isDir == false && size == nil) {
            if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                let type = attrs[.type] as? FileAttributeType
                if isDir == nil { isDir = type == .typeDirectory }
                if isLink == nil { isLink = type == .typeSymbolicLink }
                if size == nil { size = Self.int64(attrs[.size]) }
                if modified == nil { modified = attrs[.modificationDate] as? Date }
            }
            if isDir == nil {
                var d: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &d) { isDir = d.boolValue }
            }
        }
        let logical = size ?? 0
        let allocated = (v?.totalFileAllocatedSize ?? v?.fileAllocatedSize).map(Int64.init) ?? logical
        return EntryInfo(isDirectory: isDir ?? false, isSymbolicLink: isLink ?? false, size: logical, allocated: allocated, modified: modified)
    }

    static func int64(_ any: Any?) -> Int64? {
        if let n = any as? NSNumber { return n.int64Value }
        if let n = any as? UInt64 { return Int64(clamping: n) }
        if let n = any as? Int64 { return n }
        if let n = any as? Int { return Int64(n) }
        return nil
    }

    private func folder(_ url: URL, relative: String, entries: [URL]? = nil) throws -> StorageNode {
        if isCancelled() { throw ScanCancelled() }
        state.folders += 1
        state.current = relative
        var listed = entries
        if listed == nil { listed = try? lister(url) }
        var children: [StorageNode] = []
        children.reserveCapacity(listed?.count ?? 0)
        for entry in listed ?? [] {
            let info = info(entry)
            if info.isSymbolicLink { continue }
            let name = entry.lastPathComponent
            let rel = relative.isEmpty ? name : relative + "/" + name
            if info.isDirectory {
                children.append(try folder(entry, relative: rel))
            } else {
                children.append(.file(id: rel, name: name, size: info.size, allocated: info.allocated, modified: info.modified, ref: rel))
                state.files += 1
                state.bytes += info.size
                if state.files - lastReport >= 250 {
                    lastReport = state.files
                    if isCancelled() { throw ScanCancelled() }
                    progress?(state)
                }
            }
        }
        let display = relative.isEmpty ? url.lastPathComponent : (relative.split(separator: "/").last.map(String.init) ?? relative)
        var node = StorageNode.container(id: relative.isEmpty ? "/" : relative, name: display, kind: .folder, ref: relative, children: children)
        if listed == nil {
            state.unreadable += 1
            node.detail = Self.unreadableDetail
        }
        return node
    }
}

extension StorageNode {
    /// Folders below (and including) this node that could not be listed.
    public var unreadableFolders: Int {
        guard isContainer else { return 0 }
        let own = detail == DirectoryScanner.unreadableDetail ? 1 : 0
        return children.reduce(own) { $0 + $1.unreadableFolders }
    }
}
