import Foundation

actor IndexDisk {
    private let url: URL
    private var lastSequence = -1

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("Shots/index.json")) {
        self.url = url
    }

    func load() throws -> IndexSnapshot? {
        try prepareDirectory()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let snapshot = try JSONDecoder().decode(IndexSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.version == 1 else { throw IndexError.newerVersion }
        return snapshot
    }

    func save(_ snapshot: IndexSnapshot, sequence: Int) throws {
        guard sequence > lastSequence else { return }
        try prepareDirectory()
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        lastSequence = sequence
    }

    private func prepareDirectory() throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    enum IndexError: LocalizedError {
        case newerVersion
        var errorDescription: String? { "This index needs a newer version of Shots." }
    }
}
