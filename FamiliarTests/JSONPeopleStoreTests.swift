import XCTest
@testable import Familiar

@MainActor
final class JSONPeopleStoreTests: XCTestCase {
    func testAddPersistsAndReloads() throws {
        let paths = MemoryPaths.temporary()
        let store = JSONPeopleStore(paths: paths, modelID: "fake")
        let p = makePerson()
        try store.add(p)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.peopleJSON.path))
        let again = JSONPeopleStore(paths: paths, modelID: "fake")
        XCTAssertEqual(again.all().map(\.id), [p.id])
        XCTAssertEqual(again.all().first?.name, "Marcus")
        XCTAssertEqual(again.gallery().people.count, 1)
        XCTAssertEqual(again.gallery().people.first?.embeddings.first?.count, 512)
    }

    func testGalleryFiltersByModelID() throws {
        let store = JSONPeopleStore(paths: .temporary(), modelID: "w600k_mbf")
        try store.add(makePerson(modelID: "fake"))
        XCTAssertEqual(store.gallery().people.count, 0)
        XCTAssertEqual(store.gallery().modelID, "w600k_mbf")
        store.modelID = "fake"
        XCTAssertEqual(store.gallery().people.count, 1)
    }

    func testRemoveDeletesFilesAndContact() async throws {
        let paths = MemoryPaths.temporary()
        let contacts = RecordingContactsBridge()
        let store = JSONPeopleStore(paths: paths, modelID: "fake")
        var p = makePerson()
        p.contactIdentifier = "CN123"
        p.thumbnailPath = try store.writeThumbnail(Data([1, 2, 3]), for: p.id)
        try store.add(p)
        try Data([0, 1]).write(to: paths.consentClipURL(for: p.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.thumbnailURL(for: p.id).path))
        let store2 = JSONPeopleStore(paths: paths, modelID: "fake", contacts: contacts)
        try store2.remove(id: p.id)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(store2.all().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.thumbnailURL(for: p.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.consentClipURL(for: p.id).path))
        XCTAssertEqual(contacts.deleted, ["CN123"])
        XCTAssertEqual(store2.gallery().people.count, 0)
    }

    func testFindIsCaseInsensitivePrefixAndChangesPublish() async throws {
        let store = JSONPeopleStore(paths: .temporary(), modelID: "fake")
        let stream = store.changes()
        let waiter = Task { for await _ in stream { return true }; return false }
        try store.add(makePerson(name: "Marcus"))
        XCTAssertEqual(store.find(name: "mar")?.name, "Marcus")
        XCTAssertEqual(store.find(name: "MARCUS")?.name, "Marcus")
        XCTAssertNil(store.find(name: "Dana"))
        let got = await waiter.value
        XCTAssertTrue(got)
    }

    func testResetPeopleLeavesOtherFolders() throws {
        let paths = MemoryPaths.temporary()
        let store = JSONPeopleStore(paths: paths, modelID: "fake")
        try store.add(makePerson())
        let ttsCache = paths.root.appendingPathComponent("tts_cache", isDirectory: true)
        try FileManager.default.createDirectory(at: ttsCache, withIntermediateDirectories: true)
        try Data([9]).write(to: ttsCache.appendingPathComponent("x.pcm"))
        try store.removeAll()
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ttsCache.appendingPathComponent("x.pcm").path))
    }
}
