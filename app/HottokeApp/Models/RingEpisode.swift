import Foundation

/// 1回の活動（歩いた・走った・自転車に乗った・乗り物に乗った）のまとまり。花びらやアーチになる。
struct RingEpisode: Equatable {
    let kind: ActivityKind
    /// 開始・終了（時）
    let start: Double
    let end: Double
    /// 強さの平均・最大（歩/分）
    let average: Double
    let peak: Double

    var duration: Double { end - start }
    var mid: Double { (start + end) / 2 }
    /// 強さ（0...1）。1 − exp(−(0.5×平均 + 0.5×最大)/70)。
    var strength: Double { 1 - exp(-(0.5 * average + 0.5 * peak) / DailyRingLayout.intensityScale) }
}

extension DailyRingLayout {
    /// 移動系の活動として拾う種類。
    static let episodeKinds: [ActivityKind] = [.walking, .running, .cycling, .automotive]
    /// 5分スライスの中で、その種類が占める割合がこれ以上なら「その活動の最中」とみなす。
    static let episodeWeightThreshold: Double = 0.35
    /// 同じ種類で、これ未満（分）の間隔は結合する（7分未満 = 5分スライス1つ分の隙間は許す）。
    static let episodeMergeGapSlices = 1
    /// これ未満（分）の活動は捨てる。
    static let episodeMinimumMinutes: Double = 5

    /// 5分スライスの集計から、活動のまとまり（エピソード）を取り出す。開始の早い順。
    /// 今日の途中は、現在時刻（描いた範囲）で打ち切られる。積算の密度からも、同じ方法で「平均的な1日」のまとまりを取り出せる。
    static func episodes(from density: DailyRingDensity) -> [RingEpisode] {
        let n = density.sliceCount
        guard n > 0 else { return [] }
        var result: [RingEpisode] = []
        for kind in episodeKinds {
            guard let weights = density.rawWeights[kind] else { continue }
            var runs: [(first: Int, last: Int)] = []
            var i = 0
            while i < n {
                guard weights[i] >= episodeWeightThreshold else { i += 1; continue }
                let first = i
                var last = i
                var gap = 0
                var j = i + 1
                while j < n {
                    if weights[j] >= episodeWeightThreshold {
                        last = j
                        gap = 0
                    } else {
                        gap += 1
                        if gap > episodeMergeGapSlices { break }
                    }
                    j += 1
                }
                runs.append((first, last))
                i = last + 1
            }
            for run in runs {
                var activeMinutes = 0.0
                var intensitySum = 0.0
                var peak = 0.0
                var count = 0.0
                for s in run.first...run.last {
                    activeMinutes += weights[s] * sliceMinutes
                    intensitySum += density.rawIntensity[s]
                    peak = max(peak, density.rawIntensity[s])
                    count += 1
                }
                guard activeMinutes >= episodeMinimumMinutes else { continue }
                let start = Double(run.first) * sliceHours
                let end = min(density.drawnHours, Double(run.last + 1) * sliceHours)
                guard end > start else { continue }
                result.append(RingEpisode(kind: kind, start: start, end: end, average: intensitySum / max(1, count), peak: peak))
            }
        }
        return result.sorted { $0.start < $1.start }
    }
}
