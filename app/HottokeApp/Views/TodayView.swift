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
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("今日のデータから模様を作っています…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                Text("模様を準備中です")
                    .foregroundStyle(.white.opacity(0.6))
            }
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
        HStack(spacing: 24) {
            statItem(value: "\(summary.stepCount)", label: "歩数")
            statItem(value: String(format: "%.1f km", summary.distanceMeters / 1000), label: "距離")
            statItem(value: "\(summary.activeMinutes)分", label: "アクティブ時間")
        }
        .padding(.horizontal, 16)
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
