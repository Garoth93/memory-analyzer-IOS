import XCTest
@testable import StorageCore

final class StorageNodeTests: XCTestCase {
    private let d1 = Date(timeIntervalSince1970: 1_000)
    private let d2 = Date(timeIntervalSince1970: 2_000)

    private func tree() -> StorageNode {
        .container(id: "/", name: "C:", children: [
            .container(id: "Users", name: "Users", children: [
                .file(id: "Users/a.mp4", name: "a.mp4", size: 500, allocated: 512, modified: d1),
                .file(id: "Users/b.jpg", name: "b.jpg", size: 100, allocated: 128, modified: d2),
                .container(id: "Users/empty", name: "empty", children: [])
            ]),
            .file(id: "hiberfil.sys", name: "hiberfil.sys", size: 800),
            .file(id: "notes.txt", name: "notes.txt", size: 10)
        ])
    }

    func testAggregatesAndSorting() {
        let t = tree()
        XCTAssertEqual(t.size, 1410)
        XCTAssertEqual(t.allocated, 512 + 128 + 800 + 10)
        XCTAssertEqual(t.fileCount, 4)
        XCTAssertEqual(t.folderCount, 2)
        XCTAssertEqual(t.modified, d2)
        XCTAssertEqual(t.children.map(\.name), ["hiberfil.sys", "Users", "notes.txt"])
        let users = t.children[1]
        XCTAssertEqual(users.category, .video)
        XCTAssertEqual(users.children.last?.name, "empty")
        XCTAssertEqual(users.children.last?.fileCount, 0)
        XCTAssertEqual(t.children[0].ext, "sys")
        XCTAssertEqual(t.children[0].category, .other)
        XCTAssertEqual(t.children[2].category, .document)
    }

    func testNavigation() {
        let t = tree()
        XCTAssertEqual(t.node(at: [1, 0])?.name, "a.mp4")
        XCTAssertNil(t.node(at: [7]))
        XCTAssertEqual(t.trail([1, 1]).map(\.name), ["Users", "b.jpg"])
        XCTAssertEqual(t.path(of: "Users/b.jpg"), [1, 1])
        XCTAssertNil(t.path(of: "missing"))
        XCTAssertEqual(t.validContainerPath([1, 0]), [1])
        XCTAssertEqual(t.validContainerPath([9]), [])
        XCTAssertEqual(t.leaves.count, 4)
        var paths: [[Int]] = []
        t.forEachLeaf { _, p in paths.append(p) }
        XCTAssertEqual(paths, [[0], [1, 0], [1, 1], [2]])
    }

    func testRemoveUpdatesAncestors() {
        var t = tree()
        let removed = t.remove(at: [1, 0])
        XCTAssertEqual(removed?.name, "a.mp4")
        XCTAssertEqual(t.size, 910)
        XCTAssertEqual(t.fileCount, 3)
        let users = t.children.first { $0.name == "Users" }!
        XCTAssertEqual(users.size, 100)
        XCTAssertEqual(users.category, .image)
        XCTAssertNil(t.remove(at: [42]))
    }

    func testRemoveLeavesByID() {
        var t = tree()
        XCTAssertEqual(t.removeLeaves(ids: ["Users/b.jpg", "notes.txt", "nope"]), 2)
        XCTAssertEqual(t.size, 1300)
        XCTAssertEqual(t.fileCount, 2)
        XCTAssertEqual(t.removeLeaves(ids: []), 0)
    }

    func testPinnedCategoryIsKept() {
        var g = StorageNode.container(id: "g", name: "g", kind: .group, category: .document, children: [
            .file(id: "v.mov", name: "v.mov", size: 10), .file(id: "d.pdf", name: "d.pdf", size: 1)
        ])
        XCTAssertEqual(g.category, .document)
        g.remove(at: [1])
        XCTAssertEqual(g.category, .document)
    }

    func testCodableRoundTrip() throws {
        let t = tree()
        let data = try JSONFileStore<StorageNode>.encoder.encode(t)
        let back = try JSONFileStore<StorageNode>.decoder.decode(StorageNode.self, from: data)
        XCTAssertEqual(back, t)
    }

    func testFraction() {
        let t = tree()
        XCTAssertEqual(t.children[0].fraction(of: t.size), 800.0 / 1410.0, accuracy: 1e-9)
        XCTAssertEqual(t.fraction(of: 0), 0)
    }
}
