import SwiftUI

/// 振り返りレポート（プロ機能）。1週間または1ヶ月の積算リング・合計歩数・活動別の時間・
/// 最も活発だった日と時間帯を1枚の画像にまとめ、カメラロールに保存できる。
struct ReportView: View {
    let proEnabled: Bool
    let theme: RingTheme

    @Environment(\.dismiss) private var dismiss
    @State private var period: RingPeriod = .week
    @State private var image: UIImage?
    @State private var isRendering = false
    @State private var message: String?
    @State private var showSaved = false

    private var unlocked: Bool { ProAccess.isUnlocked(.report, enabled: proEnabled) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("期間", selection: $period) {
                        Text(RingPeriod.week.displayName).tag(RingPeriod.week)
                        Text(RingPeriod.month.displayName).tag(RingPeriod.month)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if !unlocked {
                        Text(ProAccess.lockedMessage(for: .report))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 24)
                    } else {
                        ZStack {
                            Color.black
                            if let image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            } else if let message {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(24)
                            }
                            if isRendering { ProgressView().tint(.white) }
                        }
                        .aspectRatio(ReportRenderer.canvasSize.width / ReportRenderer.canvasSize.height, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)

                        Button {
                            Task { await save() }
                        } label: {
                            Label("レポートをカメラロールに保存", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(image == nil || isRendering)
                        .padding(.horizontal, 16)

                        if showSaved {
                            Text("カメラロールに保存しました").font(.footnote).foregroundStyle(.green)
                        }
                        Text("保存済みの日の記録から作ります。保存は、このアプリを開いた日から貯まっていきます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("振り返りレポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task(id: period) { await render() }
        }
    }

    private func render() async {
        guard unlocked else { return }
        isRendering = true
        message = nil
        defer { isRendering = false }
        let now = Date()
        let records = DailyHistoryStore.shared.recentRecords(days: period.days, endingAt: now)
        guard !records.isEmpty else {
            image = nil
            message = "まだ保存された日がありません。今日タブを開くと、その日から保存が始まります。"
            return
        }
        let report = PeriodReport.make(records: records, period: period, now: now)
        let theme = self.theme
        image = await Task.detached(priority: .userInitiated) {
            ReportRenderer.render(report: report, records: records, theme: theme)
        }.value
    }

    private func save() async {
        guard unlocked else { return }
        let now = Date()
        let records = DailyHistoryStore.shared.recentRecords(days: period.days, endingAt: now)
        guard !records.isEmpty else { return }
        let report = PeriodReport.make(records: records, period: period, now: now)
        let theme = self.theme
        let scale: CGFloat = ProAccess.isUnlocked(.highQualityExport, enabled: proEnabled) ? 2 : 1
        let high = await Task.detached(priority: .userInitiated) {
            ReportRenderer.render(report: report, records: records, theme: theme, scale: scale)
        }.value
        do {
            try await PhotoLibrarySaver.saveImage(high)
            showSaved = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showSaved = false
        } catch {
            message = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
