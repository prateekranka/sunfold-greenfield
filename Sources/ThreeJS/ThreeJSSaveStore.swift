import Foundation

/// Save slots for the Three.js experiment.
///
/// Ownership follows #19 exactly: SwiftUI owns save slots, the runtime owns the
/// state inside them. Swift never reads a field of the snapshot and never
/// decides what it means — it stores an opaque document and hands the same
/// bytes back. That is what keeps simulation truth on one side of the bridge.
@MainActor
final class ThreeJSSaveStore: ObservableObject {
    struct Slot: Equatable, Codable {
        let snapshot: String
        let savedAt: Date
        let faction: String
        /// Recorded so a slot list can be shown without parsing the document.
        let schemaVersion: Int
    }

    @Published private(set) var slot: Slot?

    private let url: URL

    init(filename: String = "threejs-save-slot.json") {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = documents.appendingPathComponent(filename)
        slot = Self.read(from: url)
    }

    var hasSave: Bool { slot != nil }

    func write(snapshot: String, faction: String) {
        let slot = Slot(
            snapshot: snapshot,
            savedAt: Date(),
            faction: faction,
            schemaVersion: ThreeJSBridgeEnvelope.currentSaveSchemaVersion
        )
        self.slot = slot
        guard let data = try? JSONEncoder().encode(slot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        slot = nil
        try? FileManager.default.removeItem(at: url)
    }

    /// A slot written by a different schema version is dropped rather than
    /// offered. Refusing to load is honest; loading a world this build cannot
    /// reproduce is not.
    private static func read(from url: URL) -> Slot? {
        guard let data = try? Data(contentsOf: url),
              let slot = try? JSONDecoder().decode(Slot.self, from: data),
              slot.schemaVersion == ThreeJSBridgeEnvelope.currentSaveSchemaVersion
        else { return nil }
        return slot
    }
}
