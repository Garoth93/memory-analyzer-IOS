import Foundation
import StorageCore

/// Security-scoped access to the folders chosen in Files.
@MainActor
enum FolderAccess {
    /// Folders opened in this session (access stays active until the app quits,
    /// so previews, sharing and deletion work while browsing).
    private static var opened: [UUID: URL] = [:]

    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves the bookmark of a scan and starts accessing the folder.
    static func url(for record: FolderScanRecord) throws -> URL {
        if let url = opened[record.id] { return url }
        var stale = false
        let url = try URL(resolvingBookmarkData: record.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        _ = url.startAccessingSecurityScopedResource()
        opened[record.id] = url
        return url
    }

    /// Keeps access to a folder just picked with the file importer.
    static func register(_ url: URL, id: UUID) {
        _ = url.startAccessingSecurityScopedResource()
        opened[id] = url
    }

    static func forget(_ id: UUID) {
        opened.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
    }

    /// URL of a node inside the scanned folder.
    static func url(of node: StorageNode, in record: FolderScanRecord) throws -> URL {
        let root = try url(for: record)
        guard let ref = node.ref, !ref.isEmpty else { return root }
        return root.appendingPathComponent(ref)
    }
}

/// Folder listing for the scanner. Folders served by a File Provider
/// (iCloud Drive, "Sul mio iPhone", Drive, OneDrive…) can be "dataless" until
/// someone reads them through file coordination: when the direct listing
/// fails or comes back empty, list again inside an NSFileCoordinator read.
enum FolderLister {
    static func list(_ url: URL) throws -> [URL] {
        var firstError: Error?
        do {
            let direct = try DirectoryScanner.defaultLister(url)
            if !direct.isEmpty { return direct }
        } catch {
            firstError = error
        }
        var result: [URL]?
        var innerError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                // Keep the original path so the children stay under the security scope.
                let names = try FileManager.default.contentsOfDirectory(atPath: readURL.path)
                result = names.map { url.appendingPathComponent($0) }
            } catch {
                innerError = error
            }
        }
        if let result { return result }
        throw innerError ?? coordinationError ?? firstError ?? CocoaError(.fileReadUnknown)
    }
}

enum DeviceInfo {
    /// Capacity of the iPhone volume, like Settings › General › iPhone Storage.
    static func disk() -> DiskUsage? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]),
              let total = v.volumeTotalCapacity else { return nil }
        let available = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        return DiskUsage(total: Int64(total), available: available)
    }

    /// Bytes used by this app's own sandbox (documents, caches, saved scans).
    static func appSandboxSize() -> Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return (try? DirectoryScanner().scan(home))?.allocated ?? 0
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
