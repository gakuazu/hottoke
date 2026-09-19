import SwiftUI

/// アーカイブのカレンダーで日付をタップしたときに表示するシート。
/// その日の「1日の輪」（点描リング）を、今日タブと同じレンダラーで描いて表示する（24時間すべて）。
/// 端末に活動履歴が残っていない日は、保存済みの要約から描き、それもなければ「データなし」を表示する。
/// （以前の動画版は廃止。ArchivePatternStore・動画書き出しのコードは復活用に残してあるが、この画面は使わない）
struct ArchiveDayDetailView: View {
    let date: Date
    @StateObject private var store: DailyRingStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProAccess.storageKey) private var proEnabled = ProAccess.defaultEnabled
    @AppStorage(RingArtStyle.storageKey) private var styleRaw = RingArtStyle.defaultStyle.rawValue

    init(date: Date) {
        self.date = date
        _store = StateObject(wrappedValue: DailyRingStore(date: date))
    }

    var body: some View {
        NavigationStack {
            DailyRingPanel(store: store, proEnabled: proEnabled)
                .navigationTitle(dateTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") { dismiss() }
                    }
                }
                .task {
                    store.configure(proEnabled: proEnabled, styleRaw: styleRaw)
                    await store.refresh()
                }
        }
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
