import Foundation
import QuartzCore
import os

/// Development aid: the judge-view event log, wake-word hits, Poyo's lines and (debug builds only) final transcript
/// segments, appended to Documents/poyo-log.txt so a test can be read afterwards with
/// `xcrun devicectl device copy from … --domain-type appDataContainer --source Documents/poyo-log.txt`.
/// Trimmed to the newest ~500 KB. Remove the file with Settings → Remove everyone or by reinstalling.
enum DiagnosticLog {
    static let url: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("poyo-log.txt")
    private static let queue = DispatchQueue(label: "familiar.diagnosticlog")
    private static let maxBytes = 1_000_000
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func write(_ text: String) {
        let line = "\(formatter.string(from: Date())) \(text)\n"
        queue.async {
            let data = Data(line.utf8)
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                let size = (try? h.seekToEnd()) ?? 0
                if size > maxBytes, let all = try? Data(contentsOf: url) {
                    try? Data(all.suffix(maxBytes / 2) + data).write(to: url, options: .atomic)
                } else {
                    try? h.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Debug builds only: what the recognizer heard is needed to debug the wake word, but is not kept otherwise.
    static func heard(_ seg: TranscriptSegment) {
        #if DEBUG
        write("heard[\(seg.speaker)] \(seg.text)")
        #endif
    }
}
