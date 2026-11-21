import XCTest
@testable import StorageCore

final class TreemapTests: XCTestCase {
    private func assertFills(_ rects: [TMRect], values: [Double], in bounds: TMRect, file: StaticString = #filePath, line: UInt = #line) {
        let total = values.filter { $0 > 0 }.reduce(0, +)
        for (r, v) in zip(rects, values) {
            if v <= 0 {
                XCTAssertEqual(r, .zero, file: file, line: line)
                continue
            }
            XCTAssertEqual(r.area, bounds.area * v / total, accuracy: bounds.area * 1e-6, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.x, bounds.x - 1e-6, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.y, bounds.y - 1e-6, file: file, line: line)
            XCTAssertLessThanOrEqual(r.maxX, bounds.maxX + 1e-6, file: file, line: line)
            XCTAssertLessThanOrEqual(r.maxY, bounds.maxY + 1e-6, file: file, line: line)
        }
        // No overlaps.
        for i in rects.indices {
            for j in rects.indices where j > i {
                let a = rects[i], b = rects[j]
                let ox = min(a.maxX, b.maxX) - max(a.x, b.x)
                let oy = min(a.maxY, b.maxY) - max(a.y, b.y)
                XCTAssertFalse(ox > 1e-6 && oy > 1e-6, "rect \(i) overlaps \(j)", file: file, line: line)
            }
        }
    }

    func testClassicExampleFromThePaper() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let bounds = TMRect(x: 0, y: 0, w: 6, h: 4)
        let rects = Treemap.squarify(values, in: bounds)
        assertFills(rects, values: values, in: bounds)
        // First row: the two 6s stacked in a 3-wide column on the left.
        XCTAssertEqual(rects[0], TMRect(x: 0, y: 0, w: 3, h: 2))
        XCTAssertEqual(rects[1].x, 0, accuracy: 1e-9)
        XCTAssertEqual(rects[1].y, 2, accuracy: 1e-9)
        XCTAssertLessThan(rects.map(\.aspect).max()!, 3)
    }

    func testUnsortedInputKeepsOrderAndZeros() {
        let values: [Double] = [1, 0, 10, 5, -3]
        let bounds = TMRect(x: 10, y: 20, w: 300, h: 200)
        let rects = Treemap.squarify(values, in: bounds)
        XCTAssertEqual(rects.count, 5)
        assertFills(rects, values: values, in: bounds)
        XCTAssertGreaterThan(rects[2].area, rects[3].area)
    }

    func testManyValuesFillExactly() {
        let values = (1...200).map { Double($0 * $0 % 97 + 1) }
        let bounds = TMRect(x: 0, y: 0, w: 390, h: 420)
        let rects = Treemap.squarify(values, in: bounds)
        assertFills(rects, values: values, in: bounds)
        XCTAssertEqual(rects.map(\.area).reduce(0, +), bounds.area, accuracy: 1e-3)
    }

    func testEmptyAndDegenerate() {
        XCTAssertEqual(Treemap.squarify([], in: TMRect(x: 0, y: 0, w: 10, h: 10)), [])
        XCTAssertEqual(Treemap.squarify([1, 2], in: TMRect(x: 0, y: 0, w: 0, h: 10)), [.zero, .zero])
        XCTAssertEqual(Treemap.squarify([5], in: TMRect(x: 1, y: 2, w: 10, h: 20)), [TMRect(x: 1, y: 2, w: 10, h: 20)])
    }

    private func sampleTree() -> StorageNode {
        .container(id: "/", name: "root", children: [
            .container(id: "a", name: "a", children: [
                .file(id: "a/x.mov", name: "x.mov", size: 600),
                .file(id: "a/y.jpg", name: "y.jpg", size: 200),
                .container(id: "a/deep", name: "deep", children: [.file(id: "a/deep/z.zip", name: "z.zip", size: 100)])
            ]),
            .file(id: "b.pdf", name: "b.pdf", size: 300),
            .file(id: "tiny", name: "tiny", size: 0)
        ])
    }

    func testLayoutNestsChildrenInsideParents() {
        let tree = sampleTree()
        let bounds = TMRect(x: 0, y: 0, w: 400, h: 400)
        let tiles = TreemapLayout.tiles(for: tree, in: bounds, options: TreemapOptions(maxDepth: 3))
        let top = tiles.filter { $0.depth == 1 }
        XCTAssertEqual(top.map(\.name), ["a", "b.pdf"])
        let a = top[0]
        XCTAssertTrue(a.hasNestedTiles)
        XCTAssertNotNil(a.header)
        for t in tiles where t.depth > 1 {
            XCTAssertEqual(t.path.first, 0)
            XCTAssertTrue(t.rect.x >= a.rect.x && t.rect.maxX <= a.rect.maxX + 1e-6)
            XCTAssertTrue(t.rect.y >= a.rect.y && t.rect.maxY <= a.rect.maxY + 1e-6)
        }
        XCTAssertTrue(tiles.contains { $0.name == "z.zip" && $0.depth == 3 && $0.path == [0, 2, 0] })
        // Parents come before their children in drawing order.
        let ia = tiles.firstIndex { $0.id == "a" }!
        let ix = tiles.firstIndex { $0.id == "a/x.mov" }!
        XCTAssertLessThan(ia, ix)
    }

    func testDepthLimitAndHitTesting() {
        let tree = sampleTree()
        let bounds = TMRect(x: 0, y: 0, w: 400, h: 400)
        let tiles = TreemapLayout.tiles(for: tree, in: bounds, options: TreemapOptions(maxDepth: 1))
        XCTAssertEqual(tiles.count, 2)
        XCTAssertFalse(tiles[0].hasNestedTiles)

        let deep = TreemapLayout.tiles(for: tree, in: bounds, options: TreemapOptions(maxDepth: 3))
        let x = deep.first { $0.id == "a/x.mov" }!
        let hit = TreemapLayout.hit(deep, x: x.rect.midX, y: x.rect.midY)
        XCTAssertEqual(hit?.id, "a/x.mov")
        XCTAssertEqual(TreemapLayout.hitTop(deep, x: x.rect.midX, y: x.rect.midY)?.id, "a")
        XCTAssertNil(TreemapLayout.hit(deep, x: -5, y: -5))
    }

    func testTileIsLeaf() {
        let tree = DeviceMap.build(.init(disk: DiskUsage(total: 100, available: 40), photos: 20))
        let tiles = TreemapLayout.tiles(for: tree, in: TMRect(x: 0, y: 0, w: 100, h: 100))
        XCTAssertTrue(tiles.allSatisfy(\.isLeaf))
    }
}
