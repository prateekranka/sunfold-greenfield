import Foundation
import simd

/// A canonical fingerprint of simulation state, defined once so every
/// determinism test compares the same thing.
///
/// The layout is `Docs/Design/05-RESOLUTIONS-R1.md` §6.13, exactly: FNV-1a over,
/// in order — tick; then for each faction in declaration order its four resource
/// amounts as centi-units; then every unit in ascending `EntityID` as
/// (id, kind, faction, x and z quantised to 1 mm, life in centi-units, activity
/// tag); then every building the same way.
///
/// **Quantising is the point.** Two runs that agree to the millimetre are the
/// same run; comparing raw `Double` bit patterns would fail on a difference no
/// player could observe and no bug could cause. Sorting by `EntityID` is the
/// other half — dictionary order is not stable and would make the hash a coin
/// flip rather than a measurement.
enum WorldHash {

    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    static func value(
        tick: UInt64,
        stock: [Faction: ResourcePool],
        units: [EntityID: Unit],
        buildings: [EntityID: Building]
    ) -> UInt64 {
        var hash = offsetBasis
        mix(&hash, tick)

        for faction in Faction.allCases {
            let pool = stock[faction] ?? .zero
            for kind in ResourceKind.allCases {
                mix(&hash, centi(pool[kind]))
            }
        }

        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard let unit = units[id] else { continue }
            mix(&hash, UInt64(id.raw))
            mix(&hash, tag(unit.kind.rawValue))
            mix(&hash, tag(unit.faction.rawValue))
            mix(&hash, milli(unit.position.x))
            mix(&hash, milli(unit.position.y))
            mix(&hash, centi(unit.life))
            mix(&hash, tag(activityTag(unit.activity)))
        }

        for id in buildings.keys.sorted(by: { $0.raw < $1.raw }) {
            guard let building = buildings[id] else { continue }
            mix(&hash, UInt64(id.raw))
            mix(&hash, tag(building.kind.rawValue))
            // "neutral" is a stable string like every other tag here, so the
            // Dominion Spire folds into the fingerprint without a faction.
            mix(&hash, tag(building.faction?.rawValue ?? "neutral"))
            mix(&hash, milli(building.position.x))
            mix(&hash, milli(building.position.y))
            mix(&hash, centi(building.life))
            mix(&hash, centi(building.constructionProgress))
        }

        return hash
    }

    /// The tag written into the hash for each activity. Stable strings rather
    /// than case ordinals, so reordering the enum cannot silently change a
    /// recorded hash.
    static func activityTag(_ activity: UnitActivity) -> String {
        switch activity {
        case .idle: "idle"
        case .moving: "moving"
        case .gathering: "gathering"
        case .boarding: "boarding"
        case .aboard: "aboard"
        case .constructing: "constructing"
        case .attacking: "attacking"
        }
    }

    // MARK: - Mixing

    private static func mix(_ hash: inout UInt64, _ value: UInt64) {
        var remaining = value
        for _ in 0..<8 {
            hash ^= UInt64(remaining & 0xFF)
            hash &*= prime
            remaining >>= 8
        }
    }

    private static func tag(_ text: String) -> UInt64 {
        var hash = offsetBasis
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return hash
    }

    /// Hundredths, as a two's-complement bit pattern so negatives hash cleanly.
    /// Non-finite values are pinned rather than trapped: a `Double.infinity`
    /// yield exists in this simulation on purpose and must not crash a test.
    private static func centi(_ value: Double) -> UInt64 {
        quantise(value, scale: 100)
    }

    /// Millimetres, from a `Float` world coordinate.
    private static func milli(_ value: Float) -> UInt64 {
        quantise(Double(value), scale: 1000)
    }

    private static func quantise(_ value: Double, scale: Double) -> UInt64 {
        guard value.isFinite else {
            return value > 0 ? UInt64(bitPattern: Int64.max) : UInt64(bitPattern: Int64.min)
        }
        let scaled = (value * scale).rounded()
        guard scaled >= Double(Int64.min), scaled <= Double(Int64.max) else {
            return scaled > 0 ? UInt64(bitPattern: Int64.max) : UInt64(bitPattern: Int64.min)
        }
        return UInt64(bitPattern: Int64(scaled))
    }
}
