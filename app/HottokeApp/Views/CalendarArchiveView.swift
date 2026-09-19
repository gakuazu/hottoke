import SwiftUI

/// 「アーカイブ」画面。月表示のカレンダーで日付を選ぶと、その日の「1日の輪」（点描リング）を表示する。
/// 端末の歩数計・活動履歴は直近約7日分までしか残っていないため、日ごとに
/// 「見られる日（直近約7日）」「データが残っていない日」「未来（選択不可）」を色分けして表示する。
/// （以前の「動画を生成済みの日」の表示は廃止。動画・スタイル関連のコードは復活用に残してある）
struct CalendarArchiveView: View {
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
                ArchiveDayDetailView(date: selection.date)
            }
            .alert("この日のデータはありません", isPresented: $showUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("この日の歩数・活動のデータはもう端末に残っていません。iPhoneが保持している履歴はおおむね直近1週間ほどのため、それより前の日の「1日の輪」は作れません。")
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
            legendRow(color: .blue.opacity(0.75), text: "その日の「1日の輪」を見られる日（直近約1週間）")
            legendRow(color: Color.secondary.opacity(0.06), text: "端末に記録が残っておらず、見られない日")
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
            let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
            let isToday = calendar.isDateInToday(date)
            let available = !isFuture && DailyRingLayout.isWithinRetention(date: date, now: Date(), calendar: calendar)

            Button {
                handleTap(date: date, isFuture: isFuture, available: available)
            } label: {
                ZStack {
                    Circle()
                        .fill(fillColor(isFuture: isFuture, available: available))
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

    private func fillColor(isFuture: Bool, available: Bool) -> Color {
        if isFuture {
            return .clear
        }
        return available ? Color.blue.opacity(0.75) : Color.secondary.opacity(0.06)
    }

    private func handleTap(date: Date, isFuture: Bool, available: Bool) {
        guard !isFuture else { return }
        if available {
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
