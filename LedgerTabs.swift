import SwiftUI
import Charts
import UniformTypeIdentifiers

private let accent = Color(red: 0.12, green: 0.52, blue: 0.44)
private func moneyText(_ value: Decimal) -> String { (value as NSDecimalNumber).doubleValue.formatted(.currency(code: "CNY")) }
private func monthItems(_ entries: [Entry], _ date: Date) -> [Entry] { entries.filter { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month) }.sorted { $0.date > $1.date } }
private func sum(_ entries: [Entry], income: Bool) -> Decimal { entries.filter { $0.income == income }.reduce(0) { $0 + $1.amount } }

struct LedgerTabs: View {
    @EnvironmentObject private var ledger: Ledger
    @State private var target: EditorTarget?
    @State private var selected = 1
    var body: some View {
        TabView(selection: $selected) {
            Dashboard(target: $target).tabItem { Label("明细", systemImage: "list.bullet.rectangle") }.tag(0)
            EntryEditor(entry: nil, embedded: true).tabItem { Label("记账", systemImage: "plus.circle.fill") }.tag(1)
            Insights().tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(2)
        }
        .tint(accent)
        .sheet(item: $target) { EntryEditor(entry: $0.entry).environmentObject(ledger) }
        .alert("提示", isPresented: Binding(get: { ledger.error != nil }, set: { if !$0 { ledger.error = nil } })) { Button("知道了") { ledger.error = nil } } message: { Text(ledger.error ?? "") }
    }
}

private struct Dashboard: View {
    @EnvironmentObject private var ledger: Ledger
    @Binding var target: EditorTarget?
    @State private var month = Date()
    @State private var deleting: Entry?
    @State private var search = ""
    @AppStorage("monthlyBudget") private var budget = 0.0
    private var items: [Entry] { monthItems(ledger.entries, month) }
    private var visible: [Entry] { search.isEmpty ? items : items.filter { $0.category.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search) } }
    private var days: [Date] { Array(Set(visible.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    summary
                    if budget > 0 { budgetCard }
                    HStack(alignment: .firstTextBaseline) { Text("账目明细").font(.title3.bold()); Spacer(); Text("\(visible.count) 笔").font(.subheadline).foregroundStyle(.secondary) }
                    if visible.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "还没有账目" : "没有找到结果", systemImage: search.isEmpty ? "tray" : "magnifyingglass", description: Text(search.isEmpty ? "点击底部记账按钮记录收支" : "试试其他关键词"))
                    } else {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(days, id: \.self) { day in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(day, format: .dateTime.month().day().weekday(.wide)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    VStack(spacing: 0) {
                                        ForEach(visible.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { entry in
                                            Button { target = EditorTarget(entry: entry) } label: { EntryRow(entry: entry) }.buttonStyle(.plain)
                                                .contextMenu { Button("编辑") { target = EditorTarget(entry: entry) }; Button("删除", role: .destructive) { deleting = entry } }
                                            if entry.id != visible.filter({ Calendar.current.isDate($0.date, inSameDayAs: day) }).last?.id { Divider().padding(.leading, 64) }
                                        }
                                    }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("明细").navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: "搜索分类或备注")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { target = EditorTarget(entry: nil) } label: { Image(systemName: "plus") }.accessibilityLabel("记一笔") } }
            .alert("删除这笔账目？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("删除", role: .destructive) { if let item = deleting { _ = ledger.save(ledger.entries.filter { $0.id != item.id }) }; deleting = nil }
                Button("取消", role: .cancel) { deleting = nil }
            } message: { Text("删除后无法恢复。") }
        }
    }
    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34) }.accessibilityLabel("上个月")
            Spacer()
            Text(month, format: .dateTime.year().month()).font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 34, height: 34) }.accessibilityLabel("下个月")
        }.modifier(NativeMonthControls()).foregroundStyle(.primary)
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("本月支出").font(.subheadline).foregroundStyle(.secondary)
            Text(moneyText(sum(items, income: false))).font(.system(size: 36, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Divider()
            HStack { amountLabel("收入", sum(items, income: true)); Spacer(); amountLabel("收支结余", sum(items, income: true) - sum(items, income: false)) }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
    private var budgetCard: some View {
        let spent = (sum(items, income: false) as NSDecimalNumber).doubleValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Label("月度预算", systemImage: "chart.pie").font(.subheadline.weight(.semibold)); Spacer(); Text(spent > budget ? "已超出" : "剩余") .foregroundStyle(.secondary).font(.caption); Text(moneyText(Decimal(abs(budget - spent)))).font(.subheadline.bold()) }
            ProgressView(value: min(spent / budget, 1)).tint(spent > budget ? .orange : accent)
            Text("预算 \(moneyText(Decimal(budget))) · 已支出 \(moneyText(Decimal(spent)))").font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    private func amountLabel(_ title: String, _ amount: Decimal) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(moneyText(amount)).font(.headline).lineLimit(1).minimumScaleFactor(0.6) } }
    private func shift(_ offset: Int) { if let next = Calendar.current.date(byAdding: .month, value: offset, to: month) { withAnimation { month = next } } }
}

private struct NativeMonthControls: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.buttonStyle(.glass) }
        else { content.buttonStyle(.borderless) }
    }
}

private struct EntryRow: View {
    let entry: Entry
    @AppStorage("customCategories") private var customJSON = "[]"
    private var emoji: String {
        let custom = (try? JSONDecoder().decode([CategoryItem].self, from: Data(customJSON.utf8))) ?? []
        return (expenseCategories + incomeCategories + custom).first { $0.name == entry.category && $0.income == entry.income }?.emoji ?? "📌"
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(emoji).font(.title3)
                .frame(width: 42, height: 42).background((entry.income ? accent : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) { Text(entry.category).font(.body.weight(.medium)); if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
            Spacer(minLength: 4)
            Text((entry.income ? "+" : "−") + moneyText(entry.amount)).font(.body.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(14).contentShape(Rectangle())
    }
}

private struct Insights: View {
    @EnvironmentObject private var ledger: Ledger
    @State private var month = Date()
    @State private var showingSettings = false
    private var items: [Entry] { monthItems(ledger.entries, month) }
    private var categories: [(name: String, value: Double)] {
        let groups = Dictionary(grouping: items.filter { !$0.income }, by: \.category)
        return groups.map { (name: $0.key, value: ($0.value.reduce(Decimal.zero) { $0 + $1.amount } as NSDecimalNumber).doubleValue) }.sorted { $0.value > $1.value }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Button { shift(-1) } label: { Image(systemName: "chevron.left") }; Spacer(); Text(month, format: .dateTime.year().month()).font(.headline); Spacer(); Button { shift(1) } label: { Image(systemName: "chevron.right") } }.padding(.vertical, 10)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("支出分类").font(.headline)
                        if categories.isEmpty { Text("本月暂无支出，记一笔后即可查看统计。 ").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 25) }
                        else {
                            Chart(categories, id: \.name) { item in BarMark(x: .value("金额", item.value), y: .value("分类", item.name)).foregroundStyle(accent.gradient).cornerRadius(5) }
                                .frame(height: CGFloat(max(140, categories.count * 38)))
                            ForEach(categories, id: \.name) { item in HStack { Text(item.name); Spacer(); Text(moneyText(Decimal(item.value))).monospacedDigit() }.font(.subheadline) }
                        }
                    }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    Text("按账目分类汇总，仅统计所选月份的支出。 ").font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("统计")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("设置") } }
                .sheet(isPresented: $showingSettings) { Preferences() }
        }.tint(accent)
    }
    private func shift(_ n: Int) { if let next = Calendar.current.date(byAdding: .month, value: n, to: month) { month = next } }
}

private struct Preferences: View {
    @EnvironmentObject private var ledger: Ledger
    @AppStorage("monthlyBudget") private var budget = 0.0
    @State private var input = ""
    @State private var message = false
    @State private var exporting = false
    @State private var document = LedgerDocument(data: Data())
    var body: some View {
        NavigationStack {
            Form {
                Section("月度预算") {
                    HStack { Text("¥"); TextField("不设置", text: $input).keyboardType(.decimalPad) }
                    Button("保存预算") { let value = Double(input.replacingOccurrences(of: ",", with: ".")) ?? -1; if value >= 0 && value <= 999999999 { budget = value; message = true } }
                    Text(budget > 0 ? "当前预算：\(moneyText(Decimal(budget)))。输入 0 可关闭。" : "设置后，首页显示本月预算进度。") .font(.footnote).foregroundStyle(.secondary)
                }
                Section("数据与隐私") {
                    Label("数据保存在本机", systemImage: "iphone")
                    Button("导出账目备份") { do { document = LedgerDocument(data: try ledger.exportData()); exporting = true } catch { ledger.error = "读取账目失败，无法导出。" } }
                    Text("备份文件包含账目，请妥善保管。本版本暂不支持导入；删除 App 可能导致本地账目丢失。") .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于") { LabeledContent("版本", value: "2.0 测试版") }
            }.navigationTitle("设置").onAppear { input = budget > 0 ? String(format: "%.2f", budget) : "" }
                .alert("预算已保存", isPresented: $message) { Button("好", role: .cancel) {} }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "记账备份") { result in if case .failure = result { ledger.error = "导出失败，请重试。" } }
        }
    }
}

private struct LedgerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

