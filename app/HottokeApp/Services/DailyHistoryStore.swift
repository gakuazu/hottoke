import Foundation

/// 日ごとの要約（5分スライスごとの種類別の秒数と、1時間ごとの歩数）を端末内に保存する。
///
/// iPhoneが保持する歩数・活動の履歴は約7日分しかないため、アプリを開くたびに直近7日分を取り直して
/// ここに保存しておく。1ヶ月の積算や、7日より古い日のアーカイブは、この保存データから作る。
/// つまり、保存が始まった日から貯まっていく（それ以前の日は遡れない）。
/// 保存先は Application Support の `HottokeHistory/daily-history.json`（外部へは送信しない）。
final class DailyHistoryStore: ObservableObject {
    static let shared = DailyHistoryStore()
    /// アプリを開くたびに取り直す日数（今日を含む）。
    static let syncDays = 7

    /// 睡眠推定の日境界バグ修正（2026-09-26、`ActivityDataService`が対象日の前後の実際の歩数を
    /// 使うようにした変更）を、すでに保存済みの直近の日にも反映するための版数。この値を上げると、
    /// 次に同期したときだけ、直近`syncDays`日ぶんを「保存済み・完了扱い」でも関係なく
    /// もう一度取り直す（＝古い誤った判定のまま端末に残ってしまうのを防ぐ）。
    /// 対象は端末にCoreMotionの生データがまだ残っていそうな直近の日に限られる
    /// （それより古い日は生データ自体が失われている可能性が高く、直しようがない）。
    static let resyncVersion = 1
    /// 上記の版数をどこまで適用したかを覚えておくUserDefaultsのキー。
    static let resyncVersionDefaultsKey = "dailyHistoryResyncVersion"

    @Published private(set) var records: [String: DailyRingSlices]
    /// 保存のたびに増える番号（画面の再読み込みのきっかけに使う）。
    @Published private(set) var revision = 0

    private let fileURL: URL
    private let defaults: UserDefaults
    private var isSyncing = false

    /// `directory`を渡すとそこに保存する（テスト用）。省略時はApplication Support。
    /// `defaults`も同様にテスト用（省略時は`UserDefaults.standard`）。
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("daily-history.json")
        records = Self.load(from: fileURL)
        self.defaults = defaults
    }

    /// まだ今回の睡眠推定バグ修正ぶんの取り直しをしていないか（一度きりの再同期が必要か）。
    var needsOneTimeResync: Bool {
        defaults.integer(forKey: Self.resyncVersionDefaultsKey) < Self.resyncVersion
    }

    private func markOneTimeResyncDone() {
        defaults.set(Self.resyncVersion, forKey: Self.resyncVersionDefaultsKey)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HottokeHistory", isDirectory: true)
    }

    // MARK: - 読み出し

    func record(forKey key: String) -> DailyRingSlices? { records[key] }

    func record(for date: Date, calendar: Calendar = .current) -> DailyRingSlices? {
        records[DailyRingSlices.dateKey(for: date, calendar: calendar)]
    }

    /// データのある保存済みの日数。
    var savedDayCount: Int { records.values.filter { $0.hasAnyData }.count }

    /// 保存が始まった日（最も古い日）。
    var oldestDateKey: String? { records.keys.min() }

    /// `endingAt`を含む直近`days`日ぶんの保存済みの記録（古い順）。
    func recentRecords(days: Int, endingAt now: Date, calendar: Calendar = .current) -> [DailyRingSlices] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let startKey = DailyRingSlices.dateKey(for: start, calendar: calendar)
        let endKey = DailyRingSlices.dateKey(for: today, calendar: calendar)
        return records.values
            .filter { $0.dateKey >= startKey && $0.dateKey <= endKey && $0.hasAnyData }
            .sorted { $0.dateKey < $1.dateKey }
    }

    // MARK: - 保存

    /// 1日ぶんを保存（同じ日があれば置き換える）。データが空のものは保存しない（良い記録を空で上書きしない）。
    func save(_ slices: DailyRingSlices) {
        guard slices.hasAnyData else { return }
        records[slices.dateKey] = slices
        revision += 1
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [String: DailyRingSlices] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: DailyRingSlices].self, from: data)) ?? [:]
    }

    // MARK: - 直近の日を取り直して保存

    /// 取り直す必要がある日か。今日と昨日は毎回（昨日は、今朝の睡眠が増えると夜の分の推定が変わるため）。
    /// まだ`resyncVersion`ぶんの取り直しが済んでいなければ、直近`syncDays`日ぶんはすべて対象。
    /// それ以外は、まだ保存がない日、または途中の状態で保存した日だけ。
    func needsRefresh(offset: Int, day: Date, calendar: Calendar = .current) -> Bool {
        if offset <= 1 { return true }
        if needsOneTimeResync { return true }
        guard let record = record(for: day, calendar: calendar) else { return true }
        return !record.isComplete
    }

    /// 直近7日ぶんを端末の履歴から取り直して保存する。今日は呼び出し側が保存する場合は`includeToday`をfalseに。
    /// まだ睡眠推定バグ修正の取り直しが済んでいなければ、直近7日ぶんをこの1回でまとめて取り直し、
    /// 最後まで実行できたら「済み」の印を付ける（次回以降はいつもどおり必要な日だけ取り直す）。
    @MainActor
    func syncRecentDays(service: ActivityDataService, now: Date = Date(), includeToday: Bool = true) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let wasResyncNeeded = needsOneTimeResync
        var reachedTheEnd = true
        for offset in 0..<Self.syncDays {
            if offset == 0 && !includeToday { continue }
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                reachedTheEnd = false
                continue
            }
            guard needsRefresh(offset: offset, day: day, calendar: calendar) else { continue }
            let data = await service.fetch(for: day, includeHourlySteps: true)
            save(DailyRingLayout.makeSlices(data: data, now: now, calendar: calendar))
        }
        if wasResyncNeeded && reachedTheEnd {
            markOneTimeResyncDone()
        }
    }
}
