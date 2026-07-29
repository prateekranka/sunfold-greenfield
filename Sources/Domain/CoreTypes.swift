import Foundation

/// Stable, durable identity for everything the simulation owns.
///
/// Architectural rule: never use array position as gameplay identity. Every unit,
/// building, deposit, formation and objective carries one of these for its whole life.
struct EntityID: Hashable, Sendable, CustomStringConvertible {
    let raw: UInt32
    var description: String { "#\(raw)" }
}

/// Allocates `EntityID`s in a deterministic, replayable order.
struct EntityIDAllocator: Sendable {
    private var next: UInt32 = 1

    mutating func allocate() -> EntityID {
        defer { next &+= 1 }
        return EntityID(raw: next)
    }
}

enum Faction: String, CaseIterable, Sendable {
    case sunwoven
    case gravemark

    var opponent: Faction {
        switch self {
        case .sunwoven: .gravemark
        case .gravemark: .sunwoven
        }
    }

    var displayName: String {
        switch self {
        case .sunwoven: "Sunwoven"
        case .gravemark: "Gravemark"
        }
    }
}

/// The four legible resources. Order here is the order shown in the top bar.
enum ResourceKind: String, CaseIterable, Sendable {
    case provisions
    case matter
    case lumen
    case aether

    var displayName: String {
        switch self {
        case .provisions: "Provisions"
        case .matter: "Matter"
        case .lumen: "Lumen"
        case .aether: "Aether"
        }
    }

    /// Renewable sources never deplete; the rest draw down a finite deposit.
    var isRenewable: Bool { self == .provisions }
}

/// A bundle of the four resources. Used for stock, costs and rates alike.
struct ResourcePool: Sendable, Equatable {
    var provisions: Double = 0
    var matter: Double = 0
    var lumen: Double = 0
    var aether: Double = 0

    static let zero = ResourcePool()

    init(provisions: Double = 0, matter: Double = 0, lumen: Double = 0, aether: Double = 0) {
        self.provisions = provisions
        self.matter = matter
        self.lumen = lumen
        self.aether = aether
    }

    subscript(kind: ResourceKind) -> Double {
        get {
            switch kind {
            case .provisions: provisions
            case .matter: matter
            case .lumen: lumen
            case .aether: aether
            }
        }
        set {
            switch kind {
            case .provisions: provisions = newValue
            case .matter: matter = newValue
            case .lumen: lumen = newValue
            case .aether: aether = newValue
            }
        }
    }

    /// True when this pool can pay `cost` in full.
    func covers(_ cost: ResourcePool) -> Bool {
        ResourceKind.allCases.allSatisfy { self[$0] >= cost[$0] }
    }

    static func + (lhs: ResourcePool, rhs: ResourcePool) -> ResourcePool {
        var result = lhs
        for kind in ResourceKind.allCases { result[kind] += rhs[kind] }
        return result
    }

    static func - (lhs: ResourcePool, rhs: ResourcePool) -> ResourcePool {
        var result = lhs
        for kind in ResourceKind.allCases { result[kind] -= rhs[kind] }
        return result
    }

    static func * (lhs: ResourcePool, scalar: Double) -> ResourcePool {
        var result = lhs
        for kind in ResourceKind.allCases { result[kind] *= scalar }
        return result
    }

    /// Compact cost line for HUD tiles, e.g. "70 Matter".
    var costSummary: String {
        ResourceKind.allCases
            .compactMap { kind in
                let amount = self[kind]
                guard amount > 0 else { return nil }
                return "\(Int(amount.rounded())) \(kind.displayName)"
            }
            .joined(separator: " · ")
    }
}

/// The two ages in this slice. Ascension is explicitly out of scope.
enum Age: Int, Comparable, Sendable {
    case foundation = 0
    case voyager = 1

    var displayName: String {
        switch self {
        case .foundation: "Foundation"
        case .voyager: "Voyager"
        }
    }

    static func < (lhs: Age, rhs: Age) -> Bool { lhs.rawValue < rhs.rawValue }
}
