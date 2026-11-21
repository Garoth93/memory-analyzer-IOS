import Foundation

public enum NodeKind: String, Codable, Sendable {
    /// Directory on disk.
    case folder
    /// Virtual group (year, month, media kind, device segment).
    case group
    /// Regular file on disk.
    case file
    /// Photo library asset.
    case asset
    /// Summary block of the device map (opens another screen when tapped).
    case segment
}

/// One block of the map: a file / asset (leaf) or a container whose size is
/// the sum of its children. Children are always sorted by size, biggest first.
public struct StorageNode: Codable, Equatable, Sendable, Identifiable {
    /// Unique inside its tree (relative path, asset identifier, "2024/03", …).
    public var id: String
    public var name: String
    public var kind: NodeKind
    /// Logical size in bytes (sum of the children for containers).
    public var size: Int64
    /// Bytes actually allocated on disk (iCloud placeholders are 0).
    public var allocated: Int64
    /// Leaves below this node (1 for a leaf).
    public var fileCount: Int
    /// Containers below this node, itself excluded.
    public var folderCount: Int
    /// Most recent modification / creation date below this node.
    public var modified: Date?
    /// Leaf: its category. Container: the category that weighs the most.
    public var category: FileCategory
    /// Lowercased extension of a leaf ("" for containers).
    public var ext: String
    /// Asset local identifier or path relative to the scanned folder.
    public var ref: String?
    /// Extra info for leaves (photo resolution "4032×3024", duration, …).
    public var detail: String?
    /// Container whose category was set explicitly (device segments): not recomputed.
    public var pinnedCategory: Bool
    public var children: [StorageNode]

    public var isContainer: Bool { kind == .folder || kind == .group }

    public init(
        id: String, name: String, kind: NodeKind, size: Int64 = 0, allocated: Int64? = nil,
        modified: Date? = nil, category: FileCategory? = nil, ext: String? = nil,
        ref: String? = nil, detail: String? = nil, children: [StorageNode] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = max(0, size)
        self.allocated = max(0, allocated ?? size)
        self.modified = modified
        self.ref = ref
        self.detail = detail
        self.children = children
        self.fileCount = 1
        self.folderCount = 0
        self.pinnedCategory = false
        if kind == .folder || kind == .group {
            self.ext = ""
            self.category = category ?? .folder
            self.pinnedCategory = category != nil
            self.recompute()
        } else {
            let e = ext ?? (kind == .segment ? "" : FileCategory.ext(of: name))
            self.ext = e
            self.category = category ?? FileCategory.classify(ext: e)
        }
    }

    /// Convenience for a leaf on disk.
    public static func file(id: String, name: String, size: Int64, allocated: Int64? = nil, modified: Date? = nil, ref: String? = nil) -> StorageNode {
        StorageNode(id: id, name: name, kind: .file, size: size, allocated: allocated, modified: modified, ref: ref ?? id)
    }

    /// Convenience for a container.
    public static func container(id: String, name: String, kind: NodeKind = .folder, category: FileCategory? = nil, ref: String? = nil, children: [StorageNode]) -> StorageNode {
        StorageNode(id: id, name: name, kind: kind, category: category, ref: ref, children: children)
    }

    // MARK: - Aggregates

    /// Recomputes size, counts, date and dominant category from the children
    /// and sorts them by size (biggest first, then by name).
    public mutating func recompute() {
        guard isContainer else { return }
        children.sort(by: StorageNode.order)
        var size: Int64 = 0, allocated: Int64 = 0, files = 0, folders = 0
        var latest: Date?
        var weights: [FileCategory: Int64] = [:]
        for c in children {
            size += c.size
            allocated += c.allocated
            files += c.isContainer ? c.fileCount : 1
            folders += c.isContainer ? c.folderCount + 1 : 0
            if let d = c.modified, latest.map({ d > $0 }) ?? true { latest = d }
            weights[c.category, default: 0] += max(c.size, 1)
        }
        self.size = size
        self.allocated = allocated
        self.fileCount = files
        self.folderCount = folders
        self.modified = latest
        if !pinnedCategory {
            let dominant = weights.filter { $0.key != .folder }.max { a, b in
                a.value == b.value ? a.key.rawValue > b.key.rawValue : a.value < b.value
            }
            self.category = dominant?.key ?? .folder
        }
    }

    static func order(_ a: StorageNode, _ b: StorageNode) -> Bool {
        if a.size != b.size { return a.size > b.size }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    // MARK: - Navigation

    /// Node at the index path (empty path = self).
    public func node(at path: [Int]) -> StorageNode? {
        var current = self
        for i in path {
            guard current.children.indices.contains(i) else { return nil }
            current = current.children[i]
        }
        return current
    }

    /// Nodes from self (excluded) down to the node at `path`.
    public func trail(_ path: [Int]) -> [StorageNode] {
        var out: [StorageNode] = []
        var current = self
        for i in path {
            guard current.children.indices.contains(i) else { break }
            current = current.children[i]
            out.append(current)
        }
        return out
    }

    /// Index path of the node with `id`, depth-first.
    public func path(of id: String) -> [Int]? {
        if self.id == id { return [] }
        for (i, c) in children.enumerated() {
            if let p = c.path(of: id) { return [i] + p }
        }
        return nil
    }

    /// Longest prefix of `path` that still points to a container in this tree.
    public func validContainerPath(_ path: [Int]) -> [Int] {
        var out: [Int] = []
        var current = self
        for i in path {
            guard current.children.indices.contains(i), current.children[i].isContainer else { break }
            current = current.children[i]
            out.append(i)
        }
        return out
    }

    /// Calls `body` for every leaf with its index path.
    public func forEachLeaf(_ prefix: [Int] = [], _ body: (StorageNode, [Int]) -> Void) {
        if !isContainer {
            body(self, prefix)
            return
        }
        for (i, c) in children.enumerated() { c.forEachLeaf(prefix + [i], body) }
    }

    /// All leaves (files / assets) below this node.
    public var leaves: [StorageNode] {
        var out: [StorageNode] = []
        forEachLeaf { n, _ in out.append(n) }
        return out
    }

    // MARK: - Editing

    /// Removes the node at `path` and updates every ancestor. Returns the removed node.
    @discardableResult
    public mutating func remove(at path: [Int]) -> StorageNode? {
        guard let first = path.first, children.indices.contains(first) else { return nil }
        let removed: StorageNode?
        if path.count == 1 {
            removed = children.remove(at: first)
        } else {
            removed = children[first].remove(at: Array(path.dropFirst()))
        }
        if removed != nil { recompute() }
        return removed
    }

    /// Removes every leaf whose id is in `ids`. Containers are kept even if empty.
    /// Returns the number of removed leaves.
    @discardableResult
    public mutating func removeLeaves(ids: Set<String>) -> Int {
        guard isContainer, !ids.isEmpty else { return 0 }
        var removed = 0
        var kept: [StorageNode] = []
        kept.reserveCapacity(children.count)
        for var c in children {
            if c.isContainer {
                removed += c.removeLeaves(ids: ids)
                kept.append(c)
            } else if ids.contains(c.id) {
                removed += 1
            } else {
                kept.append(c)
            }
        }
        if removed > 0 {
            children = kept
            recompute()
        }
        return removed
    }

    /// Share of this node in `total` (0…1).
    public func fraction(of total: Int64) -> Double {
        total > 0 ? Double(size) / Double(total) : 0
    }
}
