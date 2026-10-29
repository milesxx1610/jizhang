import SwiftUI

struct Entry: Identifiable, Codable {
    var id = UUID()
    var amount: Decimal
    var category: String
    var note: String
    var date: Date
    var income: Bool
}

@MainActor final class Ledger: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var error: String?
    private var loadFailed = false
    private let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ledger.json")
    func exportData() throws -> Data {
        guard !loadFailed else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONEncoder().encode(entries)
    }
    init() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file)) }
        catch { loadFailed = true; self.error = "账目读取失败。请勿删除 App，以免丢失数据。" }
    }
    func save(_ updated: [Entry]) -> Bool {
        guard !loadFailed else { error = "账目读取失败，为保护原数据已停止保存。"; return false }
        do {
            let data = try JSONEncoder().encode(updated)
            try data.write(to: file, options: .atomic)
            entries = updated
            return true
        } catch { self.error = "保存失败，请重试。"; return false }
    }
}

@main struct MoneyApp: App {
    @StateObject private var ledger = Ledger()
    var body: some Scene { WindowGroup { LedgerTabs().environmentObject(ledger) } }
}

struct EditorTarget: Identifiable { let id = UUID(); var entry: Entry? }

struct Home: View {
    @EnvironmentObject private var ledger: Ledger
    @State private var month = Date()
    @State private var editor: EditorTarget?
    @State private var deleting: Entry?
    private var monthEntries: [Entry] { ledger.entries.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }.sorted { $0.date > $1.date } }
    private func total(_ income: Bool) -> Decimal { monthEntries.filter { $0.income == income }.reduce(Decimal.zero) { $0 + $1.amount } }
    private func money(_ amount: Decimal) -> String { (amount as NSDecimalNumber).doubleValue.formatted(.currency(code: "CNY")) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("上个月")
                            Spacer()
                            Text(month, format: .dateTime.year().month()).font(.headline)
                            Spacer()
                            Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("下个月")
                        }
                        HStack {
                            metric("支出", money(total(false)))
                            Spacer()
                            metric("收入", money(total(true)))
                        }
                        Text("结余  \(money(total(true) - total(false)))").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section("账目") {
                    if monthEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有账目").font(.headline)
                            Text("点击右上角的加号，记录第一笔收支。 ").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 20)
                    }
                    ForEach(monthEntries) { entry in
                        Button { editor = EditorTarget(entry: entry) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.income ? "arrow.down.left" : "arrow.up.right")
                                    .font(.headline).foregroundStyle(entry.income ? .green : .orange)
                                    .frame(width: 40, height: 40).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.category).foregroundStyle(.primary)
                                    Text(entry.note.isEmpty ? entry.date.formatted(date: .abbreviated, time: .omitted) : entry.note + " · " + entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text((entry.income ? "+" : "−") + money(entry.amount)).fontWeight(.semibold).foregroundStyle(.primary)
                            }.padding(.vertical, 4)
                        }.swipeActions { Button("删除", role: .destructive) { deleting = entry } }
                    }
                }
                Section { Text("数据仅保存在此设备。删除 App 可能同时删除账目，请先谨慎使用测试数据。") .font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("记账")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editor = EditorTarget(entry: nil) } label: { Image(systemName: "plus") }.accessibilityLabel("添加账目") } }
            .sheet(item: $editor) { target in EntryEditor(entry: target.entry).environmentObject(ledger) }
            .alert("删除这笔账目？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("删除", role: .destructive) { if let entry = deleting { _ = ledger.save(ledger.entries.filter { $0.id != entry.id }) }; deleting = nil }
                Button("取消", role: .cancel) { deleting = nil }
            } message: { Text("删除后无法恢复。") }
            .alert("提示", isPresented: Binding(get: { ledger.error != nil }, set: { if !$0 { ledger.error = nil } })) { Button("知道了") { ledger.error = nil } } message: { Text(ledger.error ?? "") }
        }
    }
    private func shift(_ value: Int) { if let date = Calendar.current.date(byAdding: .month, value: value, to: month) { month = date } }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1) } }
}

struct EntryEditor: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    let entry: Entry?
    @State private var amount: String
    @State private var category: String
    @State private var note: String
    @State private var date: Date
    @State private var income: Bool
    @State private var error: String?
    init(entry: Entry?) {
        self.entry = entry
        _amount = State(initialValue: entry.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _category = State(initialValue: entry?.category ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _date = State(initialValue: entry?.date ?? Date())
        _income = State(initialValue: entry?.income ?? false)
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $income) { Text("支出").tag(false); Text("收入").tag(true) }.pickerStyle(.segmented)
                Section("金额") { TextField("0.00", text: $amount).keyboardType(.decimalPad) }
                Section("详情") {
                    TextField("分类，例如餐饮", text: $category)
                    TextField("备注（选填）", text: $note)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(entry == nil ? "记一笔" : "编辑账目").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
    }
    private func save() {
        let clean = amount.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !clean.isEmpty, clean.allSatisfy({ $0.isNumber || $0 == "." }), parts.count == 1 || parts[1].count <= 2, let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")), value > 0, value <= 999999999 else { error = "请输入大于零的金额，最多两位小数。"; return }
        let name = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "请填写分类。"; return }
        let updated = Entry(id: entry?.id ?? UUID(), amount: value, category: name, note: note.trimmingCharacters(in: .whitespacesAndNewlines), date: date, income: income)
        var all = ledger.entries
        if let index = all.firstIndex(where: { $0.id == updated.id }) { all[index] = updated } else { all.append(updated) }
        if ledger.save(all) { dismiss() } else { error = "保存失败，请重试。" }
    }
}

