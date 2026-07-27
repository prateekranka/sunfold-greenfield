import Foundation
import os

/// Loud, visible diagnostics for the fail-closed rule: when art or a mesh is
/// missing we fall back to a readable primitive *and* say so, rather than
/// crashing or silently rendering nothing.
enum DebugLog {
    private static let logger = Logger(subsystem: "com.sunfold.greenfield", category: "world")

    /// Warnings raised this session, surfaced in the debug overlay.
    @MainActor private(set) static var warnings: [String] = []

    static func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        Task { @MainActor in
            // Keep the tail only; the overlay has limited room.
            warnings.append(message)
            if warnings.count > 12 { warnings.removeFirst(warnings.count - 12) }
        }
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
