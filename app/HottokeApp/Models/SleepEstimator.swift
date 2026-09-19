import Foundation

/// 睡眠の推定（夜間の長い静止区間を「睡眠」とみなす）。描画・保存から切り離した純粋な関数。
///
/// CoreMotionは睡眠を直接返さないため、次の条件をすべて満たす「静止のひと続き」を睡眠とみなす。
///  ・5分ごとに見て、静止（不明を含む）が半分以上で、その1時間の歩数が300歩未満の時間を「静かな時間」とする
///  ・静かな時間の間に、15分以内の中断（トイレなど）が入っても、ひと続きとみなす
///  ・ひと続きが3時間以上
///  ・開始時刻が20時〜翌4時半ごろ
///  ・終了時刻が正午まで
/// 注意: 夜更かしで動かずにスマホを見ていた時間も、条件に合えば睡眠として扱われる。
/// 眠っている最中に短い中断で歩行などが入っていても、その活動の区間はそのまま残し、静止・不明の部分だけを睡眠に置き換える。
enum SleepEstimator {

    /// 睡眠とみなす最短の長さ。
    static let minimumDuration: TimeInterval = 3 * 3600
    /// ひと続きとみなす中断の最大の長さ。
    static let maximumInterruption: TimeInterval = 15 * 60
    /// この歩数/時間以上の時間は、明らかに動いていたので対象外。
    static let stepsPerHourLimit: Int = 300
    /// 判定の細かさ（5分）。
    static let sliceSeconds: TimeInterval = 300

    /// 推定した睡眠の区間。
    struct SleepInterval: Equatable {
        let start: Date
        let end: Date
    }

    /// 睡眠の区間を推定する。`segments`は`windowStart`〜`windowEnd`の範囲の活動区間（複数日にまたがってよい）。
    /// `stepsInHour`は「その1時間（開始時刻を渡す）の歩数」を返す。分からない時間は0を返せばよい。
    static func estimateIntervals(
        segments: [ActivitySegment],
        windowStart: Date,
        windowEnd: Date,
        stepsInHour: (Date) -> Int,
        calendar: Calendar = .current
    ) -> [SleepInterval] {
        let total = windowEnd.timeIntervalSince(windowStart)
        guard total > 0 else { return [] }
        let n = Int(ceil(total / sliceSeconds))

        // 5分ごとの「静かな時間」判定
        var quiet = [Bool](repeating: false, count: n)
        var stepsCache: [Int: Int] = [:]
        for i in 0..<n {
            let s0 = windowStart.addingTimeInterval(Double(i) * sliceSeconds)
            let s1 = min(windowEnd, s0.addingTimeInterval(sliceSeconds))
            let length = s1.timeIntervalSince(s0)
            var stationary = 0.0
            for segment in segments {
                let overlap = min(segment.end, s1).timeIntervalSince(max(segment.start, s0))
                if overlap > 0 && (segment.kind == .stationary || segment.kind == .unknown || segment.kind == .sleeping) {
                    stationary += overlap
                }
            }
            guard stationary >= 0.5 * length else { continue }
            let hourIndex = Int(floor(s0.timeIntervalSinceReferenceDate / 3600))
            let steps: Int
            if let cached = stepsCache[hourIndex] {
                steps = cached
            } else {
                let hourStart = Date(timeIntervalSinceReferenceDate: Double(hourIndex) * 3600)
                steps = stepsInHour(hourStart)
                stepsCache[hourIndex] = steps
            }
            quiet[i] = steps < stepsPerHourLimit
        }

        // ひと続き（短い中断は許容）を探す
        let maxGapSlices = Int(maximumInterruption / sliceSeconds)
        var result: [SleepInterval] = []
        var i = 0
        while i < n {
            guard quiet[i] else { i += 1; continue }
            let first = i
            var last = i
            var gap = 0
            var j = i + 1
            while j < n {
                if quiet[j] {
                    last = j
                    gap = 0
                } else {
                    gap += 1
                    if gap > maxGapSlices { break }
                }
                j += 1
            }
            let start = windowStart.addingTimeInterval(Double(first) * sliceSeconds)
            let end = min(windowEnd, windowStart.addingTimeInterval(Double(last + 1) * sliceSeconds))
            if qualifies(start: start, end: end, calendar: calendar) {
                result.append(SleepInterval(start: start, end: end))
            }
            i = last + 1
        }
        return result
    }

    /// 長さ・開始時刻・終了時刻の条件を満たすか。
    static func qualifies(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        guard end.timeIntervalSince(start) >= minimumDuration else { return false }
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let startMinutes = (s.hour ?? 0) * 60 + (s.minute ?? 0)
        let startOK = startMinutes >= 20 * 60 || startMinutes <= 4 * 60 + 30
        let e = calendar.dateComponents([.hour, .minute], from: end)
        let endMinutes = (e.hour ?? 0) * 60 + (e.minute ?? 0)
        let endOK = endMinutes <= 12 * 60
        return startOK && endOK
    }

    /// 活動区間のうち、静止・不明の部分を、推定した睡眠の区間に重なる範囲だけ`.sleeping`に置き換える。
    static func estimate(
        segments: [ActivitySegment],
        windowStart: Date,
        windowEnd: Date,
        stepsInHour: (Date) -> Int,
        calendar: Calendar = .current
    ) -> [ActivitySegment] {
        let intervals = estimateIntervals(segments: segments, windowStart: windowStart, windowEnd: windowEnd, stepsInHour: stepsInHour, calendar: calendar)
        guard !intervals.isEmpty else { return segments }
        var result: [ActivitySegment] = []
        for segment in segments {
            guard segment.kind == .stationary || segment.kind == .unknown else {
                result.append(segment)
                continue
            }
            // この区間を、睡眠の区間で切り分ける
            var cursor = segment.start
            for interval in intervals {
                let overlapStart = max(segment.start, interval.start)
                let overlapEnd = min(segment.end, interval.end)
                guard overlapEnd > overlapStart else { continue }
                if overlapStart > cursor {
                    result.append(ActivitySegment(start: cursor, end: overlapStart, kind: segment.kind))
                }
                result.append(ActivitySegment(start: overlapStart, end: overlapEnd, kind: .sleeping))
                cursor = overlapEnd
            }
            if segment.end > cursor {
                result.append(ActivitySegment(start: cursor, end: segment.end, kind: segment.kind))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// 指定の範囲（その日の0時〜終わり）にはみ出した部分を切り落とす。
    static func clip(_ segments: [ActivitySegment], from start: Date, to end: Date) -> [ActivitySegment] {
        segments.compactMap { segment in
            let s = max(segment.start, start)
            let e = min(segment.end, end)
            return e > s ? ActivitySegment(start: s, end: e, kind: segment.kind) : nil
        }
    }
}
