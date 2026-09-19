import SwiftUI

/// 「1日の輪」の画像を作って持っておく。画面を開いたとき・アプリを前面に戻したとき・更新ボタンを
/// 押したときに、最新の活動データ（歩数・活動区間）を取り直して描き直す。
@MainActor
final class DailyRingStore: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var stepCount: Int = 0
    @Published private(set) var errorMessage: String?

    private let service = ActivityDataService()

    /// 最新データを取得して描き直す。すでに取得中なら何もしない。
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let now = Date()
        let data = await service.fetch(for: now, includeHourlySteps: true)
        let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage in
            let profile = DailyRingLayout.makeProfile(data: data, now: now)
            return DailyRingRenderer.render(profile: profile, date: data.date)
        }.value

        image = rendered
        stepCount = data.stepCount
        lastUpdated = now
    }
}

/// 「1日の輪」画面。円の一周が1日（0時が真上・時計回り）、中心から遠いほど活動が多く、
/// 模様の種類が活動の種類を表す（docs/22-app1-radial-redesign.md）。
struct DailyRingView: View {
    @StateObject private var store = DailyRingStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSavedBanner = false
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
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
            .navigationTitle("1日の輪")
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
            // 画面を開いたとき（別のタブから戻ったときも含む）に最新データで描き直す。
            .task {
                await store.refresh()
            }
            // アプリを前面に戻したときも描き直す。
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await store.refresh() }
            }
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
        if let updated = store.lastUpdated {
            VStack(spacing: 2) {
                Text("今日の歩数: \(store.stepCount)歩")
                    .font(.headline)
                Text("\(Self.timeFormatter.string(from: updated)) 時点のデータ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            legendLine(icon: "clock", text: "ぐるっと一周が24時間です。真上が0時、右が6時、真下が12時、左が18時。今日は現在時刻までを描き、これからの時間は空白です（点線が今の時刻）。")
            legendLine(icon: "arrow.up.left.and.arrow.down.right", text: "中心から遠いほど、その時間に活動した量（歩数）が多いです。うっすらした円は、内側から1時間あたり500歩・1500歩・3000歩の目安。静かな時間も中心の近くに小さく残ります。")
            legendLine(icon: "paintpalette", text: "色は時間帯にそって朝から夜へ移り変わります。")

            Text("模様の種類 = 活動")
                .font(.footnote.bold())
                .padding(.top, 4)
            ForEach(Self.legendKinds, id: \.self) { kind in
                HStack(spacing: 8) {
                    Image(systemName: DailyRingLayout.patternStyle(for: kind).iconName)
                        .frame(width: 22)
                        .foregroundStyle(.secondary)
                    Text("\(kind.displayName): \(DailyRingLayout.patternStyle(for: kind).displayName)")
                        .font(.footnote)
                }
            }
            Text("自転車・車移動は歩数が出ないため、乗っていた時間から歩数に換算して半径を決めています。活動の切り替わり目は、形も半径もなめらかにつながります。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.10)))
    }

    private static let legendKinds: [ActivityKind] = [.stationary, .walking, .running, .cycling, .automotive]

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
