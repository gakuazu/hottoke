import SwiftUI

/// 「過去の模様アーカイブ」画面（docs/02-spec.md 2章 #6）。月表示のカレンダーで、
/// 日ごとに「すでに生成済み」「まだ未生成だが今から生成可能」「今からはもう生成不可能」
/// 「未来（選択不可）」の4状態を色分けして表示する。
struct CalendarArchiveView: View {
    @StateObject private var archiveStore = ArchivePatternStore()
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var selection: DateSelection?
    @State private var showUnavailableAlert = false

    private var calendar: Calendar { Calendar.current }

    private struct DateSelection: Identifiable, Equatable {
        let date: Date
        var id: TimeInterval { date.timeIntervalSinceReferenceDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthHeader
                    VStack(spacing: 10) {
                        weekdayHeader
                        calendarGrid
                    }
                    .padding(.horizontal, 16)
                    legend
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("アーカイブ")
            .sheet(item: $selection) { selection in
                ArchiveDayDetailView(date: selection.date, store: archiveStore)
            }
            .alert("この日の模様は作れません", isPresented: $showUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("この日のデータはもう端末に残っていません。iPhoneが保持している活動履歴はおおむね直近1週間ほどのため、それより前で未生成の日は今から作ることができません。")
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isCurrentMonthDisplayed)
        }
        .padding(.horizontal, 24)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { day in
                Text(day)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                dayCell(date: date)
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(color: .blue.opacity(0.75), text: "すでに模様を作った日（色は使ったスタイルを表す）")
            legendRow(color: Color.secondary.opacity(0.15), text: "まだ作っていないが、今から作れる日")
            legendRow(color: Color.secondary.opacity(0.06), text: "端末に記録が残っておらず、今からは作れない日")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(text)
        }
    }

    @ViewBuilder
    private func dayCell(date: Date?) -> some View {
        if let date {
            let entry = archiveStore.entry(for: date)
            let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
            let isToday = calendar.isDateInToday(date)
            let generatable = !isFuture && archiveStore.isGeneratable(date: date)

            Button {
                handleTap(date: date, entry: entry, isFuture: isFuture, generatable: generatable)
            } label: {
                ZStack {
                    Circle()
                        .fill(fillColor(entry: entry, isFuture: isFuture, generatable: generatable))
                        .frame(width: 36, height: 36)
                    if isToday {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 36, height: 36)
                    }
                    Text("\(calendar.component(.day, from: date))")
                        .font(.footnote)
                        .foregroundStyle(isFuture ? Color.secondary.opacity(0.4) : .primary)
                }
            }
            .disabled(isFuture)
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(width: 36, height: 36).frame(maxWidth: .infinity)
        }
    }

    private func fillColor(entry: ArchiveEntry?, isFuture: Bool, generatable: Bool) -> Color {
        if let entry, let style = PatternStyle(rawValue: entry.patternStyleRaw) {
            return style.archiveSwatchColor.opacity(0.75)
        }
        if isFuture {
            return .clear
        }
        return generatable ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.06)
    }

    private func handleTap(date: Date, entry: ArchiveEntry?, isFuture: Bool, generatable: Bool) {
        guard !isFuture else { return }
        if entry != nil || generatable {
            selection = DateSelection(date: date)
        } else {
            showUnavailableAlert = true
        }
    }

    /// 表示中の月に含まれる日付の配列（前後の空マス分はnilで埋める）。
    private var monthDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay) // 1=日曜
        let leadingBlanks = firstWeekday - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: offset, to: firstDay) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private var isCurrentMonthDisplayed: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func changeMonth(by delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = newMonth
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: displayedMonth)
    }
}

/// アーカイブのカレンダー上で「その日どのスタイルの模様が生成済みか」をひと目で分かるように
/// 添える簡易的な色。動画からサムネイルを切り出すような凝った実装はせず、スタイルごとに
/// 固定の色を割り当てるだけの軽量な表現にとどめる。
private extension PatternStyle {
    var archiveSwatchColor: Color {
        switch self {
        case .tiling: return .orange
        case .spirograph: return .purple
        case .waves: return .blue
        case .fractal: return .green
        }
    }
}
