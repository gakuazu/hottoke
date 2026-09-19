import SwiftUI

/// 「1日の輪」（点描リング）の画像を作って持っておく。
/// ・`date`がnil = 今日。開いたとき／前面に戻したとき／更新ボタンで最新の活動データを取り直して描き直す。
///   プロモードでは、期間（今日／1週間／1ヶ月）の切り替えと、普段との比較もできる。
/// ・`date`が過去日 = アーカイブ。その日の24時間ぶんを描く。端末の履歴が残っていない古い日は、
///   保存済みの要約（DailyHistoryStore）から描き、それもなければ「データなし」を示す。
@MainActor
final class DailyRingStore: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var stepCount: Int = 0
    /// 画像を作れない理由（過去日で端末にデータが残っていない等）。nilなら画像あり（または準備中）。
    @Published private(set) var noDataMessage: String?
    /// プロ機能がロックされているときの案内など、一時的なお知らせ。
    @Published private(set) var notice: String?
    /// 積算・比較の状況の説明（保存済み◯日分の平均など）。
    @Published private(set) var summaryNote: String?
    @Published private(set) var period: RingPeriod = .today
    @Published private(set) var compare = false

    let date: Date?
    var isToday: Bool { date == nil }

    private(set) var proEnabled = ProAccess.defaultEnabled
    private(set) var themeRaw = RingTheme.standard.rawValue
    var theme: RingTheme { RingTheme.effective(rawValue: themeRaw, proEnabled: proEnabled) }

    private let service = ActivityDataService()
    private var baseSlices: DailyRingSlices?
    private var built: Built?
    private var generation = 0

    /// 直近に描いた内容（別のサイズで書き出し直すために持っておく）。
    private struct Built {
        var density: DailyRingDensity
        var date: Date
        var caption: RingCaption?
        var ghost: DailyRingDensity?
    }

    init(date: Date? = nil) {
        self.date = date
    }

    /// 端末の画面のピクセル数（壁紙サイズの書き出しに使う）。
    static var screenPixels: CGSize {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let b = scene?.screen.nativeBounds ?? CGRect(x: 0, y: 0, width: 1179, height: 2556)
        return CGSize(width: b.width, height: b.height)
    }

    // MARK: - 設定の反映

    /// プロモードのオン・オフと配色テーマの設定を反映する。変わったら描き直す。
    func configure(proEnabled: Bool, themeRaw: String) {
        let changed = proEnabled != self.proEnabled || themeRaw != self.themeRaw
        self.proEnabled = proEnabled
        self.themeRaw = themeRaw
        if !ProAccess.isUnlocked(.aggregation, enabled: proEnabled) && period != .today { period = .today }
        if !ProAccess.isUnlocked(.comparison, enabled: proEnabled) && compare { compare = false }
        if changed && baseSlices != nil { Task { await rebuild() } }
    }

    func showLocked(_ feature: ProFeature) {
        notice = ProAccess.lockedMessage(for: feature)
    }

    func selectPeriod(_ newPeriod: RingPeriod) {
        guard isToday, newPeriod != period else { return }
        if newPeriod != .today && !ProAccess.isUnlocked(.aggregation, enabled: proEnabled) {
            showLocked(.aggregation)
            return
        }
        notice = nil
        period = newPeriod
        Task { await rebuild() }
    }

    func setCompare(_ on: Bool) {
        guard isToday else { return }
        if on && !ProAccess.isUnlocked(.comparison, enabled: proEnabled) {
            showLocked(.comparison)
            return
        }
        notice = nil
        compare = on
        Task { await rebuild() }
    }

    // MARK: - 取得と描画

    /// 最新データを取得して描き直す。すでに取得中なら何もしない。
    /// ・取得した日ごとの要約は、端末内の履歴（DailyHistoryStore）に保存する。
    /// ・端末の履歴が残っていない古い日は、保存済みの要約から描く（なければ「データなし」）。
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        noDataMessage = nil
        defer { isLoading = false }

        let now = Date()
        let calendar = Calendar.current
        let target = date ?? now
        let history = DailyHistoryStore.shared

        var slices: DailyRingSlices?
        if isToday || DailyRingLayout.isWithinRetention(date: target, now: now) {
            let data = await service.fetch(for: target, includeHourlySteps: true)
            let fresh = DailyRingLayout.makeSlices(data: data, now: now, calendar: calendar)
            if fresh.hasAnyData {
                history.save(fresh)
                slices = fresh
            } else if let saved = history.record(for: target) {
                slices = saved
            } else if isToday {
                slices = fresh // 今日はまだデータがなくても、空の輪と現在時刻の目印を出す
            }
        } else {
            slices = history.record(for: target)
        }

        guard let slices else {
            baseSlices = nil
            image = nil
            stepCount = 0
            lastUpdated = now
            noDataMessage = DailyRingLayout.isWithinRetention(date: target, now: now)
                ? "この日の歩数・活動のデータがありません。"
                : "この日のデータは端末に残っていません。iPhoneが保持している歩数・活動の履歴は、おおむね直近1週間ほどです（このアプリは、開いた日から日ごとの要約を保存しています）。"
            return
        }

        baseSlices = slices
        lastUpdated = now
        await rebuild()

        // 今日を開いたときは、ついでに直近の他の日も取り直して保存する（アーカイブ・積算のため）。
        if isToday {
            let service = self.service
            Task { @MainActor in
                await history.syncRecentDays(service: service, includeToday: false)
                if self.period != .today || self.compare { await self.rebuild() }
            }
        }
    }

    /// 取得済みのデータから、いまの設定（期間・比較・テーマ）で描き直す。
    func rebuild() async {
        guard let slices = baseSlices else { return }
        generation += 1
        let gen = generation
        let now = Date()
        let calendar = Calendar.current
        let history = DailyHistoryStore.shared
        let period = self.period
        let compareOn = compare && isToday
        let day = calendar.startOfDay(for: date ?? now)
        var options = RingRenderOptions(canvas: CGSize(width: 1080, height: 1080))
        options.theme = theme

        var records: [DailyRingSlices] = []
        var ghostRecords: [DailyRingSlices] = []
        var caption: RingCaption?
        var note: String?
        var steps = slices.totalSteps
        var renderDate = day

        if period == .today {
            if compareOn {
                ghostRecords = history.recentRecords(days: 30, endingAt: now, calendar: calendar)
                    .filter { $0.dateKey != slices.dateKey && $0.isComplete }
                note = ghostRecords.isEmpty
                    ? "普段（過去の日の平均）を作るデータが、まだ保存されていません。"
                    : "淡い点は「普段」（保存済みの過去\(ghostRecords.count)日の平均）です。"
            }
        } else {
            // 期間の積算: 今日の最新の記録を差し替えて、直近の期間の記録を集める。
            records = history.recentRecords(days: period.days, endingAt: now, calendar: calendar).filter { $0.dateKey != slices.dateKey }
            records.append(slices)
            records.sort { $0.dateKey < $1.dateKey }
            steps = records.reduce(0) { $0 + $1.totalSteps }
            renderDate = calendar.date(byAdding: .day, value: -(period.days - 1), to: day) ?? day
            caption = RingCaption(title: "\(period.displayName)の積算", subtitle: "保存済み \(records.count)日分")
            note = records.count < period.days
                ? "保存済み\(records.count)日分の平均です（\(period.days)日のうち。保存を始めた日から貯まります）。"
                : "保存済み\(records.count)日分の平均です。"
        }

        let renderRecords = records
        let renderGhost = ghostRecords
        let renderCaption = caption
        let renderDay = renderDate
        let baseOptions = options
        let result = await Task.detached(priority: .userInitiated) { () -> (UIImage, Built) in
            let density: DailyRingDensity
            if period == .today {
                density = DailyRingLayout.makeDensity(slices: slices)
            } else {
                density = DailyRingLayout.aggregate(renderRecords)
            }
            let ghost: DailyRingDensity? = renderGhost.isEmpty ? nil : DailyRingLayout.aggregate(renderGhost)
            var renderOptions = baseOptions
            renderOptions.ghost = ghost
            renderOptions.caption = renderCaption
            let image = DailyRingRenderer.render(density: density, date: renderDay, options: renderOptions)
            return (image, Built(density: density, date: renderDay, caption: renderCaption, ghost: ghost))
        }.value

        guard gen == generation else { return }
        image = result.0
        built = result.1
        stepCount = steps
        summaryNote = note
    }

    // MARK: - 書き出し

    /// いま表示している内容を、指定のサイズで描き直して返す（標準・高解像度・壁紙）。
    func exportImage(size: RingExportSize) async -> UIImage? {
        guard let built else { return nil }
        let canvas = size.canvas(screenPixels: Self.screenPixels)
        var options = RingRenderOptions(canvas: canvas)
        options.theme = theme
        options.ghost = built.ghost
        if size == .wallpaper {
            options.chrome = .art
            // 壁紙は輪を大きく（画面の幅いっぱいに）描く。
            options.ringSide = min(canvas.width, canvas.height) * 1.35
            options.ringCenter = CGPoint(x: canvas.width / 2, y: canvas.height * 0.54)
        } else {
            options.caption = built.caption
        }
        let density = built.density
        let day = built.date
        let renderOptions = options
        return await Task.detached(priority: .userInitiated) {
            DailyRingRenderer.render(density: density, date: day, options: renderOptions)
        }.value
    }
}

/// 画像・期間の切り替え・保存ボタン・更新ボタン・読み方の凡例。「今日」タブとアーカイブの日付シートで共通。
struct DailyRingPanel: View {
    @ObservedObject var store: DailyRingStore
    let proEnabled: Bool
    @State private var showSavedBanner = false
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isToday {
                    periodPicker
                        .padding(.horizontal, 16)
                }

                ringArea
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)

                statusLine

                if let note = store.summaryNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                if let notice = store.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if store.isToday && store.period == .today {
                    let comparisonUnlocked = ProAccess.isUnlocked(.comparison, enabled: proEnabled)
                    Toggle(isOn: Binding(get: { store.compare }, set: { store.setCompare($0) })) {
                        Label(comparisonUnlocked ? "普段と比べる" : "普段と比べる（プロ機能）",
                              systemImage: comparisonUnlocked ? "square.on.square" : "lock")
                    }
                    .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    Menu {
                        ForEach(RingExportSize.allCases) { size in
                            let locked = size.requiresPro && !ProAccess.isUnlocked(.highQualityExport, enabled: proEnabled)
                            Button {
                                Task { await save(size) }
                            } label: {
                                Label(locked ? "\(size.displayName)（プロ機能）" : size.displayName, systemImage: locked ? "lock" : "square.and.arrow.down")
                            }
                        }
                    } label: {
                        Label("カメラロールに保存", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.image == nil || store.isLoading || isSaving)

                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("最新のデータで更新", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isLoading)
                }
                .padding(.horizontal, 16)

                if showSavedBanner {
                    Text("カメラロールに保存しました")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                legend
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
    }

    private var periodPicker: some View {
        Picker("期間", selection: Binding(get: { store.period }, set: { store.selectPeriod($0) })) {
            ForEach(RingPeriod.allCases) { period in
                let locked = period != .today && !ProAccess.isUnlocked(.aggregation, enabled: proEnabled)
                Text(locked ? "\(period.displayName) 🔒" : period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var ringArea: some View {
        ZStack {
            Color.black
            if let image = store.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let message = store.noDataMessage {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.title)
                    Text("データなし")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(24)
            } else if !store.isLoading {
                Text("1日の輪を準備中です")
                    .foregroundStyle(.white.opacity(0.6))
            }
            if store.isLoading {
                ZStack {
                    Color.black.opacity(store.image == nil ? 0 : 0.55)
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("最新のデータを取得して描いています…")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isLoading)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let updated = store.lastUpdated, store.image != nil {
            VStack(spacing: 2) {
                Text("\(store.isToday ? store.period.displayName : "この日")の歩数: \(store.stepCount)歩")
                    .font(.headline)
                if store.isToday {
                    Text("\(Self.timeFormatter.string(from: updated)) 時点のデータ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    /// 読み方の凡例（控えめに）。
    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("この輪の読み方")
                .font(.subheadline.bold())
            legendLine(icon: "clock", text: "ぐるっと一周が24時間です。真上が0時、右が6時、真下が12時、左が18時。今日は現在時刻までを描き、これからの時間は空のまま残ります（点線が今の時刻）。")
            legendLine(icon: "arrow.up.left.and.arrow.down.right", text: "中心から外へ行くほど、その時刻の活動が活発だったことを表します（歩数が多いほど遠くまで広がり、静かな時間は中心の近くにとどまります）。うっすらした点線の円は、内側から弱・中・強の目安です。")
            legendLine(icon: "circle.dotted", text: "点の詰まりは、その時刻にその状態だった時間の長さです。歩行・ランニングは歩数が多いほど濃くなります。")
            legendLine(icon: "paintpalette", text: "色は活動の種類です。切り替わりの前後20分ほどは、色がなめらかに混ざります。1週間・1ヶ月の積算では、その時刻に各活動をしていた日の割合で色が混ざります。")

            Text("色 = 活動の種類")
                .font(.footnote.bold())
                .padding(.top, 4)
            ForEach(DailyRingLayout.kindOrder, id: \.self) { kind in
                let c = store.theme.color(for: kind)
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: c.r, green: c.g, blue: c.b))
                        .frame(width: 12, height: 12)
                        .frame(width: 22)
                    Text(kind.displayName)
                        .font(.footnote)
                }
            }
            Text("自転車は1分90歩、乗り物（電車・バス・車）は1分30歩の歩数に換算して強さを決めています。静止と睡眠は、長い時間でも中心近くの小さな円になります。睡眠は、夜間の長い静止から推定しています。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.10)))
    }

    private func legendLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func save(_ size: RingExportSize) async {
        if size.requiresPro && !ProAccess.isUnlocked(.highQualityExport, enabled: proEnabled) {
            saveErrorMessage = ProAccess.lockedMessage(for: .highQualityExport)
            return
        }
        isSaving = true
        defer { isSaving = false }
        guard let image = await store.exportImage(size: size) else { return }
        do {
            try await PhotoLibrarySaver.saveImage(image)
            saveErrorMessage = nil
            showSavedBanner = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showSavedBanner = false
        } catch {
            saveErrorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}

/// 「今日」タブ。今日の点描リングを表示する。画面を開いたとき（別のタブから戻ったときも含む）・
/// アプリを前面に戻したとき・更新ボタンを押したときに、最新の活動データで描き直す。
struct DailyRingView: View {
    @StateObject private var store = DailyRingStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ProAccess.storageKey) private var proEnabled = ProAccess.defaultEnabled
    @AppStorage(RingTheme.storageKey) private var themeRaw = RingTheme.standard.rawValue
    @State private var showReport = false

    var body: some View {
        NavigationStack {
            DailyRingPanel(store: store, proEnabled: proEnabled)
                .navigationTitle("今日")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        themeMenu
                        Button {
                            if ProAccess.isUnlocked(.report, enabled: proEnabled) {
                                showReport = true
                            } else {
                                store.showLocked(.report)
                            }
                        } label: {
                            Image(systemName: "doc.richtext")
                        }
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.isLoading)
                    }
                }
                .task {
                    store.configure(proEnabled: proEnabled, themeRaw: themeRaw)
                    await store.refresh()
                }
                .onChange(of: proEnabled) { _, _ in store.configure(proEnabled: proEnabled, themeRaw: themeRaw) }
                .onChange(of: themeRaw) { _, _ in store.configure(proEnabled: proEnabled, themeRaw: themeRaw) }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { await store.refresh() }
                }
                .sheet(isPresented: $showReport) {
                    ReportView(proEnabled: proEnabled, theme: store.theme)
                }
        }
    }

    /// 配色テーマの切り替え（プロ機能）。
    private var themeMenu: some View {
        Menu {
            ForEach(RingTheme.allCases) { theme in
                Button {
                    if ProAccess.isUnlocked(.colorThemes, enabled: proEnabled) {
                        themeRaw = theme.rawValue
                    } else {
                        store.showLocked(.colorThemes)
                    }
                } label: {
                    Label(theme.displayName, systemImage: theme == store.theme ? "checkmark" : "paintpalette")
                }
            }
        } label: {
            Image(systemName: "paintpalette")
        }
    }
}
