import XCTest
@testable import HottokeApp

/// `ActivityDataService`のうち、CoreMotionを使わない「日境界をまたぐ睡眠推定」の部分
/// （`estimateDaySegments`）のテスト。
///
/// オーナー報告「0時を過ぎると睡眠継続してても色が変わっちゃう」の調査用。
/// 結論（詳しくはdocs/04-build-log.mdに記載）:
///  ・前後12時間ウィンドウのおかげで、「今日」の取得と「前日」の取得は、同じ夜の睡眠を
///    一貫して「睡眠」と判定する（testSameNightIsConsistentBetweenTodayAndYesterdayFetch）。
///  ・ただし、就寝から3時間経つまでは「まだ睡眠と判定できない」という仕様上の制約があり、
///    多くの人の就寝時刻（21時前後）だとその3時間後がちょうど0時前後になるため、
///    「0時を過ぎたら色が変わった」ように見える（testNotYetThreeHoursIsNotMidnightSpecific）。
///    これはバグではなく、`SleepEstimator.minimumDuration`（3時間）という仕様上の制約。
///  ・一方、`stepsInHour`が対象日の前後を常に「歩数0（＝静か）」とみなしていた点は、実際に
///    バグを起こしうることが分かった（`testOldBehaviorWasInconsistentAtBoundary`で再現）。
///    対象日の前後の実際の歩数を無視してしまうと、日境界のちょうど前後で実際は動いていた
///    （＝睡眠が中断していた）時間帯を、片方の日の取得では正しく除外できるのに、もう片方の
///    日の取得では「歩数不明→0歩＝静か」と誤ってみなしてしまい、判定が食い違うことがあった。
///    この食い違いを防ぐため、`ActivityDataService.fetch`は対象日の前後ぶんの実際の歩数も
///    問い合わせて使うように修正した（`testFetchLikeUsageIsConsistentAtBoundaryAfterFix`）。
///
/// 【2026-09-27追記】上記2件の修正後も「23時就寝・7時起床なのに0時以降が睡眠にならない」という
/// 報告が再発した。調査の結果、`ActivityDataService`側の日境界の計算自体は正しく動いており
/// （`testCleanEightHourNightMatchesOwnerReportedTimes`で確認）、原因は`SleepEstimator`が
/// 「15分を超える中断」で睡眠のひと続きを分断してしまい、CoreMotionが夜中に数十分だけ
/// 誤って別の種類に分類することがあると、その前後がそれぞれ3時間未満になって睡眠なし判定に
/// なってしまうことだった（`testRealisticOvernightNoiseAcrossMidnightStillBecomesSleep`で確認・
/// `SleepEstimator`側の中断許容を60分に拡大して修正。詳しくは`SleepEstimatorTests.swift`と
/// `docs/04-build-log.md`参照）。
final class ActivityDataServiceTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    /// 9月`d`日の h:m
    private func t(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    private func seg(_ a: Date, _ b: Date, _ kind: ActivityKind) -> ActivitySegment {
        ActivitySegment(start: a, end: b, kind: kind)
    }

    private func sleepingSeconds(_ segments: [ActivitySegment]) -> TimeInterval {
        segments.filter { $0.kind == .sleeping }.reduce(0) { $0 + $1.duration }
    }

    /// 実際の`ActivityDataService.fetch`と同じく、`hourIndex(for:)`をキーにした歩数の辞書を作る。
    private func hourlyStepsDict(_ entries: [(Date, Int)]) -> [Int: Int] {
        var dict: [Int: Int] = [:]
        for (date, steps) in entries {
            dict[ActivityDataService.hourIndex(for: date)] = steps
        }
        return dict
    }

    // MARK: - 1. 前後12時間ウィンドウのおかげで、日をまたいでも一貫して判定される

    func testSameNightIsConsistentBetweenTodayAndYesterdayFetch() {
        // 22:00(18日)〜翌6:00(19日) 静止が続く。19日の朝08:00に、それぞれ「18日を対象日として」
        // 「19日を対象日として」independentに`estimateDaySegments`を呼ぶ（＝「前日」「今日」を
        // それぞれ独立に開いた場合を再現）。
        let raw = [
            seg(t(18, 12), t(18, 22), .walking),
            seg(t(18, 22), t(19, 6), .stationary),
            seg(t(19, 6), t(19, 9), .walking),
        ]
        let now = t(19, 8) // 起きてしばらく経った時刻に見にきた想定

        let todayAsThe18th = ActivityDataService.estimateDaySegments(
            date: t(18, 0), now: now, rawSegments: raw, hourlySteps: [:], calendar: calendar
        )
        let todayAsThe19th = ActivityDataService.estimateDaySegments(
            date: t(19, 0), now: now, rawSegments: raw, hourlySteps: [:], calendar: calendar
        )

        // 18日ぶん(22:00〜24:00 = 2時間)と19日ぶん(00:00〜06:00 = 6時間)を合わせて、
        // 8時間まるごと「睡眠」になっているはず（どちらの呼び出しでも欠けない）。
        XCTAssertEqual(sleepingSeconds(todayAsThe18th), 2 * 3600, accuracy: 1, "前日として見たとき、22時〜24時が睡眠になっているはず")
        XCTAssertEqual(sleepingSeconds(todayAsThe19th), 6 * 3600, accuracy: 1, "今日として見たとき、0時〜6時が睡眠になっているはず")
    }

    // MARK: - 2. 「3時間未満はまだ睡眠と判定できない」は0時特有ではない（仕様上の制約）

    func testNotYetThreeHoursIsNotMidnightSpecific() {
        // 22:00(18日)に寝て、まだ2時間半しか経っていない0時30分(19日)に見た場合。
        let raw = [seg(t(18, 22), t(19, 5), .stationary)]
        let nowJustAfterMidnight = t(19, 0, 30)

        let asThe19th = ActivityDataService.estimateDaySegments(
            date: t(19, 0), now: nowJustAfterMidnight, rawSegments: raw, hourlySteps: [:], calendar: calendar
        )
        XCTAssertEqual(sleepingSeconds(asThe19th), 0, "まだ3時間経っていないので、0時を過ぎた直後でもまだ睡眠とは判定されない（仕様上の制約であり、0時をまたいだことによる不具合ではない）")

        // 参考: 日をまたいでいなくても、同じく「まだ3時間経っていない」時刻に見れば同様に判定されない
        // （寝た直後の18日 23:30に見た場合）。
        let sameNightBeforeMidnight = ActivityDataService.estimateDaySegments(
            date: t(18, 0), now: t(18, 23, 30), rawSegments: [seg(t(18, 22), t(18, 23, 30), .stationary)], hourlySteps: [:], calendar: calendar
        )
        XCTAssertEqual(sleepingSeconds(sameNightBeforeMidnight), 0, "日をまたいでいない23:30時点でも、3時間未満ならまだ睡眠とは判定されない（0時特有の問題ではないことの確認）")

        // 3時間5分経った時刻(1:05)に見れば、22:00〜1:05がまとめて睡眠と判定される
        // （日をまたいだ後も一貫して働くことの確認）。
        let afterThreeHours = ActivityDataService.estimateDaySegments(
            date: t(19, 0), now: t(19, 1, 5), rawSegments: raw, hourlySteps: [:], calendar: calendar
        )
        XCTAssertEqual(sleepingSeconds(afterThreeHours), 65 * 60, accuracy: 1, "3時間経過後は、0時〜現在までが睡眠と判定される")
    }

    // MARK: - 3. 修正前の挙動（対象日の前後を常に歩数0とみなす）が引き起こしていた食い違いの再現

    /// 修正前の`ActivityDataService.fetch`が使っていたのと同じ考え方の`stepsInHour`
    /// （対象日自身の0〜23時だけ実際の値を使い、それ以外は常に0とみなす）を再現するヘルパー。
    private func oldBuggyEstimate(date: Date, now: Date, rawSegments: [ActivitySegment], ownDayHourlySteps: [Int], calendar: Calendar) -> [ActivitySegment] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let end = min(endOfDay, now)
        let windowStart = startOfDay.addingTimeInterval(-12 * 3600)
        let windowEnd = min(endOfDay.addingTimeInterval(12 * 3600), now)
        let estimated = SleepEstimator.estimate(
            segments: rawSegments,
            windowStart: windowStart,
            windowEnd: windowEnd,
            stepsInHour: { hourStart in
                let index = Int(floor(hourStart.timeIntervalSince(startOfDay) / 3600))
                return (0..<24).contains(index) ? ownDayHourlySteps[index] : 0
            },
            calendar: calendar
        )
        return SleepEstimator.clip(estimated, from: startOfDay, to: end)
    }

    func testOldBehaviorWasInconsistentAtBoundary() {
        // シナリオ: 21:00(18日)〜22:00に静かにして、22:00〜24:00の2時間、実際には400歩/時間ぶん
        // 動いていた（CoreMotionの活動区間としては検出されず、静止/不明のまま記録された想定）。
        // その後0:00(19日)〜2:00にまた静かにする。
        // （2時間の中断にしているのは、2026-09-27の修正で中断の許容を60分に広げたため、
        // 1時間の中断だと中断を挟んでも「ひと続き」とみなされてしまい、この再現に使えなくなったため）
        // 21:00〜22:00 (1時間) と 0:00〜2:00 (2時間) は、それぞれ単独では3時間未満で睡眠にならない。
        // 22:00〜24:00の実際の歩数(400歩/時間、しきい値300歩を超える、かつ2時間で許容の60分を超える)を
        // 正しく踏まえれば、静かな時間がそこで途切れるので、どちらの日から見ても「睡眠なし」が正しい判定のはず。
        let raw = [seg(t(18, 21), t(19, 2), .stationary)] // CoreMotion上はずっと同じ区間（静止/不明扱い）
        let now = t(19, 8)

        var day18Hourly = [Int](repeating: 0, count: 24)
        day18Hourly[22] = 400 // 18日 22時台の実際の歩数
        day18Hourly[23] = 400 // 18日 23時台の実際の歩数
        let day19Hourly = [Int](repeating: 0, count: 24)

        // 18日を対象日として見たとき: 22・23時台は18日自身の配列にあるので、修正前でも正しく除外できていた。
        let oldAsThe18th = oldBuggyEstimate(date: t(18, 0), now: now, rawSegments: raw, ownDayHourlySteps: day18Hourly, calendar: calendar)
        XCTAssertEqual(sleepingSeconds(oldAsThe18th), 0, "18日自身から見れば、22・23時台の歩数が分かるので睡眠なしと正しく判定できていた")

        // 19日を対象日として見たとき（修正前）: 18日22・23時台は19日の配列の外なので常に0歩＝静かとみなされ、
        // 21:00〜2:00がひと続きの5時間の静けさとして誤って睡眠判定されてしまう。
        let oldAsThe19th = oldBuggyEstimate(date: t(19, 0), now: now, rawSegments: raw, ownDayHourlySteps: day19Hourly, calendar: calendar)
        XCTAssertEqual(sleepingSeconds(oldAsThe19th), 2 * 3600, accuracy: 1, "【修正前の再現】19日から見ると、18日22・23時台の実際の動きを見落として誤って睡眠と判定してしまっていた")

        // つまり修正前は、同じ夜なのに「18日から見ると睡眠なし」「19日から見ると0:00〜2:00が睡眠」という
        // 食い違いが起きていた（＝オーナー報告の「睡眠継続してても色が変わる」の一因になりうる動き）。
        XCTAssertNotEqual(sleepingSeconds(oldAsThe18th), sleepingSeconds(oldAsThe19th))
    }

    func testFetchLikeUsageIsConsistentAtBoundaryAfterFix() {
        // 修正後: `estimateDaySegments`には、対象日の前後の実際の歩数も渡す
        // （`ActivityDataService.fetch`が`queryStepsByHour`で問い合わせて渡すのと同じ形）。
        let raw = [seg(t(18, 21), t(19, 2), .stationary)]
        let now = t(19, 8)

        // 18日・19日どちらを対象日として見るときも、必要な歩数（18日22・23時台）は同じ実測値を渡す
        // （fetchが前後の窓ぶんも実際に問い合わせるようになったのと同じ状況）。
        let hourlySteps = hourlyStepsDict([(t(18, 22), 400), (t(18, 23), 400)])
        let asThe18th = ActivityDataService.estimateDaySegments(
            date: t(18, 0), now: now, rawSegments: raw, hourlySteps: hourlySteps, calendar: calendar
        )
        let asThe19th = ActivityDataService.estimateDaySegments(
            date: t(19, 0), now: now, rawSegments: raw, hourlySteps: hourlySteps, calendar: calendar
        )

        XCTAssertEqual(sleepingSeconds(asThe18th), 0, "18日から見ても睡眠なし")
        XCTAssertEqual(sleepingSeconds(asThe19th), 0, "19日から見ても睡眠なし（修正前は誤って2時間ぶん睡眠になっていた）")
        XCTAssertEqual(sleepingSeconds(asThe18th), sleepingSeconds(asThe19th), "どちらの日から見ても一致する")
    }

    // MARK: - 4. 実機再発「23時就寝・7時起床なのに0時以降が睡眠にならない」の調査・再現

    /// 仮説: 短い中断がなければ、そもそも問題なく動くはず。まず理想的な「一切中断のない8時間の
    /// 完全な静止」を`estimateDaySegments`に通して、コード自体は正しく動くことを確認する
    /// （これが通れば、実機での不具合は主にCoreMotionの実データのノイズ側の要因と考えられる）。
    func testCleanEightHourNightMatchesOwnerReportedTimes() {
        // 23:00(18日)就寝〜7:00(19日)起床、その間ずっと完全に静止（中断なし）という理想的なケース。
        let raw = [
            seg(t(18, 20), t(18, 23), .walking),
            seg(t(18, 23), t(19, 7), .stationary),
            seg(t(19, 7), t(19, 9), .walking),
        ]
        let now = t(19, 7) // 朝7時に確認した想定（オーナー報告どおりの時刻）

        let asThe18th = ActivityDataService.estimateDaySegments(
            date: t(18, 0), now: now, rawSegments: raw, hourlySteps: [:], calendar: calendar
        )
        let asThe19th = ActivityDataService.estimateDaySegments(
            date: t(19, 0), now: now, rawSegments: raw, hourlySteps: [:], calendar: calendar
        )
        // 18日ぶん(23:00〜24:00=1時間)と19日ぶん(0:00〜7:00=7時間)を合わせて8時間が睡眠になるはず。
        XCTAssertEqual(sleepingSeconds(asThe18th), 1 * 3600, accuracy: 1)
        XCTAssertEqual(sleepingSeconds(asThe19th), 7 * 3600, accuracy: 1, "0時以降の7時間がすべて睡眠になっているべき（実機不具合の再現確認）")
    }

    /// 仮説1の実データ再現: 中断なしなら問題ないが、実際のCoreMotionのように夜中に数十分だけ
    /// 別の種類に誤検知されると、修正前（中断許容15分）ではその前後が3時間未満に分断されて
    /// 「睡眠なし」になってしまっていた。`ActivityDataService`のwindow計算を通しても、
    /// この中断が正しく吸収されて一晩通して睡眠になることを確認する。
    func testRealisticOvernightNoiseAcrossMidnightStillBecomesSleep() {
        // 23:00(18日)就寝、0:20(19日)に30分だけ誤検知（乗り物）、1:00(19日)から7:00(19日)まで再び静止。
        let raw = [
            seg(t(18, 20), t(18, 23), .walking),
            seg(t(18, 23), t(19, 0, 20), .stationary),
            seg(t(19, 0, 20), t(19, 0, 50), .automotive),
            seg(t(19, 0, 50), t(19, 7), .stationary),
            seg(t(19, 7), t(19, 9), .walking),
        ]
        let now = t(19, 7)

        let asThe19th = ActivityDataService.estimateDaySegments(
            date: t(19, 0), now: now, rawSegments: raw, hourlySteps: [:], calendar: calendar
        )
        // 0時〜7時(7時間)から、30分の誤検知ぶんを除いた6時間30分が睡眠になるべき。
        XCTAssertEqual(sleepingSeconds(asThe19th), 6.5 * 3600, accuracy: 1, "0時以降、夜中の短い誤検知を挟んでも一晩通して睡眠になるべき（修正前は0時以降が睡眠にならなかった）")
    }

    // MARK: - hourIndex

    func testHourIndexIsStableAndMonotonic() {
        let a = ActivityDataService.hourIndex(for: t(18, 23, 0))
        let b = ActivityDataService.hourIndex(for: t(18, 23, 59))
        let c = ActivityDataService.hourIndex(for: t(19, 0, 0))
        XCTAssertEqual(a, b, "同じ時間帯（23:00〜23:59）は同じ番号になる")
        XCTAssertEqual(c, a + 1, "次の時間帯は+1になる")
    }
}
