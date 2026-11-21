import Foundation

/// Capacity of the device volume (from URLResourceValues).
public struct DiskUsage: Codable, Equatable, Sendable {
    public var total: Int64
    /// "Available for important usage": what iOS Settings shows as free.
    public var available: Int64

    public init(total: Int64, available: Int64) {
        self.total = max(0, total)
        self.available = min(max(0, available), max(0, total))
    }

    public var used: Int64 { total - available }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    public var freeFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }
}

/// Builds the device-level map: free space, photo library, analysed folders
/// stored on the iPhone, this app and "everything else".
public enum DeviceMap {
    public static let rootID = "device"
    public static let photosID = "device/photos"
    public static let foldersID = "device/folders"
    public static let appID = "device/app"
    public static let systemID = "device/system"
    public static let freeID = "device/free"

    public struct Input: Sendable {
        public var disk: DiskUsage
        /// Bytes of the photo library actually on this iPhone (nil = not analysed).
        public var photos: Int64?
        /// Allocated bytes of the folders analysed on "Sul mio iPhone".
        public var folders: [(id: String, name: String, bytes: Int64)]
        /// This app's sandbox.
        public var app: Int64

        public init(disk: DiskUsage, photos: Int64? = nil, folders: [(id: String, name: String, bytes: Int64)] = [], app: Int64 = 0) {
            self.disk = disk
            self.photos = photos
            self.folders = folders
            self.app = app
        }
    }

    /// Known parts are clamped so that the sum never exceeds the used space;
    /// the remainder is "Sistema, app e altri dati".
    public static func build(_ input: Input) -> StorageNode {
        var budget = input.disk.used
        var used: [StorageNode] = []

        func take(_ bytes: Int64) -> Int64 {
            let v = min(max(0, bytes), budget)
            budget -= v
            return v
        }

        if let photos = input.photos {
            let v = take(photos)
            if v > 0 {
                used.append(StorageNode(id: photosID, name: "Foto e video", kind: .segment, size: v, category: .image))
            }
        }
        let folderLeaves: [StorageNode] = input.folders.enumerated().compactMap { i, f in
            let v = take(f.bytes)
            return v > 0 ? StorageNode(id: "\(foldersID)/\(i)", name: f.name, kind: .segment, size: v, category: .document, ref: f.id) : nil
        }
        if !folderLeaves.isEmpty {
            used.append(.container(id: foldersID, name: "Cartelle analizzate", kind: .group, category: .document, children: folderLeaves))
        }
        let app = take(input.app)
        if app > 0 {
            used.append(StorageNode(id: appID, name: "Questa app", kind: .segment, size: app, category: .app))
        }
        if budget > 0 {
            used.append(StorageNode(id: systemID, name: "Sistema, app e altri dati", kind: .segment, size: budget, category: .system))
        }
        var children = used
        if input.disk.available > 0 {
            children.append(StorageNode(id: freeID, name: "Spazio libero", kind: .segment, size: input.disk.available, category: .free))
        }
        return .container(id: rootID, name: "iPhone", kind: .group, category: .system, children: children)
    }
}
