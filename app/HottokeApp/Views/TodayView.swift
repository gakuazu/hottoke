import SwiftUI
import AVFoundation
import AVKit

/// 「今日の模様」画面（メイン）。docs/02-spec.md 2章 #2 / docs/03-design.md 画面2に対応。
struct TodayView: View {
    @StateObject private var store = TodayPatternStore()
    @State private var queuePlayer: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var showSavedBanner = false
    @State private var saveErrorMessage: String?
    @State private var showUpdatedBanner = false
    // 「作り直し中」に既存の動画が表示されたままだと更新中であることが分からないため、
    // 生成開始時点で既存の模様（summary）があったかどうかを覚えておく。これがtrueのまま
    // isGeneratingがfalseに戻ったときだけ「更新しました」バナーを出す
    // （アプリ起動直後の初回生成では紛らわしいので出さない）。
    @State private var isRefreshingExistingPattern = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    previewArea
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal, 16)

                    if let summary = store.summary {
                        statsRow(summary)
                        styleSelectionRow(summary)
                    }

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }

                    VStack(spacing: 12) {
                        Button {
                            Task { await save() }
                        } label: {
                            Label("保存する", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.videoURL == nil)

                        Button {
                            Task { await store.forceRefresh() }
                        } label: {
                            Label("最新のデータで作り直す", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isGenerating)

                        NavigationLink {
                            ManualModeView()
                        } label: {
                            Label("手動モードで作ってみる", systemImage: "hand.draw")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)

                    if showSavedBanner {
                        Text("カメラロールに保存しました")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if showUpdatedBanner {
                        Text("模様を更新しました")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("今日の模様")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.forceRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isGenerating)
                }
            }
            .task {
                await store.loadOrGenerateTodayIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // アプリを再度前面に戻したタイミングで、日付が変わっていないかや
                // 前回確定時から活動量が増えていないかを確認し、増えていれば模様を作り直す。
                guard newPhase == .active else { return }
                Task { await store.refreshIfStale() }
            }
            .onChange(of: store.videoURL) { _, newValue in
                guard newValue != nil else { return }
                setUpPlayer()
            }
            .onChange(of: store.isGenerating) { oldValue, newValue in
                if newValue {
                    // 生成が始まった瞬間。すでに確定済みの模様がある状態からの「作り直し」なのか、
                    // アプリ起動直後などの「初回生成」なのかをここで覚えておく
                    // （この時点ではstore.summaryはまだ更新前の値のまま）。
                    isRefreshingExistingPattern = store.summary != nil
                } else if oldValue, isRefreshingExistingPattern {
                    // 既存の模様がある状態からの作り直しが完了した。初回生成のときは出さない。
                    isRefreshingExistingPattern = false
                    showUpdatedBanner = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showUpdatedBanner = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            Color.black
            if let queuePlayer {
                VideoPlayer(player: queuePlayer)
                    .disabled(true)
            } else if store.isGenerating {
                generatingPreview
            } else {
                Text("模様を準備中です")
                    .foregroundStyle(.white.opacity(0.6))
            }

            // 既存の動画が表示されている状態で「作り直す」を押しても進行中であることが
            // 分かるよう、生成中は元の動画の上に薄い暗幕とインジケーターを重ねる。
            if store.isGenerating, queuePlayer != nil {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("最新のデータで作り直しています…")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isGenerating)
    }

    /// 生成中の待ち時間を「静止したスピナー」ではなく、実際にできあがる模様と同じ
    /// レンダラーで動く万華鏡プレビューにして、待っている間も動的に見えるようにする。
    /// パラメータは今日の実データではなくプレースホルダー（現在時刻のパレットのみ反映）で、
    /// 動画が出来上がり次第 queuePlayer 側の実際の映像に自然に切り替わる。
    private var generatingPreview: some View {
        ZStack(alignment: .bottom) {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let hour = Calendar.current.component(.hour, from: Date())
                // 待っている間のプレースホルダーなので特定の活動には結び付けず、
                // 穏やかな「波の干渉」スタイルで表示する（実際の模様は生成完了後に差し替わる）。
                KaleidoscopeCanvasView(parameters: KaleidoscopeParameters(
                    symmetryCount: 8,
                    seed: 777,
                    palette: .forTimeOfDay(.of(hour: hour)),
                    rotation: KaleidoscopeDynamics.organicRotationAngle(elapsed: elapsed, angularSpeed: 0.35),
                    pulsePhase: (sin(elapsed * 1.6) + 1) / 2,
                    deformationIntensity: 0.5,
                    rotationSpeed: 0.35,
                    shardDensity: 0.6,
                    noiseAmount: 0.08,
                    time: elapsed,
                    patternStyle: .waves,
                    detail: 0.5
                ))
            }
            VStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text("今日のデータから模様を作っています…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func setUpPlayer() {
        guard let url = store.videoURL else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
        queuePlayer = player
    }

    private func statsRow(_ summary: TodaySummary) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                statItem(value: "\(summary.stepCount)", label: "歩数")
                statItem(value: String(format: "%.1f km", summary.distanceMeters / 1000), label: "距離")
                statItem(value: "\(summary.activeMinutes)分", label: "アクティブ時間")
            }
            // この模様がどのデータを元に、どのスタイルで作られたかを見えるようにする
            // （ユーザーからの「元にしているデータを表示して」というフィードバック対応）。
            // さらに「なぜそのスタイルになったか」がもっと分かるよう、各スタイルのひと言説明も
            // 添える（実機フィードバック対応）。手動でスタイルを選んでいる場合は
            // 「主な活動→スタイル」の対応関係が実際とは異なるため、その旨がわかる文言にする。
            if let style = PatternStyle(rawValue: summary.patternStyleRaw) {
                if summary.isManualStyleOverride {
                    Label("試しに選んだスタイル: \(style.displayName)", systemImage: style.iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let kind = summary.dominantKindRaw.flatMap(ActivityKind.init(rawValue:)) {
                    Label("主な活動: \(kind.displayName) → \(style.displayName)の模様", systemImage: style.iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(style.rationale)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
    }

    /// 「今日の模様」でも試しに他のスタイルへ変えられるスタイル選択行（ManualModeViewの
    /// styleSwatchと同じ「アイコン+短いラベルの丸ボタン、選択中はハイライト」という見た目）。
    /// 自動選択に戻すための選択肢も先頭に用意する。
    private func styleSelectionRow(_ summary: TodaySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("スタイルを試しに変える")
                .font(.caption)
                .foregroundStyle(.secondary)
            // 9スタイル分は横一列に並べきれないため、横スクロールにする
            // （5スタイル追加時に見た目が崩れないよう対応。docs/04-build-log.md参照）。
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    styleOptionSwatch(
                        label: "自動",
                        iconName: "wand.and.stars",
                        isLocked: false,
                        isSelected: !summary.isManualStyleOverride
                    ) {
                        Task { await store.forceRefresh(styleOverride: nil) }
                    }
                    ForEach(PatternStyle.allCases) { style in
                        styleOptionSwatch(
                            label: style.shortLabel,
                            iconName: style.iconName,
                            isLocked: style.isLocked,
                            isSelected: summary.isManualStyleOverride && summary.patternStyleRaw == style.rawValue
                        ) {
                            Task { await store.forceRefresh(styleOverride: style) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func styleOptionSwatch(label: String, iconName: String, isLocked: Bool, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            // ロック済みスタイル（将来課金で解放予定）はタップしても選択できない
            // （ManualModeViewのstyleSwatchと同じ考え方。今回は土台のみ）。
            guard !isLocked else { return }
            action()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                        )
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: iconName)
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    }
                }
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .disabled(store.isGenerating)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() async {
        guard let url = store.videoURL else { return }
        do {
            try await PhotoLibrarySaver.saveVideo(at: url)
            showSavedBanner = true
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
