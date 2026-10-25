import Foundation
import OnnxRuntimeBindings

/// Proves the ONNX Runtime package links. S2 replaces this with `OnDeviceEmbedder`.
enum ORTSmokeTest {
    static func versionString() -> String { ORTVersion() ?? "unknown" }
}
