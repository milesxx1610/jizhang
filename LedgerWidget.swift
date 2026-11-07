import SwiftUI
import WidgetKit
import AppIntents

private struct QuickEntry: TimelineEntry {
    let date: Date
}

private struct QuickEntryProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
        completion(QuickEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        completion(Timeline(entries: [QuickEntry(date: .now)], policy: .never))
    }
}

private struct QuickEntryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickEntryWidget", provider: QuickEntryProvider()) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "plus.circle.fill").font(.system(size: 30))
                Text("记一笔").font(.headline)
                Text("记录一笔收支").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
            .widgetURL(URL(string: "simpleledger://add"))
        }
        .configurationDisplayName("记一笔")
        .description("轻点打开记账页面。")
        .supportedFamilies([.systemSmall])
    }
}

@available(iOS 18.0, *)
private struct QuickEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickEntryControl") {
            ControlWidgetButton(action: OpenLedgerEntryIntent()) {
                Label("记一笔", systemImage: "plus.circle")
            }
        }
        .displayName("记一笔")
        .description("打开记账页面。")
    }
}

private struct SummaryEntry: TimelineEntry {
    let date: Date
    let totals: MonthlyTotals?
}

private struct SummaryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, totals: MonthlyTotals(income: 4000, expense: 2400))
    }
    func snapshot(for configuration: SummaryConfiguration, in context: Context) async -> SummaryEntry {
        entry(configuration)
    }
    func timeline(for configuration: SummaryConfiguration, in context: Context) async -> Timeline<SummaryEntry> {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        return Timeline(entries: [entry(configuration)], policy: .after(next))
    }
    private func entry(_ configuration: SummaryConfiguration) -> SummaryEntry {
        let date = Date()
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month,
              let shared = widgetSharedDefaults(),
              let data = shared.data(forKey: "monthlyTotals"),
              let totals = try? JSONDecoder().decode([String: MonthlyTotals].self, from: data) else {
            return SummaryEntry(date: date, totals: nil)
        }
        let monthly = totals["\(year)-\(month)"] ?? MonthlyTotals(income: 0, expense: 0)
        return SummaryEntry(date: date, totals: monthly.incomplete ? nil : monthly)
    }
}

private struct MonthlySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MonthlySummary", intent: SummaryConfiguration.self, provider: SummaryProvider()) { entry in
            MonthlySummaryView(entry: entry)
            .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
            .widgetURL(URL(string: "simpleledger://summary"))
        }
        .configurationDisplayName("本月收支")
        .description("查看本月收支与结余。")
        .supportedFamilies([.systemMedium])
    }
}

private struct MonthlySummaryView: View {
    let entry: SummaryEntry
    private let accent = Color(red: 0.12, green: 0.52, blue: 0.44)

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                SummaryRing(entry: entry)
                    .privacySensitive()
                    .frame(width: max(0, min(geometry.size.height - 18, geometry.size.width * 0.39)) * 0.84,
                           height: max(0, min(geometry.size.height - 18, geometry.size.width * 0.39)) * 0.84)
                VStack(alignment: .leading, spacing: 8) {
                    Text("本月收支").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    if let totals = entry.totals {
                        row("支出", totals.expense)
                        row("收入", totals.income)
                        row("结余", totals.income - totals.expense)
                    } else {
                        Text("打开 App 更新数据").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func row(_ title: String, _ amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(amount.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN")).precision(.fractionLength(2))))
                .fontWeight(.medium).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).privacySensitive()
        }.font(.system(size: 12))
    }
}

private struct SummaryRing: View {
    @Environment(\.redactionReasons) private var redactionReasons
    let entry: SummaryEntry
    private let accent = Color(red: 0.12, green: 0.52, blue: 0.44)
    var body: some View {
        GeometryReader { geometry in
            let lineWidth = min(geometry.size.width, geometry.size.height) * 0.12
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.14), lineWidth: lineWidth)
                if let values = entry.totals, values.income > 0, !redactionReasons.contains(.privacy) {
                    Circle().trim(from: 0, to: min(values.expense / values.income, 1))
                        .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(percent).font(.system(size: 27, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.55).privacySensitive()
            }.padding(lineWidth / 2)
        }
    }
    private var percent: String {
        guard let totals = entry.totals, totals.income > 0 else { return "—" }
        return (totals.expense / totals.income).formatted(.percent.precision(.fractionLength(0)))
    }
}

@main
struct LedgerWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        QuickEntryWidget()
        MonthlySummaryWidget()
        if #available(iOS 18.0, *) {
            QuickEntryControl()
        }
    }
}
