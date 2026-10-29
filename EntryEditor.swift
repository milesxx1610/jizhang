import SwiftUI

struct CategoryItem: Codable, Identifiable, Equatable {
    var name: String
    var emoji: String
    var income: Bool
    var id: String { "\(income)-\(name)" }
}

let expenseCategories: [CategoryItem] = [
    ("餐饮", "🍜"), ("买菜", "🥬"), ("咖啡饮品", "☕️"), ("零食", "🍪"), ("交通", "🚇"), ("打车", "🚕"),
    ("购物", "🛍️"), ("衣服", "👕"), ("住房", "🏠"), ("水电", "💡"), ("通讯", "📱"), ("娱乐", "🎮"),
    ("运动", "🏃"), ("旅行", "✈️"), ("医疗", "💊"), ("学习", "📚"), ("数码", "💻"), ("订阅", "🔁"),
    ("人情", "🧧"), ("宠物", "🐈"), ("日用", "🧻"), ("美容", "🧴"), ("家庭", "👪"), ("其他", "📦")
].map { CategoryItem(name: $0.0, emoji: $0.1, income: false) }
let incomeCategories: [CategoryItem] = [
    ("工资", "💼"), ("兼职", "🧑‍💻"), ("生活费", "💰"), ("奖金", "🎁"), ("退款", "↩️"), ("报销", "🧾"),
    ("红包", "🧧"), ("理财", "📈"), ("出售", "🏷️"), ("其他收入", "✨")
].map { CategoryItem(name: $0.0, emoji: $0.1, income: true) }

struct EntryEditor: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    @AppStorage("customCategories") private var customJSON = "[]"
    let entry: Entry?
    let embedded: Bool
    @State private var amount: String
    @State private var category: String
    @State private var note: String
    @State private var date: Date
    @State private var income: Bool
    @State private var error: String?
    @State private var showCustom = false
    @State private var customName = ""
    @State private var customEmoji = "✨"
    @State private var saved = false
    @FocusState private var amountFocused: Bool
    private var custom: [CategoryItem] { (try? JSONDecoder().decode([CategoryItem].self, from: Data(customJSON.utf8))) ?? [] }
    private var categories: [CategoryItem] { (income ? incomeCategories : expenseCategories) + custom.filter { $0.income == income } }
    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    init(entry: Entry?, embedded: Bool = false) {
        self.entry = entry; self.embedded = embedded
        _amount = State(initialValue: entry.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _category = State(initialValue: entry?.category ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _date = State(initialValue: entry?.date ?? Date())
        _income = State(initialValue: entry?.income ?? false)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("类型", selection: $income) { Text("支出").tag(false); Text("收入").tag(true) }.pickerStyle(.segmented)
                        .onChange(of: income) { _, _ in category = "" }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("金额").font(.subheadline).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text("¥").font(.title2.weight(.medium)).foregroundStyle(.secondary)
                            TextField("0.00", text: $amount).keyboardType(.decimalPad).focused($amountFocused).font(.system(size: 38, weight: .bold, design: .rounded)).accessibilityLabel("金额")
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    HStack { Text("分类").font(.headline); Spacer(); Button { customName = ""; customEmoji = "✨"; showCustom = true } label: { Label("自定义", systemImage: "plus") }.font(.subheadline) }
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(categories) { item in
                            Button { category = item.name; amountFocused = false } label: {
                                VStack(spacing: 6) {
                                    Text(item.emoji).font(.title2).frame(width: 52, height: 52)
                                        .background(category == item.name ? Color.accentColor.opacity(0.2) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
                                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(category == item.name ? Color.accentColor : .clear, lineWidth: 2))
                                    Text(item.name).font(.caption).foregroundStyle(.primary).lineLimit(1)
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).accessibilityLabel("\(item.name)\(category == item.name ? "，已选择" : "")")
                                .contextMenu { if custom.contains(item) { Button("删除自定义分类", role: .destructive) { remove(item) } } }
                        }
                    }
                    if !category.isEmpty && !categories.contains(where: { $0.name == category }) { Text("原有分类：\(category)").font(.subheadline).foregroundStyle(.secondary) }
                    VStack(spacing: 0) {
                        DatePicker("日期", selection: $date, displayedComponents: .date).padding(16)
                        Divider().padding(.leading, 16)
                        TextField("备注（选填）", text: $note).padding(16)
                    }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(20).padding(.bottom, 24)
            }.background(Color(uiColor: .systemGroupedBackground))
                .safeAreaInset(edge: .bottom) {
                    Button(action: save) { Text(entry == nil ? "保存账目" : "保存修改").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 8) }
                        .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 20).padding(.vertical, 8)
                        .background(.regularMaterial)
                }
                .navigationTitle(entry == nil ? "记一笔" : "编辑账目")
                .navigationBarTitleDisplayMode(embedded ? .large : .inline)
                .toolbar { if !embedded { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } }
                .sheet(isPresented: $showCustom) {
                    NavigationStack {
                        Form {
                            Section("新分类") { TextField("名称，例如：猫粮", text: $customName); TextField("Emoji，例如 🐱", text: $customEmoji) }
                            Text("仅影响未来的分类选择，已有账目不会删除。长按自定义分类可删除。 ").font(.footnote).foregroundStyle(.secondary)
                        }.navigationTitle("自定义分类").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showCustom = false } }; ToolbarItem(placement: .confirmationAction) { Button("添加") { addCategory() }.disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
                    }.presentationDetents([.medium, .large])
                }
                .alert("已记录", isPresented: $saved) { Button("好", role: .cancel) {} } message: { Text("账目已保存。") }
                .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func addCategory() {
        let name = String(customName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !name.isEmpty else { return }
        if categories.contains(where: { $0.name == name }) { category = name; showCustom = false; return }
        let symbol = String(customEmoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
        var all = custom; all.append(CategoryItem(name: name, emoji: symbol.isEmpty ? "✨" : symbol, income: income))
        if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { customJSON = text; category = name; showCustom = false }
    }
    private func remove(_ item: CategoryItem) {
        let all = custom.filter { $0 != item }
        if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { customJSON = text; if category == item.name { category = "" } }
    }
    private func save() {
        let clean = amount.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !clean.isEmpty, clean.allSatisfy({ $0.isNumber || $0 == "." }), parts.count == 1 || parts[1].count <= 2, let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")), value > 0, value <= 999999999 else { error = "请输入大于零的金额，最多两位小数。"; return }
        guard !category.isEmpty else { error = "请选择分类。"; return }
        let updated = Entry(id: entry?.id ?? UUID(), amount: value, category: category, note: note.trimmingCharacters(in: .whitespacesAndNewlines), date: date, income: income)
        var all = ledger.entries
        if let index = all.firstIndex(where: { $0.id == updated.id }) { all[index] = updated } else { all.append(updated) }
        if ledger.save(all) { if embedded { amount = ""; note = ""; category = ""; date = Date(); error = nil; amountFocused = false; saved = true } else { dismiss() } }
        else { error = "保存失败，请重试。" }
    }
}

