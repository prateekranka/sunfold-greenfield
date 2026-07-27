import Foundation

/// SplitMix64 — a small, fast, fully specified generator.
///
/// The simulation must replay identically from a seed, so it never touches
/// `SystemRandomNumberGenerator`, `Double.random` or any other source whose
/// sequence is not pinned by our own state.
struct DeterministicRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zero state, which is a weak starting point for SplitMix64.
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unitFloat() -> Float {
        // 24 bits of mantissa is exactly what a Float can represent without bias.
        Float(next() >> 40) / Float(1 << 24)
    }

    /// Uniform in [lower, upper).
    mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + unitFloat() * (range.upperBound - range.lowerBound)
    }

    /// A generator derived from this seed and a stable string tag.
    ///
    /// Lets each subsystem draw from its own stream, so adding a call in one
    /// place cannot shift the numbers every other system receives.
    static func stream(seed: UInt64, tag: String) -> DeterministicRandom {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in tag.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return DeterministicRandom(seed: seed ^ hash)
    }
}
