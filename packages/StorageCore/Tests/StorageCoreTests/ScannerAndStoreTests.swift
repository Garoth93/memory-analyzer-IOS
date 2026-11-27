import XCTest
@testable import StorageCore

final class ScannerAndStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ rel: String, bytes: Int) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    func testScanBuildsTree() throws {
        try write("Videos/trip.mov", bytes: 50_000)
        try write("Videos/old/a.mp4", bytes: 20_000)
        try write("Docs/cv.pdf", bytes: 3_000)
        try write("readme", bytes: 10)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Empty"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"), withDestinationURL: dir.appendingPathComponent("Videos"))

        var reports: [ScanProgress] = []
        let root = try DirectoryScanner(progress: { reports.append($0) }).scan(dir, name: "Test")
        XCTAssertEqual(root.name, "Test")
        XCTAssertEqual(root.id, "/")
        XCTAssertEqual(root.size, 73_010)
        XCTAssertEqual(root.fileCount, 4)
        XCTAssertEqual(root.folderCount, 4)
        XCTAssertEqual(root.children.map(\.name), ["Videos", "Docs", "readme", "Empty"])
        let videos = root.children[0]
        XCTAssertEqual(videos.category, .video)
        XCTAssertEqual(videos.id, "Videos")
        XCTAssertEqual(videos.children.first?.id, "Videos/trip.mov")
        XCTAssertEqual(videos.children.first?.ref, "Videos/trip.mov")
        XCTAssertEqual(videos.children[1].id, "Videos/old")
        XCTAssertEqual(videos.children[1].name, "old")
        XCTAssertGreaterThanOrEqual(videos.children.first!.allocated, 0)
        XCTAssertNotNil(videos.children.first?.modified)
        XCTAssertEqual(reports.last?.files, 4)
        XCTAssertEqual(reports.last?.bytes, 73_010)
    }

    func testUnlistableSubfolderIsMarked() throws {
        try write("ok/a.txt", bytes: 5)
        try write("locked/b.txt", bytes: 7)
        let locked = dir.appendingPathComponent("locked").standardizedFileURL.path
        let scanner = DirectoryScanner(lister: { url in
            if url.standardizedFileURL.path == locked { throw CocoaError(.fileReadNoPermission) }
            return try DirectoryScanner.defaultLister(url)
        })
        let root = try scanner.scan(dir)
        XCTAssertEqual(root.size, 5)
        let node = root.children.first { $0.name == "locked" }!
        XCTAssertTrue(node.isContainer)
        XCTAssertEqual(node.detail, DirectoryScanner.unreadableDetail)
        XCTAssertEqual(root.unreadableFolders, 1)
        XCTAssertEqual(scanner.lastProgress.unreadable, 1)
        XCTAssertEqual(scanner.lastProgress.folders, 3)
    }

    func testUnlistableRootThrows() {
        let scanner = DirectoryScanner(lister: { _ in throw CocoaError(.fileReadNoPermission) })
        XCTAssertThrowsError(try scanner.scan(dir)) { error in
            XCTAssertTrue(error is FolderUnreadable)
            XCTAssertNotNil((error as? FolderUnreadable)?.errorDescription)
        }
    }

    func testEntryInfoFallsBackToAttributes() throws {
        try write("d/f.bin", bytes: 1234)
        let scanner = DirectoryScanner()
        let folder = scanner.info(dir.appendingPathComponent("d"))
        XCTAssertTrue(folder.isDirectory)
        let file = scanner.info(dir.appendingPathComponent("d/f.bin"))
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.size, 1234)
        XCTAssertEqual(DirectoryScanner.int64(NSNumber(value: 42)), 42)
        XCTAssertEqual(DirectoryScanner.int64(UInt64(7)), 7)
        XCTAssertNil(DirectoryScanner.int64("x"))
    }

    func testDeepRecursion() throws {
        try write("a/b/c/d/e/f/g/h/deep.mov", bytes: 99)
        let root = try DirectoryScanner().scan(dir)
        XCTAssertEqual(root.size, 99)
        XCTAssertEqual(root.folderCount, 8)
        XCTAssertEqual(root.node(at: [0, 0, 0, 0, 0, 0, 0, 0, 0])?.name, "deep.mov")
        XCTAssertEqual(root.children[0].category, .video)
    }

    func testOldFolderRecordDecodesWithoutUnreadable() throws {
        let tree = StorageNode.container(id: "/", name: "x", children: [])
        let record = FolderScanRecord(name: "A", bookmark: Data(), date: Date(timeIntervalSince1970: 0), elapsed: 0, root: tree, isLocal: true)
        var json = try JSONSerialization.jsonObject(with: JSONFileStore<FolderScanRecord>.encoder.encode(record)) as! [String: Any]
        json.removeValue(forKey: "unreadable")
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONFileStore<FolderScanRecord>.decoder.decode(FolderScanRecord.self, from: data).unreadable)
    }

    func testScanCanBeCancelled() throws {
        try write("a/b.txt", bytes: 1)
        XCTAssertThrowsError(try DirectoryScanner(isCancelled: { true }).scan(dir)) { error in
            XCTAssertTrue(error is ScanCancelled)
        }
    }

    func testStoresRoundTrip() throws {
        let tree = StorageNode.container(id: "/", name: "x", children: [.file(id: "a", name: "a.jpg", size: 5)])
        let record = FolderScanRecord(name: "Download", bookmark: Data([1, 2, 3]), date: Date(timeIntervalSince1970: 1000), elapsed: 1.5, root: tree, isLocal: true)
        let store = JSONFileStore<FolderScanRecord>(url: dir.appendingPathComponent("sub/f.json"), compact: true)
        XCTAssertNil(try store.load())
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
        try store.delete()
        XCTAssertNil(try store.load())

        let photos = PhotoScanRecord(date: Date(timeIntervalSince1970: 5), items: [PhotoItem(id: "1", filename: "a.heic", kind: .photo, date: nil, size: 3)], elapsed: 2)
        let pstore = JSONFileStore<PhotoScanRecord>(url: dir.appendingPathComponent("p.json"))
        try pstore.save(photos)
        XCTAssertEqual(try pstore.load(), photos)
    }

    func testSettingsDecodingIsLenient() throws {
        let json = #"{"seed":"not-a-color","depth":9,"units":"binary","colorMode":"bogus","cushion":false}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.seed, Palette.defaultAccent)
        XCTAssertEqual(s.depth, 4)
        XCTAssertEqual(s.units, .binary)
        XCTAssertEqual(s.colorMode, .type)
        XCTAssertFalse(s.cushion)
        XCTAssertTrue(s.labels)
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, AppSettings())
        let encoded = try JSONEncoder().encode(AppSettings(depth: 2))
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoded).depth, 2)
    }

    func testFolderLocation() {
        XCTAssertTrue(FolderLocation.isLocal(path: "/private/var/mobile/Containers/Shared/AppGroup/X/File Provider Storage/Download"))
        XCTAssertFalse(FolderLocation.isLocal(path: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Foto"))
        XCTAssertTrue(FolderLocation.isLocal(path: "/var/mobile/Containers/Data/Application/X/Documents"))
    }
}
