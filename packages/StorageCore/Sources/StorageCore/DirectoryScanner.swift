import Foundation

public struct ScanProgress: Equatable, Sendable {
    public var files: Int
    public var folders: Int
    public var bytes: Int64
    /// Path (relative to the root) of the folder being read.
    public var current: String

    public init(files: Int = 0, folders: Int = 0, bytes: Int64 = 0, current: String = "") {
        self.files = files
        self.folders = folders
        self.bytes = bytes
        self.current = current
    }
}

public struct ScanCancelled: Error, Equatable {
    public init() {}
}

/// Recursive folder scan with FileManager (works on iOS and Linux).
/// Symbolic links are not followed; unreadable folders become empty nodes.
public final class DirectoryScanner {
    private let fm = FileManager.default
    private let progress: ((ScanProgress) -> Void)?
    private let isCancelled: () -> Bool
    private var state = ScanProgress()
    private var lastReport = 0

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey
    ]

    public init(progress: ((ScanProgress) -> Void)? = nil, isCancelled: @escaping () -> Bool = { false }) {
        self.progress = progress
        self.isCancelled = isCancelled
    }

    /// Scans `url`; the root node is named `name` (default: the folder name).
    public func scan(_ url: URL, name: String? = nil) throws -> StorageNode {
        state = ScanProgress()
        var root = try folder(url, relative: "")
        root.name = name ?? url.lastPathComponent
        progress?(state)
        return root
    }

    private func folder(_ url: URL, relative: String) throws -> StorageNode {
        if isCancelled() { throw ScanCancelled() }
        state.folders += 1
        state.current = relative
        let entries = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: [])) ?? []
        var children: [StorageNode] = []
        children.reserveCapacity(entries.count)
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(Self.keys))
            if values?.isSymbolicLink == true { continue }
            let name = entry.lastPathComponent
            let rel = relative.isEmpty ? name : relative + "/" + name
            if values?.isDirectory == true {
                children.append(try folder(entry, relative: rel))
            } else {
                let size = Int64(values?.fileSize ?? 0)
                let allocated = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
                children.append(.file(id: rel, name: name, size: size, allocated: allocated, modified: values?.contentModificationDate, ref: rel))
                state.files += 1
                state.bytes += size
                if state.files - lastReport >= 250 {
                    lastReport = state.files
                    if isCancelled() { throw ScanCancelled() }
                    progress?(state)
                }
            }
        }
        let display = relative.isEmpty ? url.lastPathComponent : (relative.split(separator: "/").last.map(String.init) ?? relative)
        return .container(id: relative.isEmpty ? "/" : relative, name: display, kind: .folder, ref: relative, children: children)
    }
}
