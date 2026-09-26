import SwiftUI

/// アーカイブのカレンダーで日付をタップしたときに表示するシート。
/// その日の「1日の輪」（点描リング）を、今日タブと同じレンダラーで描いて表示する（24時間すべて）。
/// 端末に活動履歴が残っていない日は、保存済みの要約から描き、それもなければ「データなし」を表示する。
/// （以前の動画版は廃止。ArchivePatternStore・動画書き出しのコードは復活用に残してあるが、この画面は使わない）
///
/// 横スワイプで前日・翌日にも移動できる（`TabView`のページめくりを利用）。
/// ・未来の日には進めない。
/// ・過去方向は、端末に履歴が残っていそうな日（直近約1週間）か、保存済みのデータがある日まで。
///   それより古い日へは、スワイプでは行けない（ページ自体が存在しない）。
struct ArchiveDayDetailView: View {
    @State private var currentDate: Date
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProAccess.storageKey) private var proEnabled = ProAccess.defaultEnabled
    @AppStorage(RingArtStyle.storageKey) private var styleRaw = RingArtStyle.defaultStyle.rawValue
    @ObservedObject private var history = DailyHistoryStore.shared

    private var calendar: Calendar { Calendar.current }

    init(date: Date) {
        _currentDate = State(initialValue: Calendar.current.startOfDay(for: date))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 4) {
                if pageDates.count > 1 {
                    Text("← スワイプで前日・翌日へ →")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                TabView(selection: $currentDate) {
                    ForEach(pageDates, id: \.self) { day in
                        ArchiveDayPage(date: day, proEnabled: proEnabled, styleRaw: styleRaw)
                            .tag(day)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    /// いま表示できるページ（前日・当日・翌日のうち、日付として妥当なものだけ）。
    /// `currentDate`が変わるたびに再計算し、TabViewの選択（=日付そのもの）が
    /// スワイプで自然に前後の日へ移ることを利用して、日付の範囲を無限に広げずに済ませている。
    private var pageDates: [Date] {
        var days: [Date] = [currentDate]
        if let prev = calendar.date(byAdding: .day, value: -1, to: currentDate), isNavigable(prev) {
            days.append(prev)
        }
        if let next = calendar.date(byAdding: .day, value: 1, to: currentDate), isNavigable(next) {
            days.append(next)
        }
        return days.sorted()
    }

    /// 指定の日にスワイプで移動してよいか（未来は不可、過去は履歴が残っていそうな日・保存済みの日まで）。
    private func isNavigable(_ date: Date) -> Bool {
        let saved = history.record(for: date, calendar: calendar)?.hasAnyData ?? false
        return DailyRingLayout.isArchiveAvailable(date: date, hasSavedRecord: saved, now: Date(), calendar: calendar)
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: currentDate)
    }
}

/// `ArchiveDayDetailView`の1ページぶん（1日の「1日の輪」）。日付ごとに自分のデータ取得を持つ。
private struct ArchiveDayPage: View {
    let proEnabled: Bool
    let styleRaw: String
    @StateObject private var store: DailyRingStore

    init(date: Date, proEnabled: Bool, styleRaw: String) {
        self.proEnabled = proEnabled
        self.styleRaw = styleRaw
        _store = StateObject(wrappedValue: DailyRingStore(date: date))
    }

    var body: some View {
        DailyRingPanel(store: store, proEnabled: proEnabled)
            .task {
                store.configure(proEnabled: proEnabled, styleRaw: styleRaw)
                await store.refresh()
            }
            .onChange(of: proEnabled) { _, newValue in store.configure(proEnabled: newValue, styleRaw: styleRaw) }
            .onChange(of: styleRaw) { _, newValue in store.configure(proEnabled: proEnabled, styleRaw: newValue) }
    }
}
