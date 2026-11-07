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
                Text("快速记账").font(.headline)
                Text("记录一笔收支").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
            .widgetURL(URL(string: "simpleledger://add"))
        }
        .configurationDisplayName("快速记账")
        .description("轻点打开记账页面。")
        .supportedFamilies([.systemSmall])
    }
}

@available(iOS 18.0, *)
private struct QuickEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickEntryControl") {
            ControlWidgetButton(action: OpenLedgerEntryIntent()) {
                Label("快速记账", systemImage: "plus.circle")
            }
        }
        .displayName("快速记账")
        .description("打开记账页面。")
    }
}

@main
struct LedgerWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        QuickEntryWidget()
        if #available(iOS 18.0, *) {
            QuickEntryControl()
        }
    }
}
