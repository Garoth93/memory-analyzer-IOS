import Foundation

/// One row of the "Tipi" view (WizTree's extension list).
public struct ExtensionStat: Equatable, Sendable, Identifiable {
    public var ext: String
    public var category: FileCategory
    public var size: Int64
    public var allocated: Int64
    public var count: Int

    public var id: String { ext.isEmpty ? "·" : ext }
    public var label: String { ext.isEmpty ? "(nessuna)" : "." + ext }
    public var description: String { FileCategory.describe(ext: ext, category: category) }
}

/// Totals per category.
public struct CategoryStat: Equatable, Sendable, Identifiable {
    public var category: FileCategory
    public var size: Int64
    public var count: Int
    public var id: FileCategory { category }

    public init(category: FileCategory, size: Int64, count: Int) {
        self.category = category
        self.size = size
        self.count = count
    }
}

/// A leaf with where it lives (for "Più grandi" and duplicates).
public struct LeafRef: Equatable, Sendable, Identifiable {
    public var node: StorageNode
    /// Index path from the root used for the analysis.
    public var path: [Int]
    /// Names of the containers between the root (excluded) and the leaf.
    public var location: String
    public var id: String { node.id }
}

/// Leaves that look like copies of each other.
public struct DuplicateGroup: Equatable, Sendable, Identifiable {
    public var key: String
    public var items: [LeafRef]
    public var id: String { key }
    public var size: Int64 { items.first?.node.size ?? 0 }
    /// Bytes freed keeping only one copy.
    public var reclaimable: Int64 { size * Int64(max(0, items.count - 1)) }
}

public enum Analysis {
    /// Extension statistics below `node`, biggest first.
    public static func extensions(_ node: StorageNode) -> [ExtensionStat] {
        var map: [String: ExtensionStat] = [:]
        node.forEachLeaf { leaf, _ in
            var s = map[leaf.ext] ?? ExtensionStat(ext: leaf.ext, category: leaf.category, size: 0, allocated: 0, count: 0)
            s.size += leaf.size
            s.allocated += leaf.allocated
            s.count += 1
            map[leaf.ext] = s
        }
        return map.values.sorted { $0.size != $1.size ? $0.size > $1.size : $0.ext < $1.ext }
    }

    /// Category totals below `node`, biggest first.
    public static func categories(_ node: StorageNode) -> [CategoryStat] {
        var map: [FileCategory: CategoryStat] = [:]
        node.forEachLeaf { leaf, _ in
            var s = map[leaf.category] ?? CategoryStat(category: leaf.category, size: 0, count: 0)
            s.size += leaf.size
            s.count += 1
            map[leaf.category] = s
        }
        return map.values.sorted { $0.size != $1.size ? $0.size > $1.size : $0.category.rawValue < $1.category.rawValue }
    }

    /// The `limit` biggest leaves below `node`.
    public static func largest(_ node: StorageNode, limit: Int = 100) -> [LeafRef] {
        var all: [(StorageNode, [Int])] = []
        node.forEachLeaf { leaf, path in all.append((leaf, path)) }
        all.sort { $0.0.size != $1.0.size ? $0.0.size > $1.0.size : $0.0.name < $1.0.name }
        return all.prefix(max(0, limit)).map { ref(root: node, leaf: $0.0, path: $0.1) }
    }

    /// Probable duplicates: same size and same name (files) or same size and
    /// resolution (photo assets). Only leaves of at least `minSize` bytes.
    public static func duplicates(_ node: StorageNode, minSize: Int64 = 100_000) -> [DuplicateGroup] {
        var buckets: [String: [(StorageNode, [Int])]] = [:]
        node.forEachLeaf { leaf, path in
            guard leaf.size >= minSize else { return }
            buckets[duplicateKey(leaf), default: []].append((leaf, path))
        }
        return buckets.compactMap { key, list -> DuplicateGroup? in
            guard list.count > 1 else { return nil }
            let items = list
                .sorted { ($0.0.modified ?? .distantFuture) < ($1.0.modified ?? .distantFuture) }
                .map { ref(root: node, leaf: $0.0, path: $0.1) }
            return DuplicateGroup(key: key, items: items)
        }
        .sorted { $0.reclaimable != $1.reclaimable ? $0.reclaimable > $1.reclaimable : $0.key < $1.key }
    }

    static func duplicateKey(_ leaf: StorageNode) -> String {
        if leaf.kind == .asset {
            return "a|\(leaf.size)|\(leaf.detail ?? "")|\(leaf.ext)"
        }
        return "f|\(leaf.size)|\(leaf.name.lowercased())"
    }

    static func ref(root: StorageNode, leaf: StorageNode, path: [Int]) -> LeafRef {
        let names = root.trail(Array(path.dropLast())).map(\.name)
        return LeafRef(node: leaf, path: path, location: names.joined(separator: " › "))
    }
}
