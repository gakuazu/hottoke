import Foundation

/// 動画タイムライン上の1つのキーフレーム時点でどんな模様を出すかの手がかり。
struct KaleidoscopeKeyframe: Equatable {
    let position: Double // 0...1（動画の再生位置）
    let timeOfDay: TimeOfDay
    let activityKind: ActivityKind
}

/// docs/02-spec.md 3.4節「動画の時間軸設計」の実装。
/// 単純に実時間で等分するのではなく、活動の「相対的な強さ」で重み付けしたタイムラプスに圧縮する。
/// （静止・就寝中の長い時間帯が間延びしないようにするため）
enum KaleidoscopeTimelineBuilder {

    /// 活動種別ごとの「盛り上がり度」の重み。stationary/unknownを低くすることで、
    /// 長い静止区間が動画内で不自然に間延びしないようにする。
    private static func intensityWeight(_ kind: ActivityKind) -> Double {
        switch kind {
        case .stationary, .unknown: return 0.22
        case .walking: return 1.0
        case .running: return 1.6
        case .automotive: return 0.75
        case .cycling: return 1.3
        }
    }

    static func buildKeyframes(from data: DailyActivityData, frameCount: Int) -> [KaleidoscopeKeyframe] {
        guard frameCount > 0 else { return [] }

        guard !data.segments.isEmpty else {
            return fallbackKeyframes(frameCount: frameCount, referenceDate: Date())
        }

        let weighted: [(segment: ActivitySegment, weight: Double)] = data.segments.map {
            ($0, intensityWeight($0.kind) * $0.duration)
        }
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }

        guard totalWeight > 0 else {
            return fallbackKeyframes(frameCount: frameCount, referenceDate: data.segments.last?.end ?? Date())
        }

        // 各区間が動画タイムライン上で占める [start, end] (0...1) の範囲を、重み付き累積で計算する。
        var ranges: [(segment: ActivitySegment, start: Double, end: Double)] = []
        var cumulative: Double = 0
        for (segment, weight) in weighted {
            let start = cumulative / totalWeight
            cumulative += weight
            let end = cumulative / totalWeight
            ranges.append((segment, start, end))
        }

        return (0..<frameCount).map { index in
            let position = frameCount == 1 ? 0 : Double(index) / Double(frameCount - 1)
            let match = ranges.first { position >= $0.start && position <= $0.end } ?? ranges[ranges.count - 1]
            let hour = Calendar.current.component(.hour, from: match.segment.start)
            return KaleidoscopeKeyframe(position: position, timeOfDay: TimeOfDay.of(hour: hour), activityKind: match.segment.kind)
        }
    }

    /// データがまだない・取得できない場合のフォールバック。
    /// docs/02-spec.md 7章の決定事項どおり、専用の演出は用意せず「静けさの模様」を一貫したロジックで出す。
    private static func fallbackKeyframes(frameCount: Int, referenceDate: Date) -> [KaleidoscopeKeyframe] {
        let hour = Calendar.current.component(.hour, from: referenceDate)
        let timeOfDay = TimeOfDay.of(hour: hour)
        return (0..<frameCount).map { index in
            let position = frameCount == 1 ? 0 : Double(index) / Double(frameCount - 1)
            return KaleidoscopeKeyframe(position: position, timeOfDay: timeOfDay, activityKind: .stationary)
        }
    }
}
