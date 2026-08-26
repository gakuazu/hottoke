import Foundation

/// 決定論的な乱数生成器（xorshift64）。
/// 同じseedなら常に同じ模様の並びになる（今日の模様の再現性・動画フレーム間の一貫性に必要）。
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
