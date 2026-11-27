import Foundation
import Observation
import Photos
import StorageCore

enum AppTab: Hashable {
    case overview, photos, folders, settings
}

/// Which tree an explorer shows.
enum ExplorerSource: Hashable {
    case photos
    case folder(UUID)
}

/// Progress of a running scan.
struct RunningScan: Equatable {
    var done: Int
    var total: Int?
    var bytes: Int64
    var current: String

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return Double(done) / Double(total)
    }
}

@MainActor
@Observable
final class AppModel {
    var settings = AppSettings() {
        didSet { if settings != oldValue { saveSettings(); if settings.photoGrouping != oldValue.photoGrouping { rebuildPhotoTree() } } }
    }
    var tab: AppTab = .overview
    var loaded = false

    // Device
    var disk: DiskUsage?
    var appSize: Int64 = 0

    // Photos
    var photoRecord: PhotoScanRecord?
    var photoTree: StorageNode?
    var photoSummary: PhotoSummary?
    var photoScan: RunningScan?
    var photoStatus: PHAuthorizationStatus = PhotoLibraryService.status
    private var photoFlag: CancelFlag?

    // Folders
    var folders: [FolderScanRecord] = []
    /// Scans in progress, by folder id (new folders appear here before the record exists).
    var folderScans: [UUID: (name: String, progress: RunningScan)] = [:]
    private var folderFlags: [UUID: CancelFlag] = [:]
    /// Folder to open when switching to the folders tab from the overview.
    var pendingFolder: UUID?

    // Feedback
    var toast: Toast?
    var errorMessage: String?
    private var toastTask: Task<Void, Never>?

    // MARK: - Storage

    private static var baseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MemoryAnalyzer", isDirectory: true)
    }

    private var settingsStore: JSONFileStore<AppSettings> { JSONFileStore(url: Self.baseURL.appendingPathComponent("settings.json")) }
    private var photoStore: JSONFileStore<PhotoScanRecord> { JSONFileStore(url: Self.baseURL.appendingPathComponent("photos.json"), compact: true) }
    private static var foldersDir: URL { baseURL.appendingPathComponent("folders", isDirectory: true) }
    private func folderStore(_ id: UUID) -> JSONFileStore<FolderScanRecord> {
        JSONFileStore(url: Self.foldersDir.appendingPathComponent("\(id.uuidString).json"), compact: true)
    }

    init() {
        if let s = try? settingsStore.load() { settings = s }
    }

    /// Loads the saved scans in the background, then measures the device.
    func load() async {
        guard !loaded else { return }
        let base = Self.baseURL
        let (record, folders) = await Task.detached(priority: .userInitiated) { () -> (PhotoScanRecord?, [FolderScanRecord]) in
            let photos = try? JSONFileStore<PhotoScanRecord>(url: base.appendingPathComponent("photos.json")).load()
            let dir = base.appendingPathComponent("folders", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let folders = files.filter { $0.pathExtension == "json" }
                .compactMap { try? JSONFileStore<FolderScanRecord>(url: $0).load() }
                .sorted { $0.root.size > $1.root.size }
            return (photos ?? nil, folders)
        }.value
        photoRecord = record
        self.folders = folders
        rebuildPhotoTree()
        loaded = true
        await refreshDevice()
    }

    func refreshDevice() async {
        disk = DeviceInfo.disk()
        photoStatus = PhotoLibraryService.status
        appSize = await Task.detached(priority: .utility) { DeviceInfo.appSandboxSize() }.value
    }

    private func saveSettings() {
        try? settingsStore.save(settings)
    }

    private func savePhotos() {
        guard let record = photoRecord else { try? photoStore.delete(); return }
        let store = photoStore
        Task.detached(priority: .utility) { try? store.save(record) }
    }

    private func saveFolder(_ record: FolderScanRecord) {
        let store = folderStore(record.id)
        Task.detached(priority: .utility) { try? store.save(record) }
    }

    // MARK: - Trees

    func root(for source: ExplorerSource) -> StorageNode? {
        switch source {
        case .photos: return photoTree
        case .folder(let id): return folders.first { $0.id == id }?.root
        }
    }

    func title(for source: ExplorerSource) -> String {
        switch source {
        case .photos: return "Foto e video"
        case .folder(let id): return folders.first { $0.id == id }?.name ?? "Cartella"
        }
    }

    func rescan(_ source: ExplorerSource) {
        switch source {
        case .photos: Task { await scanPhotos() }
        case .folder(let id): rescanFolder(id)
        }
    }

    private func rebuildPhotoTree() {
        guard let record = photoRecord else {
            photoTree = nil
            photoSummary = nil
            return
        }
        photoTree = PhotoTreeBuilder.build(record.items, grouping: settings.photoGrouping)
        photoSummary = PhotoSummary(record.items)
    }

    /// Map of the whole iPhone.
    var deviceTree: StorageNode? {
        guard let disk else { return nil }
        let local = folders.filter(\.isLocal).map { (id: $0.id.uuidString, name: $0.name, bytes: $0.root.allocated) }
        return DeviceMap.build(.init(disk: disk, photos: photoRecord.map { _ in photoSummary?.totalSize ?? 0 }, folders: local, app: appSize))
    }

    // MARK: - Photos

    func scanPhotos() async {
        guard photoScan == nil else { return }
        var status = PhotoLibraryService.status
        if status == .notDetermined { status = await PhotoLibraryService.requestAccess() }
        photoStatus = status
        guard status == .authorized || status == .limited else {
            errorMessage = "Per analizzare foto e video consenti l'accesso alla libreria in Impostazioni › Privacy e sicurezza › Foto."
            return
        }
        let flag = CancelFlag()
        photoFlag = flag
        photoScan = RunningScan(done: 0, total: nil, bytes: 0, current: "")
        let includeHidden = settings.includeHidden
        let start = Date()
        let items = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.scan(includeHidden: includeHidden, flag: flag) { done, total in
                Task { @MainActor [weak self] in
                    guard let self, self.photoScan != nil else { return }
                    self.photoScan = RunningScan(done: done, total: total, bytes: 0, current: "")
                }
            }
        }.value
        photoScan = nil
        photoFlag = nil
        guard let items else {
            showToast("Analisi annullata", icon: "xmark.circle.fill", style: .info)
            return
        }
        photoRecord = PhotoScanRecord(date: Date(), items: items, elapsed: Date().timeIntervalSince(start))
        rebuildPhotoTree()
        savePhotos()
        await refreshDevice()
        let total = Fmt.bytes(photoSummary?.totalSize ?? 0, units: settings.units)
        showToast("\(Fmt.plural(items.count, "elemento", "elementi")) · \(total)", icon: "checkmark.circle.fill", style: .success)
    }

    func cancelPhotoScan() {
        photoFlag?.cancel()
    }

    // MARK: - Folders

    /// Folder picked in Files: scan it and keep a bookmark for later.
    func addFolder(_ url: URL) {
        let id = UUID()
        FolderAccess.register(url, id: id)
        if let existing = folders.first(where: { (try? FolderAccess.url(for: $0))?.standardizedFileURL == url.standardizedFileURL }) {
            FolderAccess.forget(id)
            rescanFolder(existing.id)
            return
        }
        do {
            let bookmark = try FolderAccess.bookmark(for: url)
            let name = url.lastPathComponent.isEmpty ? "Cartella" : url.lastPathComponent
            runFolderScan(id: id, url: url, name: name, bookmark: bookmark)
        } catch {
            errorMessage = "Impossibile accedere alla cartella: \(error.localizedDescription)"
        }
    }

    func rescanFolder(_ id: UUID) {
        guard let record = folders.first(where: { $0.id == id }), folderScans[id] == nil else { return }
        do {
            let url = try FolderAccess.url(for: record)
            runFolderScan(id: id, url: url, name: record.name, bookmark: record.bookmark)
        } catch {
            errorMessage = "La cartella “\(record.name)” non è più raggiungibile. Rimuovila e aggiungila di nuovo."
        }
    }

    private func runFolderScan(id: UUID, url: URL, name: String, bookmark: Data) {
        let flag = CancelFlag()
        folderFlags[id] = flag
        folderScans[id] = (name, RunningScan(done: 0, total: nil, bytes: 0, current: ""))
        let start = Date()
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(StorageNode, Int), Error> in
                let scanner = DirectoryScanner(progress: { p in
                    Task { @MainActor [weak self] in
                        guard let self, self.folderScans[id] != nil else { return }
                        self.folderScans[id] = (name, RunningScan(done: p.files, total: nil, bytes: p.bytes, current: p.current))
                    }
                }, isCancelled: { flag.isCancelled }, lister: FolderLister.list)
                do {
                    let root = try scanner.scan(url, name: name)
                    return .success((root, scanner.lastProgress.unreadable))
                } catch {
                    return .failure(error)
                }
            }.value
            folderScans[id] = nil
            folderFlags[id] = nil
            switch result {
            case .success(let (root, unreadable)):
                let record = FolderScanRecord(
                    id: id, name: name, bookmark: bookmark, date: Date(), elapsed: Date().timeIntervalSince(start),
                    root: root, isLocal: FolderLocation.isLocal(path: url.path), unreadable: unreadable
                )
                if let i = folders.firstIndex(where: { $0.id == id }) {
                    folders[i] = record
                } else {
                    folders.append(record)
                }
                folders.sort { $0.root.size > $1.root.size }
                saveFolder(record)
                if unreadable > 0 {
                    showToast("\(name): \(Fmt.plural(unreadable, "cartella non leggibile", "cartelle non leggibili"))", icon: "exclamationmark.triangle.fill", style: .error)
                } else {
                    showToast("\(name): \(Fmt.bytes(root.size, units: settings.units))", icon: "checkmark.circle.fill", style: .success)
                }
            case .failure(let error):
                if !folders.contains(where: { $0.id == id }) { FolderAccess.forget(id) }
                if error is ScanCancelled {
                    showToast("Analisi annullata", icon: "xmark.circle.fill", style: .info)
                } else {
                    errorMessage = "Analisi di “\(name)” non riuscita: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancelFolderScan(_ id: UUID) {
        folderFlags[id]?.cancel()
    }

    func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        try? folderStore(id).delete()
        FolderAccess.forget(id)
    }

    // MARK: - Deleting

    /// Deletes leaves (photos or files) and updates the tree. Returns how many were removed.
    @discardableResult
    func delete(_ nodes: [StorageNode], from source: ExplorerSource) async -> Int {
        guard !nodes.isEmpty else { return 0 }
        switch source {
        case .photos:
            let ids = nodes.map { $0.ref ?? $0.id }
            do {
                guard try await PhotoLibraryService.delete(ids: ids) else { return 0 }
            } catch {
                errorMessage = "Eliminazione non riuscita: \(error.localizedDescription)"
                return 0
            }
            let set = Set(ids)
            photoRecord?.items.removeAll { set.contains($0.id) }
            rebuildPhotoTree()
            savePhotos()
            showToast(deletedMessage(nodes), icon: "trash.fill", style: .success)
            await refreshDevice()
            return ids.count
        case .folder(let id):
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return 0 }
            var record = folders[index]
            var removedIDs: Set<String> = []
            var failures: [String] = []
            for node in nodes {
                do {
                    let url = try FolderAccess.url(of: node, in: record)
                    try FileManager.default.removeItem(at: url)
                    removedIDs.insert(node.id)
                } catch {
                    failures.append(node.name)
                }
            }
            // Containers are removed by path, leaves by id.
            for node in nodes where removedIDs.contains(node.id) && node.isContainer {
                if let path = record.root.path(of: node.id) { record.root.remove(at: path) }
            }
            record.root.removeLeaves(ids: removedIDs)
            folders[index] = record
            saveFolder(record)
            if !failures.isEmpty {
                errorMessage = "Non è stato possibile eliminare: \(failures.prefix(5).joined(separator: ", "))"
            }
            if !removedIDs.isEmpty {
                showToast(deletedMessage(nodes.filter { removedIDs.contains($0.id) }), icon: "trash.fill", style: .success)
                await refreshDevice()
            }
            return removedIDs.count
        }
    }

    private func deletedMessage(_ nodes: [StorageNode]) -> String {
        let bytes = nodes.reduce(Int64(0)) { $0 + $1.size }
        return "Eliminati \(Fmt.plural(nodes.count, "elemento", "elementi")) · \(Fmt.bytes(bytes, units: settings.units)) liberati"
    }

    /// Forgets every saved scan (does not touch photos or files).
    func clearAllScans() {
        photoRecord = nil
        rebuildPhotoTree()
        try? photoStore.delete()
        for f in folders {
            try? folderStore(f.id).delete()
            FolderAccess.forget(f.id)
        }
        folders = []
        showToast("Analisi salvate eliminate", icon: "checkmark.circle.fill", style: .info)
        Task { await refreshDevice() }
    }

    // MARK: - Feedback

    func showToast(_ message: String, icon: String, style: Toast.Style) {
        toast = Toast(message: message, icon: icon, style: style)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func bytes(_ value: Int64) -> String {
        Fmt.bytes(value, units: settings.units)
    }
}
