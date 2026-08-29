import SwiftUI
import AVFoundation
import AVKit

/// アーカイブのカレンダーで日付をタップしたときに表示するシート。
/// すでに生成済みならその模様をすぐに再生し、未生成（かつ生成可能な日）ならその場で
/// データ取得→動画生成を行ってから再生する（TodayViewの生成中UI・保存フローを参考にした簡易版）。
struct ArchiveDayDetailView: View {
    let date: Date
    @ObservedObject var store: ArchivePatternStore

    @State private var queuePlayer: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var playerFileName: String?
    @State private var showSavedBanner = false
    @State private var saveErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var entry: ArchiveEntry? { store.entry(for: date) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    previewArea
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal, 16)

                    if let entry {
                        statsRow(entry)
                    }

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Label("保存する", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(entry == nil)
                    .padding(.horizontal, 16)

                    // すでに生成済みの過去日も、最新のデータで作り直せるようにする。
                    // ただしOSの活動履歴の保持期間を過ぎている日で作り直すと、データが
                    // 取得できず「静けさの模様」に劣化して上書きしてしまうため、
                    // 生成可能な範囲の日にだけボタンを出す。
                    if entry != nil && store.isGeneratable(date: date) {
                        Button {
                            Task { try? await store.generate(for: date) }
                        } label: {
                            Label("最新のデータで作り直す", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isGenerating)
                        .padding(.horizontal, 16)
                    }

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
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                if entry == nil {
                    try? await store.generate(for: date)
                }
                setUpPlayerIfNeeded()
            }
            .onChange(of: store.isGenerating) { _, isGenerating in
                guard !isGenerating else { return }
                setUpPlayerIfNeeded()
            }
            .onChange(of: entry?.videoFileName) { _, _ in
                setUpPlayerIfNeeded()
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
            } else if !store.isGenerating {
                if entry == nil {
                    Text("この日の模様はまだありません")
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("模様を準備中です")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // 「作り直す」で既存の動画が表示されたまま生成中の場合も、進行中だと
            // わかるように上から覆う（TodayViewで直したのと同じ考え方）。
            if store.isGenerating {
                Color.black.opacity(queuePlayer == nil ? 1 : 0.55)
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("この日のデータから模様を作っています…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    /// 「作り直す」で動画ファイルが差し替わった場合も検知して再生し直せるよう、
    /// queuePlayerの有無ではなく「今表示しているファイル名と違うか」で判定する
    /// （TodayViewで一度直したのと同じ考え方）。
    private func setUpPlayerIfNeeded() {
        guard let entry, entry.videoFileName != playerFileName else { return }
        let url = store.videoURL(for: entry)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
        queuePlayer = player
        playerFileName = entry.videoFileName
    }

    private func statsRow(_ entry: ArchiveEntry) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                statItem(value: "\(entry.stepCount)", label: "歩数")
                statItem(value: String(format: "%.1f km", entry.distanceMeters / 1000), label: "距離")
                statItem(value: "\(entry.activeMinutes)分", label: "アクティブ時間")
            }
            if let style = PatternStyle(rawValue: entry.patternStyleRaw) {
                if let kind = entry.dominantKindRaw.flatMap(ActivityKind.init(rawValue:)) {
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

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func save() async {
        guard let entry else { return }
        let url = store.videoURL(for: entry)
        do {
            try await PhotoLibrarySaver.saveVideo(at: url)
            showSavedBanner = true
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
