import XCTest
@testable import StorageCore

final class AnalysisTests: XCTestCase {
    private func tree() -> StorageNode {
        .container(id: "/", name: "root", children: [
            .container(id: "A", name: "A", children: [
                .file(id: "A/movie.mp4", name: "movie.mp4", size: 5_000_000, modified: Date(timeIntervalSince1970: 10)),
                .file(id: "A/song.mp3", name: "song.mp3", size: 300_000)
            ]),
            .container(id: "B", name: "B", children: [
                .file(id: "B/movie.mp4", name: "movie.mp4", size: 5_000_000, modified: Date(timeIntervalSince1970: 5)),
                .file(id: "B/clip.MP4", name: "clip.MP4", size: 1_000_000),
                .file(id: "B/small.txt", name: "small.txt", size: 10)
            ]),
            .file(id: "song.mp3", name: "SONG.mp3", size: 300_000)
        ])
    }

    func testExtensions() {
        let stats = Analysis.extensions(tree())
        XCTAssertEqual(stats.map(\.ext), ["mp4", "mp3", "txt"])
        XCTAssertEqual(stats[0].count, 3)
        XCTAssertEqual(stats[0].size, 11_000_000)
        XCTAssertEqual(stats[0].label, ".mp4")
        XCTAssertEqual(stats[0].description, "Video MP4")
    }

    func testCategories() {
        let cats = Analysis.categories(tree())
        XCTAssertEqual(cats.first?.category, .video)
        XCTAssertEqual(cats.map(\.count).reduce(0, +), 6)
    }

    func testLargest() {
        let top = Analysis.largest(tree(), limit: 3)
        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top.map(\.node.size), [5_000_000, 5_000_000, 1_000_000])
        XCTAssertEqual(top[2].location, "B")
        XCTAssertEqual(tree().node(at: top[2].path)?.id, "B/clip.MP4")
        XCTAssertEqual(Analysis.largest(tree(), limit: 0).count, 0)
    }

    func testDuplicates() {
        let groups = Analysis.duplicates(tree(), minSize: 100_000)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertEqual(groups[0].reclaimable, 5_000_000)
        // Oldest copy first.
        XCTAssertEqual(groups[0].items.first?.node.id, "B/movie.mp4")
        // Names compared case-insensitively.
        XCTAssertEqual(groups[1].items.count, 2)
        XCTAssertTrue(Analysis.duplicates(tree(), minSize: 10_000_000).isEmpty)
    }

    func testPhotoDuplicatesUseResolution() {
        let items = [
            PhotoItem(id: "1", filename: "IMG_1.HEIC", kind: .photo, date: nil, size: 2_000_000, pixelWidth: 4032, pixelHeight: 3024),
            PhotoItem(id: "2", filename: "IMG_1.HEIC", kind: .photo, date: nil, size: 2_000_000, pixelWidth: 4032, pixelHeight: 3024),
            PhotoItem(id: "3", filename: "IMG_2.HEIC", kind: .photo, date: nil, size: 2_000_000, pixelWidth: 3024, pixelHeight: 4032)
        ]
        let tree = PhotoTreeBuilder.build(items, grouping: .date)
        let groups = Analysis.duplicates(tree)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].items.map(\.id)), ["1", "2"])
    }
}
