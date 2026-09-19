import SwiftUI

/// 「1日の輪」（点描リング）の画像を作って持っておく。
/// ・`date`がnil = 今日。開いたとき／前面に戻したとき／更新ボタンで最新の活動データを取り直して描き直す。
/// ・`date`が過去日 = アーカイブ。その日の24時間ぶんを描く。端末の活動履歴の保持期間（直近約7日）を
///   過ぎている日は取得せず「データなし」を示す。
@MainActor
final class DailyRingStore: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var stepCount: Int = 0
    /// 画像を作れない理由（過去日で端末にデータが残っていない等）。nilなら画像あり（または準備中）。
    @Published private(set) var noDataMessage: String?

    let date: Date?
    var isToday: Bool { date == nil }

    private let service = ActivityDataService()

    init(date: Date? = nil) {
        self.date = date
    }

    /// 最新データを取得して描き直す。すでに取得中なら何もしない。
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        noDataMessage = nil
        defer { isLoading = false }

        let now = Date()
        let target = date ?? now

        if !isToday && !DailyRingLayout.isWithinRetention(date: target, now: now) {
            image = nil
            stepCount = 0
            lastUpdated = now
            noDataMessage = "この日のデータは端末に残っていません。iPhoneが保持している歩数・活動の履歴は、おおむね直近1週間ほどです。"
            return
        }

        let data = await service.fetch(for: target, includeHourlySteps: true)
        if !isToday && data.stepCount == 0 && data.segments.isEmpty {
            image = nil
            stepCount = 0
            lastUpdated = now
            noDataMessage = "この日の歩数・活動のデータがありません。"
            return
        }

        let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage in
            let density = DailyRingLayout.makeDensity(data: data, now: now)
            return DailyRingRenderer.render(density: density, date: data.date)
        }.value

        image = rendered
        stepCount = data.stepCount
        lastUpdated = now
    }
}

/// 画像・保存ボタン・更新ボタン・読み方の凡例。「今日」タブとアーカイブの日付シートで共通。
struct DailyRingPanel: View {
    @ObservedObject var store: DailyRingStore
    @State private var showSavedBanner = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ringArea
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)

                statusLine

                VStack(spacing: 12) {
                    Button {
                        Task { await save() }
                    } label: {
                        Label("カメラロールに保存", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.image == nil || store.isLoading)

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
                Text("\(store.isToday ? "今日" : "この日")の歩数: \(store.stepCount)歩")
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
            legendLine(icon: "circle.dotted", text: "点の詰まりは、その時刻にその状態だった時間の長さです。歩行・走行は歩数が多いほど濃くなります。")
            legendLine(icon: "paintpalette", text: "色は活動の種類です。切り替わりの前後20分ほどは、色がなめらかに混ざります。")

            Text("色 = 活動の種類")
                .font(.footnote.bold())
                .padding(.top, 4)
            ForEach(DailyRingLayout.kindOrder, id: \.self) { kind in
                let c = DailyRingLayout.ringColor(for: kind)
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

    private func save() async {
        guard let image = store.image else { return }
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

    var body: some View {
        NavigationStack {
            DailyRingPanel(store: store)
                .navigationTitle("今日")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.isLoading)
                    }
                }
                .task {
                    await store.refresh()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { await store.refresh() }
                }
        }
    }
}
