import UIKit

/// 「振り返りレポート」の画像。期間（1週間／1ヶ月）の積算リングを大きく中央に描き、
/// その周り（下）に、合計歩数・活動別の時間・最も活発だった日と時間帯を並べる。
/// 積算リングは、DailyRingLayout.aggregate（期間の各日を平均したもの）を同じレンダラーで描く。
enum ReportRenderer {

    /// レポートの画像の大きさ（縦長 2:3）。
    static let canvasSize = CGSize(width: 1080, height: 1620)

    /// `records`は期間内の保存済みの記録。`scale`を2にすると2倍の解像度で書き出す。
    static func render(report: PeriodReport, records: [DailyRingSlices], style: RingArtStyle = .flowerCorona, scale: CGFloat = 1) -> UIImage {
        let canvas = canvasSize
        let inRange = records.filter { $0.dateKey >= report.startKey && $0.dateKey <= report.endKey && $0.hasAnyData }
        let sorted = inRange.sorted { $0.dateKey < $1.dateKey }
        let artStyle = style.forAggregate
        let density: DailyRingDensity
        var pastDays: [DailyRingDensity] = []
        if artStyle == .yearRings, let newest = sorted.last {
            // 週の年輪: 1日ずつ（新しい日が外側）
            density = DailyRingLayout.makeDensity(slices: newest)
            pastDays = sorted.dropLast().reversed().map { DailyRingLayout.makeDensity(slices: $0) }
        } else {
            density = DailyRingLayout.aggregate(inRange)
        }
        let seedDate = date(fromKey: report.startKey) ?? Date()

        var options = RingRenderOptions(canvas: canvas)
        options.ringSide = 1040
        options.ringCenter = CGPoint(x: canvas.width / 2, y: 655)
        options.style = artStyle
        options.pastDays = pastDays
        options.chrome = .ringOnly

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas.width * scale, height: canvas.height * scale), format: format)
        return renderer.image { rc in
            let ctx = rc.cgContext
            ctx.scaleBy(x: scale, y: scale)
            DailyRingRenderer.draw(in: ctx, density: density, date: seedDate, options: options)
            drawText(ctx: ctx, report: report, canvas: canvas)
        }
    }

    // MARK: - 文字の部分

    private static func drawText(ctx: CGContext, report: PeriodReport, canvas: CGSize) {
        let cx = canvas.width / 2
        func text(_ s: String, _ p: CGPoint, _ size: CGFloat, _ weight: UIFont.Weight, _ alpha: CGFloat, _ left: Bool, _ right: Bool) {
            DailyRingRenderer.drawText(s, at: p, fontSize: size, weight: weight, alpha: alpha, leftAligned: left, rightAligned: right)
        }

        // 見出し
        text("\(report.period.displayName)の振り返り", CGPoint(x: cx, y: 82), 46, .light, 0.9, false, false)
        text("\(shortDate(report.startKey)) – \(shortDate(report.endKey))", CGPoint(x: cx, y: 132), 26, .light, 0.5, false, false)

        // 区切り線
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 90, y: 1160))
        ctx.addLine(to: CGPoint(x: canvas.width - 90, y: 1160))
        ctx.strokePath()

        // 合計歩数
        text("合計", CGPoint(x: cx, y: 1196), 24, .light, 0.5, false, false)
        text("\(formatNumber(report.totalSteps)) 歩", CGPoint(x: cx, y: 1252), 72, .thin, 0.95, false, false)
        let saved = report.savedDays < report.period.days
            ? "保存済み \(report.savedDays)日分（\(report.period.days)日のうち。保存を始めた日から貯まります）"
            : "保存済み \(report.savedDays)日分"
        text("1日平均 \(formatNumber(report.averageStepsPerSavedDay)) 歩  ·  \(saved)", CGPoint(x: cx, y: 1308), 22, .light, 0.5, false, false)

        // 活動別の時間（2列 × 3行）
        let kinds: [ActivityKind] = [.sleeping, .stationary, .walking, .running, .cycling, .automotive]
        for (i, kind) in kinds.enumerated() {
            let col = i % 2, row = i / 2
            let x: CGFloat = col == 0 ? 150 : 590
            let y = 1372 + CGFloat(row) * 46
            let c = DailyRingLayout.ringColor(for: kind)
            ctx.setFillColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 0.95)
            ctx.fillEllipse(in: CGRect(x: x - 26, y: y - 8, width: 16, height: 16))
            text(kind.displayName, CGPoint(x: x, y: y), 26, .light, 0.75, true, false)
            text(formatMinutes(report.minutes(kind)), CGPoint(x: x + 340, y: y), 26, .regular, 0.85, false, true)
        }

        // 最も活発だった日・時間帯
        ctx.move(to: CGPoint(x: 90, y: 1520))
        ctx.addLine(to: CGPoint(x: canvas.width - 90, y: 1520))
        ctx.strokePath()
        text("最も活発だった日", CGPoint(x: canvas.width * 0.27, y: 1550), 22, .light, 0.5, false, false)
        text(report.busiestDayKey.map { "\(longDate($0))  \(formatNumber(report.busiestDaySteps))歩" } ?? "—", CGPoint(x: canvas.width * 0.27, y: 1588), 28, .regular, 0.9, false, false)
        text("最も活発だった時間帯", CGPoint(x: canvas.width * 0.73, y: 1550), 22, .light, 0.5, false, false)
        text(report.busiestHour.map { String(format: "%d:00〜%d:00", $0, ($0 + 1) % 24) } ?? "—", CGPoint(x: canvas.width * 0.73, y: 1588), 28, .regular, 0.9, false, false)

    }

    // MARK: - 書式

    static func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// 分数を「◯時間◯分」「◯分」にする。
    static func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total <= 0 { return "0分" }
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)分" }
        return m == 0 ? "\(h)時間" : "\(h)時間\(m)分"
    }

    private static func date(fromKey key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    private static func shortDate(_ key: String) -> String {
        guard let d = date(fromKey: key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d"
        return f.string(from: d)
    }

    static func longDate(_ key: String) -> String {
        guard let d = date(fromKey: key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E)"
        return f.string(from: d)
    }
}
