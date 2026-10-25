import Foundation
import os

/// Where the people store keeps its files. Default root is the app's Documents directory; tests pass a temp dir.
struct MemoryPaths: Equatable {
    let root: URL

    init(root: URL) { self.root = root }

    static var documents: MemoryPaths {
        MemoryPaths(root: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
    }
    static func temporary(_ name: String = UUID().uuidString) -> MemoryPaths {
        MemoryPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("familiar-\(name)", isDirectory: true))
    }

    var peopleJSON: URL { root.appendingPathComponent("people.json") }
    var thumbsDir: URL { root.appendingPathComponent("thumbs", isDirectory: true) }
    var consentsDir: URL { root.appendingPathComponent("consents", isDirectory: true) }
    func thumbnailURL(for id: UUID) -> URL { thumbsDir.appendingPathComponent("\(id.uuidString).jpg") }
    func consentClipURL(for id: UUID) -> URL { consentsDir.appendingPathComponent("\(id.uuidString).wav") }
    /// `Person.thumbnailPath` is stored relative to `root` so the record survives a container move.
    func relativeThumbnailPath(for id: UUID) -> String { "thumbs/\(id.uuidString).jpg" }
    func resolve(thumbnailPath: String) -> URL {
        thumbnailPath.hasPrefix("/") ? URL(fileURLWithPath: thumbnailPath) : root.appendingPathComponent(thumbnailPath)
    }

    func ensureDirectories() throws {
        for dir in [root, thumbsDir, consentsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// The real `PeopleStore`: `Documents/people.json` plus `thumbs/<id>.jpg` and `consents/<id>.wav`, written atomically.
/// `gallery()` is a lock-protected snapshot rebuilt on every change; `changes()` fans out through an `EventBus`.
@MainActor
final class JSONPeopleStore: PeopleStore {
    let paths: MemoryPaths
    /// The active embedder's model id. Only embeddings with this id go into the gallery. S5 sets it from the embedder.
    var modelID: String { didSet { if modelID != oldValue { rebuildGallery() } } }
    private(set) var people: [Person] = []
    private let contacts: ContactsBridge?
    private let bus = EventBus<Void>()
    private let galleryLock: OSAllocatedUnfairLock<Gallery>
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init(paths: MemoryPaths = .documents, modelID: String = "w600k_mbf", contacts: ContactsBridge? = nil) {
        self.paths = paths
        self.modelID = modelID
        self.contacts = contacts
        self.galleryLock = OSAllocatedUnfairLock(initialState: Gallery(modelID: modelID, people: []))
        try? paths.ensureDirectories()
        load()
    }

    // MARK: PeopleStore

    nonisolated func gallery() -> Gallery { galleryLock.withLock { $0 } }
    func all() -> [Person] { people }
    func changes() -> AsyncStream<Void> { bus.subscribe() }

    func find(name: String) -> Person? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return people.first { $0.name.lowercased() == needle } ?? people.first { $0.name.lowercased().hasPrefix(needle) }
    }

    /// Upsert by id. Writes `people.json` atomically.
    func add(_ p: Person) throws {
        people.removeAll { $0.id == p.id }
        people.append(p)
        try persist()
        rebuildGallery()
    }

    /// Removes the row, the thumbnail, the consent clip and (asynchronously) the iOS contact the app created.
    func remove(id: UUID) throws {
        guard let idx = people.firstIndex(where: { $0.id == id }) else { return }
        let person = people.remove(at: idx)
        try persist()
        let fm = FileManager.default
        for url in [paths.thumbnailURL(for: id), paths.resolve(thumbnailPath: person.thumbnailPath), paths.consentClipURL(for: id), person.consent.clipURL].compactMap({ $0 }) {
            try? fm.removeItem(at: url)
        }
        if let identifier = person.contactIdentifier, let contacts {
            Task { try? await contacts.delete(identifier: identifier) }
        }
        rebuildGallery()
    }

    /// Demo controls: forgets everyone. Never touches the TTS cache (that lives in Caches/tts).
    func removeAll() throws {
        for p in people { try remove(id: p.id) }
    }

    /// Rename / phone edits from Person detail.
    func update(id: UUID, _ edit: (inout Person) -> Void) throws {
        guard let idx = people.firstIndex(where: { $0.id == id }) else { return }
        var p = people[idx]
        edit(&p)
        try add(p)
    }

    // MARK: Files

    func writeThumbnail(_ jpeg: Data, for id: UUID) throws -> String {
        try paths.ensureDirectories()
        try jpeg.write(to: paths.thumbnailURL(for: id), options: .atomic)
        return paths.relativeThumbnailPath(for: id)
    }

    func thumbnailURL(for p: Person) -> URL? {
        let url = paths.resolve(thumbnailPath: p.thumbnailPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func consentClipURL(for p: Person) -> URL? {
        for url in [p.consent.clipURL, paths.consentClipURL(for: p.id)].compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) { return url }
        return nil
    }

    // MARK: Private

    private func load() {
        guard let data = try? Data(contentsOf: paths.peopleJSON) else { people = []; rebuildGallery(); return }
        people = (try? decoder.decode([Person].self, from: data)) ?? []
        rebuildGallery()
    }

    private func persist() throws {
        try paths.ensureDirectories()
        let data = try encoder.encode(people)
        try data.write(to: paths.peopleJSON, options: .atomic)
    }

    private func rebuildGallery() {
        let id = modelID
        let g = Gallery(modelID: id, people: people.map { p in (p.id, p.name, p.embeddings.filter { $0.modelID == id }.map(\.vector)) })
        galleryLock.withLock { $0 = g }
        bus.publish(())
    }
}
