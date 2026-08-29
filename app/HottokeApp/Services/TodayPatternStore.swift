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
            let url = documentsDirectory.appendingPathComponent(existing.videoFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                summary = existing
                videoURL = url
                return
            }
        }

        await generateToday(dateKey: key)
    }

    /// アプリを再度前面に戻したときなどに呼ぶ。日付が変わっていれば新しい日として生成し直し、
    /// 同じ日でも前回確定時から歩数などの活動量が変化していれば最新のデータで模様を更新する。
    /// 変化がなければ何もしない（動画の再書き出しは軽くない処理のため、無駄に毎回は行わない）。
    ///
    /// その日のうちにユーザーが手動でスタイルを選んでいた場合（existing.isManualStyleOverride）は、
    /// 活動量が変わって作り直す場合でも自動選択に戻さず、選んだスタイルを引き継ぐ
    /// （「アプリを開き直したら勝手にスタイルが変わった」という不満につながらないように）。
    func refreshIfStale() async {
        guard !isGenerating else { return }
        let key = dateKey(for: Date())

        guard let existing = summary else {
            await generateToday(dateKey: key)
            return
        }
        if existing.dateKey != key {
            // 日付が変わったので手動指定は引き継がず、自動選択にリセットする。
            await generateToday(dateKey: key)
            return
        }
        let data = await activityService.fetchToday()
        if hasMeaningfulChange(from: existing, to: data) {
            let carryOverStyle = existing.isManualStyleOverride ? PatternStyle(rawValue: existing.patternStyleRaw) : nil
            await generateToday(dateKey: key, prefetchedData: data, styleOverride: carryOverStyle)
        }
    }

    /// ユーザーが手動で更新ボタンを押したときに呼ぶ。変化の有無に関わらず必ず最新データで作り直す。
    /// その日のうちに手動でスタイルを選んでいた場合は、そのスタイルのまま作り直す
    /// （スタイル選択自体をやり直したい場合は`forceRefresh(styleOverride:)`を使う）。
    func forceRefresh() async {
        guard !isGenerating else { return }
        let key = dateKey(for: Date())
        let carryOverStyle: PatternStyle? = (summary?.dateKey == key && summary?.isManualStyleOverride == true)
            ? summary.flatMap { PatternStyle(rawValue: $0.patternStyleRaw) }
            : nil
        await generateToday(dateKey: key, styleOverride: carryOverStyle)
    }

    /// 「今日の模様」画面でユーザーが試しにスタイルを選んだ（または自動選択に戻した）ときに呼ぶ。
    /// - Parameter styleOverride: 明示的に使いたいスタイル。`nil`を渡すと自動選択（活動データから
    ///   決まるスタイル）に戻す。いずれの場合も最新データで作り直す。
    func forceRefresh(styleOverride: PatternStyle?) async {
        guard !isGenerating else { return }
        await generateToday(dateKey: dateKey(for: Date()), styleOverride: styleOverride)
    }

    private func hasMeaningfulChange(from existing: TodaySummary, to data: DailyActivityData) -> Bool {
        existing.stepCount != data.stepCount
            || existing.floorsAscended != data.floorsAscended
            || Int(data.totalActiveSeconds / 60) != existing.activeMinutes
    }

    /// - Parameter styleOverride: 明示的に使うスタイル。`nil`なら`data.dominantMovingKind`から
    ///   自動選択する（従来通り）。指定があれば、そのスタイルが「手動指定」として保存される。
    private func generateToday(dateKey key: String, prefetchedData: DailyActivityData? = nil, styleOverride: PatternStyle? = nil) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let data: DailyActivityData
        if let prefetchedData {
            data = prefetchedData
        } else {
            data = await activityService.fetchToday()
        }

        // 同じ日のうちに更新で再生成する場合でもファイル名を毎回変える（末尾に生成時刻を付与）。
        // ファイル名を固定すると再生成してもvideoURLが同じ値になり、TodayView側の
        // onChange(of: store.videoURL)が変化を検知できず動画プレイヤーが更新されないため。
        let previousFileName = summary?.dateKey == key ? summary?.videoFileName : nil
        let fileName = "today-\(key)-\(Int(Date().timeIntervalSince1970)).mp4"
        let outputURL = documentsDirectory.appendingPathComponent(fileName)

        do {
            try await exporter.exportDailyPattern(data: data, to: outputURL, styleOverride: styleOverride)
            let resolvedStyle = styleOverride ?? data.dominantMovingKind.map(PatternStyle.style(for:)) ?? .waves
            let newSummary = TodaySummary(
                dateKey: key,
                stepCount: data.stepCount,
                distanceMeters: data.distanceMeters,
                floorsAscended: data.floorsAscended,
                activeMinutes: Int(data.totalActiveSeconds / 60),
                dominantKindRaw: data.dominantMovingKind?.rawValue,
                videoFileName: fileName,
                patternStyleRaw: resolvedStyle.rawValue,
                isManualStyleOverride: styleOverride != nil
            )
            persist(summary: newSummary)
            summary = newSummary
            videoURL = outputURL
            if let previousFileName {
                try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(previousFileName))
            }
        } catch {
            errorMessage = "模様の生成に失敗しました: \(error.localizedDescription)"
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
