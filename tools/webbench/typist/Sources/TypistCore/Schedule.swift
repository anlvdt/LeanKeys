public enum Speed: String {
    case human
    case fast
    case burst
}

/// Deterministic inter-key delays. Same seed, same delays.
public enum Schedule {
    /// Seconds to wait before each of `count` keys.
    public static func delays(count: Int, speed: Speed, seed: UInt64) -> [Double] {
        guard count > 0 else { return [] }
        switch speed {
        case .fast:
            return Array(repeating: 1.0 / 25.0, count: count)
        case .burst:
            return Array(repeating: 0.0, count: count)
        case .human:
            var rng = SplitMix64(state: seed)
            let lo = 1.0 / 12.0
            let hi = 1.0 / 8.0
            return (0..<count).map { _ in
                let u = Double(rng.next() >> 11) / Double(UInt64(1) << 53)
                return lo + (hi - lo) * u
            }
        }
    }
}

/// SplitMix64: small, fixed, and reproducible across runs and platforms.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
