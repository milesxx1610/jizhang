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
    @State private var detail: String
    @State private var platform: String
    @State private var merchant: String
    @State private var payment: String
    @State private var currency: String
    @State private var showAllCategories = false
    @State private var error: String?
    @State private var showCustom = false
    @State private var customName = ""
    @State private var customEmoji = "✨"
    @State private var saved = false
    @FocusState private var amountFocused: Bool
    private var custom: [CategoryItem] { (try? JSONDecoder().decode([CategoryItem].self, from: Data(customJSON.utf8))) ?? [] }
    private var categories: [CategoryItem] { (income ? incomeCategories : expenseCategories) + custom.filter { $0.income == income } }
    private var visibleCategories: [CategoryItem] {
        if showAllCategories { return categories }
        let common = Array(categories.prefix(8))
        return common + categories.filter { $0.name == category && !common.contains($0) }
    }
    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    init(entry: Entry?, embedded: Bool = false) {
        self.entry = entry; self.embedded = embedded
        _amount = State(initialValue: entry.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _category = State(initialValue: entry?.category ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _date = State(initialValue: entry?.date ?? Date())
        _income = State(initialValue: entry?.income ?? false)
        _detail = State(initialValue: entry?.detail ?? "")
        _platform = State(initialValue: entry?.platform ?? "")
        _merchant = State(initialValue: entry?.merchant ?? "")
        _payment = State(initialValue: entry?.payment ?? "")
        _currency = State(initialValue: entry?.currency ?? "CNY")
        _showAllCategories = State(initialValue: entry != nil)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text("记录每一笔").font(.title2.bold()); Text("让每一份收支都有迹可循").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "sparkles").foregroundStyle(Color.accentColor) }
                    Picker("类型", selection: $income) { Text("支出").tag(false); Text("收入").tag(true) }.pickerStyle(.segmented)
                        .onChange(of: income) { _, _ in category = ""; detail = "" }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("金额").font(.subheadline).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Menu { ForEach(["CNY", "JPY", "USD"], id: \.self) { code in Button(code == "CNY" ? "人民币 CNY" : code == "JPY" ? "日元 JPY" : "美元 USD") { currency = code } } } label: { Text(currency == "USD" ? "$" : "¥").font(.title2.weight(.medium)).foregroundStyle(.secondary) }.accessibilityLabel("选择货币，当前\(currency)")
                            TextField("0.00", text: $amount).keyboardType(.decimalPad).focused($amountFocused).font(.system(size: 38, weight: .bold, design: .rounded)).accessibilityLabel("金额")
                        }
                        DatePicker("日期", selection: $date, displayedComponents: .date).font(.caption).padding(.top, 6)
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    HStack { Text("分类").font(.headline); Spacer(); Button(showAllCategories ? "收起" : "更多") { withAnimation(.easeInOut) { showAllCategories.toggle() } } }
                    categoryGrid
                    if showAllCategories { Button { customName = ""; customEmoji = "✨"; showCustom = true } label: { Label("自定义", systemImage: "plus") } }
                    if !category.isEmpty && !categories.contains(where: { $0.name == category }) { Text("原有分类：\(category)").font(.subheadline).foregroundStyle(.secondary) }
                    if !category.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("细分类").font(.headline); Text("可选").font(.caption).foregroundStyle(.secondary) }
                            if !detailOptions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack { ForEach(detailOptions, id: \.self) { item in Button(item) { detail = item } .buttonStyle(.bordered).tint(detail == item ? Color.accentColor : .secondary) } }
                                }
                            }
                            TextField("其他细分类（可自己填写）", text: $detail).textFieldStyle(.roundedBorder)
                        }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }
                    platformFields
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(20).padding(.bottom, 24)
            }.background(Color(uiColor: .systemGroupedBackground))
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { amountFocused = false }
                .sensoryFeedback(.selection, trigger: amount)
                .sensoryFeedback(.selection, trigger: category)
                .sensoryFeedback(.success, trigger: saved)
                .safeAreaInset(edge: .bottom) {
                    Button(action: save) { Text("保存").font(.headline).frame(maxWidth: .infinity).frame(height: 68).foregroundStyle(Color(uiColor: .systemBackground)).background(Color.primary, in: Capsule()) }
                        .buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 8)
                        .background(.regularMaterial)
                }
                .navigationTitle(embedded ? "" : "编辑账目")
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
    private var categoryGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(visibleCategories) { item in
                Button { if category != item.name { detail = "" }; category = item.name; amountFocused = false } label: {
                    HStack(spacing: 4) { Text(item.emoji); Text(item.name).lineLimit(1).minimumScaleFactor(0.7) }.font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 12).background(category == item.name ? Color(uiColor: .tertiarySystemFill) : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("\(item.name)\(category == item.name ? "，已选择" : "")")
                    .contextMenu { if custom.contains(item) { Button("删除自定义分类", role: .destructive) { remove(item) } } }
            }
        }
    }
    private var platformFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("消费平台（选填）").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(category == "餐饮" ? ["美团", "饿了么", "线下"] : category == "购物" ? ["淘宝", "京东", "拼多多", "线下"] : ["线下", "线上"], id: \.self) { item in Button(item) { merchant = item }.buttonStyle(.bordered).tint(merchant == item ? .primary : .secondary) } } }
            TextField("其他消费平台", text: $merchant).textFieldStyle(.roundedBorder)
            TextField("备注（选填）", text: $note).textFieldStyle(.roundedBorder)
            if !platform.isEmpty { TextField("旧版平台", text: $platform).textFieldStyle(.roundedBorder) }
        }
    }
    private var moreFields: some View {
        DisclosureGroup("更多信息（选填）") {
            VStack(spacing: 0) {
                DatePicker("日期", selection: $date, displayedComponents: .date).padding(16)
                Divider()
                HStack { Text("购买平台"); Spacer(); Menu { ForEach(["淘宝", "京东", "拼多多", "美团", "线下"], id: \.self) { item in Button(item) { merchant = item } } } label: { Text(merchant.isEmpty ? "选择" : merchant).foregroundStyle(.secondary) } }.padding(16)
                TextField("其他购买平台（可填写）", text: $merchant).padding(.horizontal, 16).padding(.bottom, 16)
                Divider()
                HStack { Text("支付方式"); Spacer(); Menu { ForEach(["微信", "支付宝", "银行卡", "现金", "Apple Pay"], id: \.self) { item in Button(item) { payment = item } } } label: { Text(payment.isEmpty ? "选择" : payment).foregroundStyle(.secondary) } }.padding(16)
                TextField("其他支付方式（可填写）", text: $payment).padding(.horizontal, 16).padding(.bottom, 16)
                if !platform.isEmpty { Divider(); TextField("旧版平台", text: $platform).padding(16) }
                Divider()
                TextField("备注（选填）", text: $note).padding(16)
            }
        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
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
        let updated = Entry(id: entry?.id ?? UUID(), amount: value, category: category, note: note.trimmingCharacters(in: .whitespacesAndNewlines), date: date, income: income, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), platform: platform.trimmingCharacters(in: .whitespacesAndNewlines), merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), payment: payment.trimmingCharacters(in: .whitespacesAndNewlines), currency: currency)
        var all = ledger.entries
        if let index = all.firstIndex(where: { $0.id == updated.id }) { all[index] = updated } else { all.append(updated) }
        if ledger.save(all) { if embedded { amount = ""; note = ""; category = ""; detail = ""; platform = ""; merchant = ""; payment = ""; date = Date(); error = nil; amountFocused = false; saved = true } else { dismiss() } }
        else { error = "保存失败，请重试。" }
    }
    private var detailOptions: [String] {
        let options: [String: [String]] = [
            "餐饮": ["早餐", "午餐", "晚餐", "外卖", "夜宵"], "买菜": ["蔬菜", "水果", "肉蛋", "超市"],
            "咖啡饮品": ["咖啡", "奶茶", "饮料"], "交通": ["地铁", "公交", "火车", "共享单车"],
            "购物": ["日用品", "服饰", "电子产品", "礼物", "其他"], "住房": ["房租", "物业", "维修"],
            "水电": ["水费", "电费", "燃气"], "娱乐": ["游戏", "电影", "音乐", "聚会"],
            "学习": ["课程", "书籍", "文具", "考试"], "医疗": ["挂号", "药品", "检查"],
            "旅行": ["机票", "住宿", "门票"], "订阅": ["软件", "影音", "云服务"],
            "工资": ["基本工资", "绩效", "补贴"], "兼职": ["项目", "劳务"], "退款": ["购物退款", "其他退款"]
        ]
        return options[category] ?? []
    }
}

