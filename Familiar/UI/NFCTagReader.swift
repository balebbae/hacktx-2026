import Foundation
import SwiftUI
#if canImport(CoreNFC)
import CoreNFC
#endif

/// Reads one NDEF tag (URL or text record) and hands back the URL it carries. Core NFC only exists on iPhone; the
/// Simulator and iPad report `isAvailable == false` and the button stays hidden. Background tag reading also opens
/// `familiar://introduce` URL-record tags on iPhone when the app is installed; this button is the explicit path.
@MainActor
final class NFCTagReader: NSObject, ObservableObject {
    @Published private(set) var status: String?
    @Published private(set) var isScanning = false
    private var onURL: ((URL) -> Void)?

    static var isAvailable: Bool {
        #if canImport(CoreNFC)
        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    /// First URL found in the records: URI records as-is, text records parsed as a URL.
    nonisolated static func url(fromRecords records: [(typeNameFormat: UInt8, type: Data, payload: Data)]) -> URL? {
        for r in records {
            let type = String(decoding: r.type, as: UTF8.self)
            guard r.typeNameFormat == 0x01 else { continue }   // NFC well-known
            if type == "U", let first = r.payload.first {
                let prefixes = ["", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:"]
                let prefix = Int(first) < prefixes.count ? prefixes[Int(first)] : ""
                let rest = String(decoding: r.payload.dropFirst(), as: UTF8.self)
                if let u = URL(string: prefix + rest) { return u }
            } else if type == "T", let first = r.payload.first {
                let langLen = Int(first & 0x3F)
                let text = String(decoding: r.payload.dropFirst(1 + langLen), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if let u = URL(string: text), u.scheme != nil { return u }
            }
        }
        return nil
    }

    #if canImport(CoreNFC)
    private var session: NFCNDEFReaderSession?

    func scan(onURL: @escaping (URL) -> Void) {
        guard Self.isAvailable else { status = "This device cannot read NFC tags."; return }
        self.onURL = onURL
        let s = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        s.alertMessage = "Hold the top of the phone near the tag."
        session = s
        isScanning = true
        status = nil
        s.begin()
    }
    #else
    func scan(onURL: @escaping (URL) -> Void) { status = "This device cannot read NFC tags." }
    #endif
}

#if canImport(CoreNFC)
extension NFCTagReader: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let records = messages.flatMap(\.records).map { (typeNameFormat: $0.typeNameFormat.rawValue, type: $0.type, payload: $0.payload) }
        let url = Self.url(fromRecords: records)
        Task { @MainActor in
            self.isScanning = false
            if let url { self.status = "Read \(url.absoluteString)"; self.onURL?(url) } else { self.status = "That tag has no URL on it." }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        Task { @MainActor in
            self.isScanning = false
            self.session = nil
            if code != .readerSessionInvalidationErrorFirstNDEFTagRead, code != .readerSessionInvalidationErrorUserCanceled { self.status = error.localizedDescription }
        }
    }
}
#endif
