import Foundation

let widgetGroup = "group.com.miles1610.simpleledger"

func widgetSharedDefaults() -> UserDefaults? {
    var candidates = [widgetGroup]
    if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
       let data = try? Data(contentsOf: url),
       let start = data.range(of: Data("<?xml".utf8)),
       let end = data.range(of: Data("</plist>".utf8), options: [], in: start.lowerBound..<data.endIndex),
       let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
       let entitlements = plist["Entitlements"] as? [String: Any],
       let groups = entitlements["com.apple.security.application-groups"] as? [String] {
        candidates = groups.filter { $0 == widgetGroup || $0.hasPrefix(widgetGroup + ".") } + candidates
    }
    guard let group = candidates.first(where: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }) else { return nil }
    return UserDefaults(suiteName: group)
}

struct MonthlyTotals: Codable {
    var income: Double
    var expense: Double
    var incomplete = false
}
