import AppIntents
import Foundation

struct SummaryConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "本月收支"
}

extension Notification.Name {
    static let openLedgerEntry = Notification.Name("openLedgerEntry")
}

@available(iOS 18.0, *)
enum LedgerDestination: String, AppEnum {
    case entry
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "记账页面")
    static let caseDisplayRepresentations: [LedgerDestination: DisplayRepresentation] = [
        .entry: "记账"
    ]
}

@available(iOS 18.0, *)
struct OpenLedgerEntryIntent: OpenIntent {
    static let title: LocalizedStringResource = "快速记账"
    @Parameter(title: "页面") var target: LedgerDestination

    init() { target = .entry }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        UserDefaults.standard.set(true, forKey: "pendingQuickEntry")
        NotificationCenter.default.post(name: .openLedgerEntry, object: nil)
        #endif
        return .result()
    }
}
