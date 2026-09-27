import Foundation

/// 睡眠の推定（夜間の長い静止区間を「睡眠」とみなす）。描画・保存から切り離した純粋な関数。
///
/// CoreMotionは睡眠を直接返さないため、次の条件をすべて満たす「静かな時間のひと続き」を睡眠とみなす。
///  ・5分ごとに見て、静止（不明を含む）が半分以上で、その1時間の歩数が300歩未満の時間を「静かな時間」とする
///  ・静かな時間の間に、60分以内の中断（トイレ・寝返り・充電中の振動などによるCoreMotionの誤検知）が
///    入っても、ひと続きとみなす（中断中の区間そのものの種類・色は変えない）
///  ・「3時間以上」の判定は、ひと続きの範囲の長さ（開始〜終了）ではなく、その中で実際に
///    静かだった時間の合計で数える。中断を大きめに許容する代わりに、中断の時間を睡眠に
///    水増ししないようにするため
///  ・開始時刻が20時〜翌4時半ごろ
///  ・終了時刻が正午まで
/// 注意: 夜更かしで動かずにスマホを見ていた時間も、条件に合えば睡眠として扱われる。
/// 眠っている最中に短い中断で歩行などが入っていても、その活動の区間はそのまま残し、静止・不明の部分だけを睡眠に置き換える。
///
/// 【2026-09-27追記】中断の許容を15分→60分に広げた。実機で「23時就寝・翌7時起床なのに
/// 0時以降が睡眠の色にならない」という不具合が2回の日境界修正後も再発し、調査の結果、
/// CoreMotionが夜間に数十分だけ「歩行」「不明」等に誤って分類することがあり、それが
/// 15分の許容を超えると、その前後がそれぞれ3時間未満に分断されて「睡眠なし」になって
/// しまうことが原因と分かったため。中断1回あたり60分までなら、複数回あってもひと続きとみなす。
enum SleepEstimator {

    /// 睡眠とみなす最短の長さ（中断を除いた、実際に静かだった時間の合計）。
    static let minimumDuration: TimeInterval = 3 * 3600
    /// ひと続きとみなす中断1回あたりの最大の長さ。CoreMotionの数十分単位の誤検知を吸収できるよう、
    /// 実測での様子を見て仮に60分としている（元は15分だったが、実機で短すぎることが分かった）。
    static let maximumInterruption: TimeInterval = 60 * 60
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
        let quiet = quietSlices(segments: segments, windowStart: windowStart, windowEnd: windowEnd, stepsInHour: stepsInHour)
        return intervals(fromQuiet: quiet, windowStart: windowStart, windowEnd: windowEnd, calendar: calendar)
    }

    /// 5分ごとに「静かな時間」かどうかを判定した配列（`windowStart`からのスライス番号順）。
    /// 静止（不明・睡眠も含む）が半分以上で、かつその1時間の歩数が300歩未満のスライスをtrueにする。
    private static func quietSlices(
        segments: [ActivitySegment],
        windowStart: Date,
        windowEnd: Date,
        stepsInHour: (Date) -> Int
    ) -> [Bool] {
        let total = windowEnd.timeIntervalSince(windowStart)
        guard total > 0 else { return [] }
        let n = Int(ceil(total / sliceSeconds))

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
        return quiet
    }

    /// `quiet`配列から、ひと続き（60分以内の中断は何回あっても許容）とみなせる区間を探す。
    private static func intervals(fromQuiet quiet: [Bool], windowStart: Date, windowEnd: Date, calendar: Calendar) -> [SleepInterval] {
        let n = quiet.count
        let maxGapSlices = Int(maximumInterruption / sliceSeconds)
        var result: [SleepInterval] = []
        var i = 0
        while i < n {
            guard quiet[i] else { i += 1; continue }
            let first = i
            var last = i
            var gap = 0
            var quietSliceCount = 1
            var j = i + 1
            while j < n {
                if quiet[j] {
                    last = j
                    gap = 0
                    quietSliceCount += 1
                } else {
                    gap += 1
                    if gap > maxGapSlices { break }
                }
                j += 1
            }
            let start = windowStart.addingTimeInterval(Double(first) * sliceSeconds)
            let end = min(windowEnd, windowStart.addingTimeInterval(Double(last + 1) * sliceSeconds))
            // 「3時間以上」は、ひと続きの範囲全体(start〜end、中断も含む)ではなく、
            // 実際に静かだったスライスの合計時間で判定する(中断を睡眠に水増ししないため)。
            let quietDuration = Double(quietSliceCount) * sliceSeconds
            if qualifies(start: start, end: end, quietDuration: quietDuration, calendar: calendar) {
                result.append(SleepInterval(start: start, end: end))
            }
            i = last + 1
        }
        return result
    }

    /// 長さ・開始時刻・終了時刻の条件を満たすか。
    /// `quietDuration`を渡すと、それを長さの判定に使う（渡さなければ`end - start`をそのまま使う）。
    static func qualifies(start: Date, end: Date, quietDuration: TimeInterval? = nil, calendar: Calendar = .current) -> Bool {
        let duration = quietDuration ?? end.timeIntervalSince(start)
        guard duration >= minimumDuration else { return false }
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let startMinutes = (s.hour ?? 0) * 60 + (s.minute ?? 0)
        let startOK = startMinutes >= 20 * 60 || startMinutes <= 4 * 60 + 30
        let e = calendar.dateComponents([.hour, .minute], from: end)
        let endMinutes = (e.hour ?? 0) * 60 + (e.minute ?? 0)
        let endOK = endMinutes <= 12 * 60
        return startOK && endOK
    }

    /// 活動区間のうち、静止・不明の部分を、推定した睡眠の区間に重なる「実際に静かだった」範囲だけ
    /// `.sleeping`に置き換える。ひと続きの睡眠区間の中に、60分以内の中断（歩数超過・活動区間の
    /// 種類違いなど）があっても、その中断の部分自体は睡眠には置き換えない（元の種類のまま残す）。
    static func estimate(
        segments: [ActivitySegment],
        windowStart: Date,
        windowEnd: Date,
        stepsInHour: (Date) -> Int,
        calendar: Calendar = .current
    ) -> [ActivitySegment] {
        let quiet = quietSlices(segments: segments, windowStart: windowStart, windowEnd: windowEnd, stepsInHour: stepsInHour)
        let sleepIntervals = intervals(fromQuiet: quiet, windowStart: windowStart, windowEnd: windowEnd, calendar: calendar)
        guard !sleepIntervals.isEmpty else { return segments }

        func sliceIndex(of date: Date) -> Int {
            Int(floor(date.timeIntervalSince(windowStart) / sliceSeconds))
        }

        var result: [ActivitySegment] = []
        for segment in segments {
            guard segment.kind == .stationary || segment.kind == .unknown else {
                result.append(segment)
                continue
            }
            var cursor = segment.start
            for interval in sleepIntervals {
                let overlapStart = max(segment.start, interval.start)
                let overlapEnd = min(segment.end, interval.end)
                guard overlapEnd > overlapStart else { continue }

                // overlapの範囲を、静かだった・そうでなかった連続区間ごとに分けて処理する
                // （中断の間だけは睡眠にしない）。
                var t = overlapStart
                while t < overlapEnd {
                    let idx = sliceIndex(of: t)
                    let isQuiet = idx >= 0 && idx < quiet.count && quiet[idx]
                    var runEnd = windowStart.addingTimeInterval(Double(idx + 1) * sliceSeconds)
                    var nextIdx = idx + 1
                    while runEnd < overlapEnd, nextIdx < quiet.count, quiet[nextIdx] == isQuiet {
                        runEnd = windowStart.addingTimeInterval(Double(nextIdx + 1) * sliceSeconds)
                        nextIdx += 1
                    }
                    let runEndClipped = min(runEnd, overlapEnd)
                    if isQuiet {
                        if t > cursor {
                            result.append(ActivitySegment(start: cursor, end: t, kind: segment.kind))
                        }
                        result.append(ActivitySegment(start: t, end: runEndClipped, kind: .sleeping))
                        cursor = runEndClipped
                    }
                    t = runEndClipped
                }
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
