import Foundation
import Contacts
import UIKit

/// `ContactsBridge` on `CNContactStore`. Creates a contact with a photo and an organisation line, never a note
/// (notes need an Apple-approved entitlement and the save fails without it). `call` / `text` only open the dialer or
/// Messages; the app never speaks or sends on the user's behalf.
final class CNContactsBridge: ContactsBridge, @unchecked Sendable {
    enum BridgeError: LocalizedError {
        case accessDenied
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .accessDenied: return "Contacts access was not granted."
            case let .notFound(id): return "No contact with identifier \(id)."
            }
        }
    }

    static let organizationName = "Familiar"
    static let jobTitle = "Met via Familiar · HackTX · Oct 25 2026"

    private let store = CNContactStore()
    private let thumbnailData: (Person) -> Data?
    private let open: (URL) -> Void

    init(thumbnailData: @escaping (Person) -> Data? = { _ in nil }, open: @escaping (URL) -> Void = CNContactsBridge.openURL) {
        self.thumbnailData = thumbnailData
        self.open = open
    }

    static func openURL(_ url: URL) {
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }

    static var authorizationStatus: CNAuthorizationStatus { CNContactStore.authorizationStatus(for: .contacts) }

    func requestAccess() async throws -> Bool {
        switch Self.authorizationStatus {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            if #available(iOS 18, *), Self.authorizationStatus == .limited { return true }
            return try await store.requestAccess(for: .contacts)
        }
    }

    func create(for p: Person) async throws -> String {
        guard try await requestAccess() else { throw BridgeError.accessDenied }
        let contact = CNMutableContact()
        contact.givenName = p.name
        contact.organizationName = Self.organizationName
        contact.jobTitle = Self.jobTitle
        if let data = thumbnailData(p) { contact.imageData = data }
        if let phone = p.phone, !phone.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
        return contact.identifier
    }

    func delete(identifier: String) async throws {
        guard try await requestAccess() else { throw BridgeError.accessDenied }
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor]
        let contact: CNContact
        do { contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys) } catch { throw BridgeError.notFound(identifier) }
        guard let mutable = contact.mutableCopy() as? CNMutableContact else { return }
        let request = CNSaveRequest()
        request.delete(mutable)
        try store.execute(request)
    }

    func call(_ p: Person) {
        guard let digits = Self.digits(p.phone), let url = URL(string: "tel://\(digits)") else { return }
        open(url)
    }

    func text(_ p: Person) {
        guard let digits = Self.digits(p.phone), let url = URL(string: "sms:\(digits)") else { return }
        open(url)
    }

    static func digits(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let kept = phone.filter { $0.isNumber || $0 == "+" }
        return kept.isEmpty ? nil : kept
    }
}

/// Test double that records what the flow asked for.
final class RecordingContactsBridge: ContactsBridge, @unchecked Sendable {
    private(set) var created: [Person] = []
    private(set) var deleted: [String] = []
    private(set) var called: [Person] = []
    private(set) var texted: [Person] = []
    var failCreate = false

    func create(for p: Person) async throws -> String {
        if failCreate { throw CNContactsBridge.BridgeError.accessDenied }
        created.append(p)
        return "fake-\(p.id.uuidString)"
    }
    func delete(identifier: String) async throws { deleted.append(identifier) }
    func call(_ p: Person) { called.append(p) }
    func text(_ p: Person) { texted.append(p) }
}
