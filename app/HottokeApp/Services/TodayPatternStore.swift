import Foundation

/// 「今日の模様」の確定・永続化を管理する。
/// 当初はdocs/02-spec.md 7章の決定通り「1日1回だけ生成・確定」だったが、
/// 実際に使うと「時間が経って活動したのに更新されない」という不満につながったため、
/// アプリを開き直した際に前回確定時から活動量（歩数など）が変化していれば
/// 自動で作り直すよう変更した（refreshIfStale）。加えて手動での更新も可能にした（forceRefresh）。
///
/// 実機フィードバック対応: 手動モードのように「今日の模様」でも試しにスタイルを変えられるように
/// なったため、実際に使われたスタイル（patternStyleRaw）と、それがユーザーによる明示的な指定か
/// どうか（isManualStyleOverride）も保存する。手動指定の場合はその日のうちは自動選択に
/// 上書きされないようにするため（TodayPatternStore.refreshIfStale/forceRefresh参照）。
struct TodaySummary: Codable, Equatable {
    let dateKey: String
    let stepCount: Int
    let distanceMeters: Double
    let floorsAscended: Int
    let activeMinutes: Int
    let dominantKindRaw: String?
    let videoFileName: String
    let patternStyleRaw: String
    let isManualStyleOverride: Bool
    /// その日のうちにスタイルを切り替えて既に生成済みの動画ファイル名のキャッシュ
    /// （PatternStyle.rawValue → ファイル名）。実機フィードバック対応: スタイルを切り替える
    /// たびに毎回フルで動画を作り直すと待ちが長いという不満を受けて、同じスタイルに
    /// 戻ってきたときは再生成せずこのキャッシュのファイルを使い回すようにした
    /// （TodayPatternStore.generateToday参照）。
    let styleVideoFileNames: [String: String]

    init(
        dateKey: String,
        stepCount: Int,
        distanceMeters: Double,
        floorsAscended: Int,
        activeMinutes: Int,
        dominantKindRaw: String?,
        videoFileName: String,
        patternStyleRaw: String,
        isManualStyleOverride: Bool,
        styleVideoFileNames: [String: String]
    ) {
        self.dateKey = dateKey
        self.stepCount = stepCount
        self.distanceMeters = distanceMeters
        self.floorsAscended = floorsAscended
        self.activeMinutes = activeMinutes
        self.dominantKindRaw = dominantKindRaw
        self.videoFileName = videoFileName
        self.patternStyleRaw = patternStyleRaw
        self.isManualStyleOverride = isManualStyleOverride
        self.styleVideoFileNames = styleVideoFileNames
    }

    private enum CodingKeys: String, CodingKey {
        case dateKey, stepCount, distanceMeters, floorsAscended, activeMinutes
        case dominantKindRaw, videoFileName, patternStyleRaw, isManualStyleOverride
        case styleVideoFileNames
    }

    // styleVideoFileNamesはこの機能追加より前に永続化された古いJSONには存在しないため、
    // 欠けていても失敗せず空の辞書として読み込めるようにする（decodeIfPresent）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try container.decode(String.self, forKey: .dateKey)
        stepCount = try container.decode(Int.self, forKey: .stepCount)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        floorsAscended = try container.decode(Int.self, forKey: .floorsAscended)
        activeMinutes = try container.decode(Int.self, forKey: .activeMinutes)
        dominantKindRaw = try container.decodeIfPresent(String.self, forKey: .dominantKindRaw)
        videoFileName = try container.decode(String.self, forKey: .videoFileName)
        patternStyleRaw = try container.decode(String.self, forKey: .patternStyleRaw)
        isManualStyleOverride = try container.decode(Bool.self, forKey: .isManualStyleOverride)
        styleVideoFileNames = try container.decodeIfPresent([String: String].self, forKey: .styleVideoFileNames) ?? [:]
    }
}

@MainActor
final class TodayPatternStore: ObservableObject {
    @Published private(set) var summary: TodaySummary?
    @Published private(set) var videoURL: URL?
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?

    private let activityService = ActivityDataService()
    private let exporter = KaleidoscopeVideoExporter()

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var metadataURL: URL {
        documentsDirectory.appendingPathComponent("today-summary.json")
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// 今日すでに確定済みの模様があればそれを読み込み、なければ新しく生成する。
    func loadOrGenerateTodayIfNeeded() async {
        guard !isGenerating else { return }
        let key = dateKey(for: Date())

        if let existing = loadPersistedSummary(), existing.dateKey == key {
            summary = existing
            let url = documentsDirectory.appendingPathComponent(existing.videoFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                videoURL = url
                return
            }
        }

        await generateToday(dateKey: key, clearStyleCache: true)
    }

    /// アプリを再度前面に戻したときなどに呼ぶ。日付が変わっていれば新しい日として生成し直し、
    /// 同じ日でも前回確定時から歩数などの活動量が変化していれば最新のデータで模様を更新する。
    /// 変化がなければ何もしない（動画の再書き出しは軽くない処理のため、無駄に毎回は行わない）。
    ///
    /// その日のうちにユーザーが手動でスタイルを選んでいた場合（existing.isManualStyleOverride）は、
    /// 活動量が変わって作り直す場合でも自動選択に戻さず、選んだスタイルを引き継ぐ
    /// （「アプリを開き直したら勝手にスタイルが変わった」という不満につながらないように）。
    ///
    /// 活動データが変化して作り直す場合、その日のうちに他のスタイルで生成済みのキャッシュ動画は
    /// 古いデータのままになってしまうため、キャッシュは全部クリアして選択中のスタイルだけ
    /// 最新データで再生成する（他のスタイルは、ユーザーが再度選び直した時点で作り直される）。
    func refreshIfStale() async {
        guard !isGenerating else { return }
        let key = dateKey(for: Date())

        guard let existing = summary else {
            await generateToday(dateKey: key, clearStyleCache: true)
            return
        }
        if existing.dateKey != key {
            // 日付が変わったので手動指定は引き継がず、自動選択にリセットする。
            await generateToday(dateKey: key, clearStyleCache: true)
            return
        }
        let data = await activityService.fetchToday()
        if hasMeaningfulChange(from: existing, to: data) {
            let carryOverStyle = existing.isManualStyleOverride ? PatternStyle(rawValue: existing.patternStyleRaw) : nil
            await generateToday(dateKey: key, prefetchedData: data, styleOverride: carryOverStyle, clearStyleCache: true)
        }
    }

    /// ユーザーが手動で更新ボタンを押したときに呼ぶ。変化の有無に関わらず必ず最新データで作り直す。
    /// その日のうちに手動でスタイルを選んでいた場合は、そのスタイルのまま作り直す
    /// （スタイル選択自体をやり直したい場合は`forceRefresh(styleOverride:)`を使う）。
    /// 「必ず作り直す」操作のため、他のスタイルのキャッシュ動画も古いデータのままになるのを
    /// 避けるべくキャッシュは全部クリアし、選択中のスタイルだけ作り直す。
    func forceRefresh() async {
        guard !isGenerating else { return }
        let key = dateKey(for: Date())
        let carryOverStyle: PatternStyle? = (summary?.dateKey == key && summary?.isManualStyleOverride == true)
            ? summary.flatMap { PatternStyle(rawValue: $0.patternStyleRaw) }
            : nil
        await generateToday(dateKey: key, styleOverride: carryOverStyle, clearStyleCache: true)
    }

    /// 「今日の模様」画面でユーザーが試しにスタイルを選んだ（または自動選択に戻した）ときに呼ぶ。
    /// - Parameter styleOverride: 明示的に使いたいスタイル。`nil`を渡すと自動選択（活動データから
    ///   決まるスタイル）に戻す。
    ///
    /// 実機フィードバック対応: 試しにスタイルを見比べる操作のたびに毎回フルで動画を作り直すと
    /// 待ちが長いため、その日のうちに同じスタイルで生成済みの動画があり、かつ生成時から活動量が
    /// 変化していなければ再生成せずそのファイルをそのまま使う（generateToday内のキャッシュ判定）。
    /// まだ生成していないスタイルの場合はこれまで通り生成し、その結果をキャッシュに追加する
    /// （他のスタイルの既存キャッシュは消さずに残す）。
    func forceRefresh(styleOverride: PatternStyle?) async {
        guard !isGenerating else { return }
        await generateToday(dateKey: dateKey(for: Date()), styleOverride: styleOverride, clearStyleCache: false)
    }

    private func hasMeaningfulChange(from existing: TodaySummary, to data: DailyActivityData) -> Bool {
        existing.stepCount != data.stepCount
            || existing.floorsAscended != data.floorsAscended
            || Int(data.totalActiveSeconds / 60) != existing.activeMinutes
    }

    /// - Parameters:
    ///   - styleOverride: 明示的に使うスタイル。`nil`なら`data.dominantMovingKind`から
    ///     自動選択する（従来通り）。指定があれば、そのスタイルが「手動指定」として保存される。
    ///   - clearStyleCache: `true`の場合、その日のうちに生成済みの他スタイルのキャッシュ動画は
    ///     すべて破棄し（ファイルも削除し）、今回生成するスタイルだけを残す。データが変わった
    ///     可能性がある更新（refreshIfStale/forceRefresh）で使う。`false`の場合は既存のキャッシュを
    ///     維持したまま、指定スタイルがキャッシュ済みならそれを再利用し、未生成ならキャッシュに
    ///     追加する（スタイルを試しに切り替える操作 forceRefresh(styleOverride:) で使う）。
    private func generateToday(
        dateKey key: String,
        prefetchedData: DailyActivityData? = nil,
        styleOverride: PatternStyle? = nil,
        clearStyleCache: Bool
    ) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let data: DailyActivityData
        if let prefetchedData {
            data = prefetchedData
        } else {
            data = await activityService.fetchToday()
        }

        let resolvedStyle = styleOverride ?? data.dominantMovingKind.map(PatternStyle.style(for:)) ?? .waves
        let previousSummary = summary

        // キャッシュ利用判定: 全部作り直す操作ではなく、同じ日で、かつ前回生成時から活動データに
        // 意味のある変化がなく、そのスタイルの動画がすでに生成済み（ファイルも実在）なら、
        // 再生成せずそのファイルをそのまま使い回す。
        if !clearStyleCache,
           let previousSummary,
           previousSummary.dateKey == key,
           !hasMeaningfulChange(from: previousSummary, to: data),
           let cachedFileName = previousSummary.styleVideoFileNames[resolvedStyle.rawValue] {
            let cachedURL = documentsDirectory.appendingPathComponent(cachedFileName)
            if FileManager.default.fileExists(atPath: cachedURL.path) {
                let newSummary = TodaySummary(
                    dateKey: key,
                    stepCount: previousSummary.stepCount,
                    distanceMeters: previousSummary.distanceMeters,
                    floorsAscended: previousSummary.floorsAscended,
                    activeMinutes: previousSummary.activeMinutes,
                    dominantKindRaw: previousSummary.dominantKindRaw,
                    videoFileName: cachedFileName,
                    patternStyleRaw: resolvedStyle.rawValue,
                    isManualStyleOverride: styleOverride != nil,
                    styleVideoFileNames: previousSummary.styleVideoFileNames
                )
                persist(summary: newSummary)
                summary = newSummary
                videoURL = cachedURL
                return
            }
        }

        // ここからは実際に動画を生成する。日付が変わった場合や、全部作り直す操作の場合は、
        // 不要になる古いキャッシュ動画をディスクに残さないよう先に削除しておく
        // （同じ日でキャッシュを維持する場合＝スタイル切り替えでの新規生成は、他スタイルの
        // 既存ファイルは消さずそのまま残す）。
        if let previousSummary, previousSummary.dateKey != key || clearStyleCache {
            deleteAllCachedFiles(for: previousSummary)
        }

        // 動画ファイル名にスタイルを含める（同じスタイルへのキャッシュ判定に使うため）。
        // 生成時刻も含めているのは、同じスタイルを再生成した場合でもファイル名を変えることで
        // videoURLの値が変わり、TodayView側のonChange(of: store.videoURL)で動画プレイヤーの
        // 更新を検知できるようにするため。
        let fileName = "today-\(key)-\(resolvedStyle.rawValue)-\(Int(Date().timeIntervalSince1970)).mp4"
        let outputURL = documentsDirectory.appendingPathComponent(fileName)

        do {
            try await exporter.exportDailyPattern(data: data, to: outputURL, styleOverride: styleOverride)

            var styleCache: [String: String]
            if clearStyleCache || previousSummary?.dateKey != key {
                styleCache = [:]
            } else {
                styleCache = previousSummary?.styleVideoFileNames ?? [:]
            }
            styleCache[resolvedStyle.rawValue] = fileName

            let newSummary = TodaySummary(
                dateKey: key,
                stepCount: data.stepCount,
                distanceMeters: data.distanceMeters,
                floorsAscended: data.floorsAscended,
                activeMinutes: Int(data.totalActiveSeconds / 60),
                dominantKindRaw: data.dominantMovingKind?.rawValue,
                videoFileName: fileName,
                patternStyleRaw: resolvedStyle.rawValue,
                isManualStyleOverride: styleOverride != nil,
                styleVideoFileNames: styleCache
            )
            persist(summary: newSummary)
            summary = newSummary
            videoURL = outputURL
        } catch {
            errorMessage = "模様の生成に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 指定したサマリーが参照している動画ファイル（現在表示中のもの＋スタイルキャッシュ全部）を
    /// ディスクから削除する。日付が変わったときや、キャッシュを全部クリアするときに使う
    /// （ストレージを圧迫しないようにするため）。
    private func deleteAllCachedFiles(for summary: TodaySummary) {
        var fileNames = Set(summary.styleVideoFileNames.values)
        fileNames.insert(summary.videoFileName)
        for fileName in fileNames {
            try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(fileName))
        }
    }

    private func persist(summary: TodaySummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func loadPersistedSummary() -> TodaySummary? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(TodaySummary.self, from: data)
    }
}
