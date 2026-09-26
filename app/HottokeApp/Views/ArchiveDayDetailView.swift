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
///
/// ページの配列（`pageDates`）は`@State`で持ち、**追加はしても、途中で作り直したり
/// 並び替えたり削除したりはしない**。当初は「選択日が変わるたびに前日・当日・翌日の3件で
/// 配列を毎回作り直す」実装だったが、実機でスワイプの最中に配列の中身が丸ごと入れ替わり、
/// ページめくりの余韻アニメーションと衝突して「1.5日分だけ動いて2日分の絵が半分ずつ混ざる」
/// 不具合が発生した（オーナー報告）。SwiftUIの`TabView(.page)`は、表示中に渡す配列の要素が
/// 入れ替わる（既存の要素が消える・並びが変わる）と、ページめくりの途中でも表示が乱れることが
/// あるため、配列は「今すでに見えている日はそのまま残し、必要なページを1枚ずつ追加するだけ」に
/// とどめている。追加のタイミングも、TabViewの選択（`currentDate`）が実際に確定して変わった
/// あと（`onChange`）だけに限定し、めくっている最中に配列を触らないようにしている。
struct ArchiveDayDetailView: View {
    @State private var currentDate: Date
    @State private var pageDates: [Date]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProAccess.storageKey) private var proEnabled = ProAccess.defaultEnabled
    @AppStorage(RingArtStyle.storageKey) private var styleRaw = RingArtStyle.defaultStyle.rawValue
    @ObservedObject private var history = DailyHistoryStore.shared

    private var calendar: Calendar { Calendar.current }

    init(date: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        _currentDate = State(initialValue: day)
        _pageDates = State(initialValue: Self.neighboringWindow(around: day, calendar: calendar))
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
        // ページめくりが確定して選択日が変わったときだけ、足りなければ隣を1枚追加する。
        .onChange(of: currentDate) { _, newValue in
            extendPageDatesIfNeeded(around: newValue)
        }
        // バックグラウンド同期などで保存済みの日が増えたときも、同じ安全な追加処理だけ行う。
        .onChange(of: history.revision) { _, _ in
            extendPageDatesIfNeeded(around: currentDate)
        }
    }

    /// 開いたときの初期ページ（前日・当日・翌日のうち、日付として妥当なものだけ）。
    private static func neighboringWindow(around day: Date, calendar: Calendar) -> [Date] {
        extendedPageDates([day], around: day, calendar: calendar) { isDateNavigable($0, calendar: calendar) }
    }

    /// 今の選択日の前後に、まだ配列にないページがあれば1枚だけ追加する。
    /// 既存のページの並び・中身には触れない（追加のみ）。
    private func extendPageDatesIfNeeded(around date: Date) {
        pageDates = Self.extendedPageDates(pageDates, around: date, calendar: calendar, isNavigable: isNavigable)
    }

    /// `pageDates`に、`date`の前後で欠けている隣を最大1件ずつ追加した新しい配列を返す（純粋関数）。
    /// 既存の要素は絶対に削除・並び替えしない（TabViewの表示中の状態を壊さないため）。
    /// `date`が配列に含まれていなければ何もしない。`date`が配列の先頭・末尾それぞれに
    /// あたる場合だけ、その側にもう1件足りなければ追加する（両端にあたる＝要素が1件だけの
    /// ときは、両側とも確認する）。
    static func extendedPageDates(_ pageDates: [Date], around date: Date, calendar: Calendar, isNavigable: (Date) -> Bool) -> [Date] {
        guard pageDates.contains(date) else { return pageDates }
        var result = pageDates
        if result.first == date, let prev = calendar.date(byAdding: .day, value: -1, to: date),
           !result.contains(prev), isNavigable(prev) {
            result.insert(prev, at: 0)
        }
        if result.last == date, let next = calendar.date(byAdding: .day, value: 1, to: date),
           !result.contains(next), isNavigable(next) {
            result.append(next)
        }
        return result
    }

    /// 指定の日にスワイプで移動してよいか（未来は不可、過去は履歴が残っていそうな日・保存済みの日まで）。
    private func isNavigable(_ date: Date) -> Bool {
        Self.isDateNavigable(date, calendar: calendar)
    }

    /// `init`など`self`（`@ObservedObject`の`history`）がまだ使えない場面向けの、
    /// シングルトンを直接参照する版。判定内容は`isNavigable`と同じ。
    private static func isDateNavigable(_ date: Date, calendar: Calendar) -> Bool {
        let saved = DailyHistoryStore.shared.record(for: date, calendar: calendar)?.hasAnyData ?? false
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
