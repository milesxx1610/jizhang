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
    @AppStorage("categoryOrder") private var categoryOrder = "[]"
    @AppStorage("customEntryOptions") private var customOptionsJSON = "{}"
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
    @State private var showSort = false
    @State private var showEmoji = false
    @State private var sortedItems: [CategoryItem] = []
    @State private var previewRate: Decimal?
    @State private var previewKey = ""
    @State private var previewDate: String?
    @State private var rateLoading = false
    @State private var rateFailed = false
    @State private var customName = ""
    @State private var customEmoji = "✨"
    @State private var saved = false
    @State private var saving = false
    @FocusState private var amountFocused: Bool
    private var custom: [CategoryItem] { (try? JSONDecoder().decode([CategoryItem].self, from: Data(customJSON.utf8))) ?? [] }
    private var categories: [CategoryItem] {
        let all = (income ? incomeCategories : expenseCategories) + custom.filter { $0.income == income }
        let order = (try? JSONDecoder().decode([String].self, from: Data(categoryOrder.utf8))) ?? []
        let counts = Dictionary(grouping: ledger.entries.filter { $0.income == income }, by: \.category).mapValues(\.count)
        return all.enumerated().sorted { a, b in
            let ai = order.firstIndex(of: a.element.id), bi = order.firstIndex(of: b.element.id)
            if let ai, let bi { return ai < bi }; if ai != nil { return true }; if bi != nil { return false }
            let ac = counts[a.element.name] ?? 0, bc = counts[b.element.name] ?? 0
            return ac == bc ? a.offset < b.offset : ac > bc
        }.map(\.element)
    }
    private var visibleCategories: [CategoryItem] {
        if showAllCategories { return categories }
        let common = Array(categories.prefix(8))
        return common + categories.filter { $0.name == category && !common.contains($0) }
    }
    private let selectionColor = Color(red: 0.12, green: 0.52, blue: 0.44)
    private var rateKey: String { "\(currency)-\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)" }

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
        _showAllCategories = State(initialValue: false)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text("记录每一笔").font(.title2.bold()); Text("让每一份收支都有迹可循").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "sparkles").foregroundStyle(Color.accentColor) }
                    Picker("类型", selection: $income) { Text("支出").tag(false); Text("收入").tag(true) }.pickerStyle(.segmented).controlSize(.large).frame(maxWidth: 310).frame(maxWidth: .infinity).scaleEffect(x: 1, y: 1.25).padding(.vertical, 5)
                        .onChange(of: income) { _, _ in category = ""; detail = "" }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("金额").font(.subheadline).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Menu { ForEach(["CNY", "JPY", "USD"], id: \.self) { code in Button(code == "CNY" ? "人民币 CNY" : code == "JPY" ? "日元 JPY" : "美元 USD") { currency = code } } } label: { Text(currency == "USD" ? "$" : currency == "JPY" ? "JPY" : "¥").font(.title2.weight(.medium)).foregroundStyle(.secondary).fixedSize().contentTransition(.identity).transaction { $0.animation = nil } }.accessibilityLabel("选择货币，当前\(currency)")
                            TextField("0.00", text: $amount).keyboardType(.decimalPad).focused($amountFocused).font(.system(size: 38, weight: .bold, design: .rounded)).accessibilityLabel("金额").frame(minWidth: 60)
                            if currency != "CNY", previewKey == rateKey, let rate = previewRate, let value = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")), value > 0 { Text("≈ ¥\(NSDecimalNumber(decimal: value * rate).doubleValue.formatted(.number.precision(.fractionLength(2))))").font(.caption).foregroundStyle(.secondary).fixedSize() }
                        }
                        DatePicker("日期", selection: $date, displayedComponents: .date).font(.subheadline).padding(.top, 6)
                        if currency != "CNY" { HStack { Text(rateLoading ? "正在获取参考汇率…" : rateFailed ? "汇率获取失败，请检查网络。" : "按参考汇率折算，实际扣款可能不同。") .font(.caption).foregroundStyle(.secondary); if rateFailed { Button("重试") { Task { await loadPreviewRate() } }.font(.caption) } }.transition(.opacity.combined(with: .move(edge: .top))) }
                    }.animation(.spring(response: 0.36, dampingFraction: 0.86), value: currency != "CNY").padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    HStack { Text("分类").font(.headline); Spacer(); categoryMenu }
                    categoryGrid
                    if !category.isEmpty && !categories.contains(where: { $0.name == category }) { Text("原有分类：\(category)").font(.subheadline).foregroundStyle(.secondary) }
                    if !category.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("细分").font(.headline)
                            if !detailOptions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack { ForEach(detailOptions, id: \.self) { item in Button { detail = detail == item ? "" : item } label: { Text("\(detailEmoji(item)) \(item)") }.buttonStyle(.bordered).tint(detail == item ? selectionColor : .secondary) } }
                                }
                            }
                            TextField("其他细分", text: $detail).padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
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
                    Button { Task { await save() } } label: { Text(saving ? "正在获取汇率…" : "保存").font(.headline).frame(maxWidth: .infinity).frame(height: 68).foregroundStyle(Color(uiColor: .systemBackground)).background(Color(uiColor: .label), in: Capsule()) }.disabled(saving)
                        .buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 8)
                        .background(.regularMaterial)
                }
                .navigationTitle(embedded ? "" : "编辑账目")
                .navigationBarTitleDisplayMode(embedded ? .large : .inline)
                .toolbar { if !embedded { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } }
                .task(id: rateKey) { await loadPreviewRate() }
                .sheet(isPresented: $showSort) { sortSheet }
                .sheet(isPresented: $showCustom) {
                    NavigationStack {
                        Form {
                            Section("新分类") { TextField("名称，例如：猫粮", text: $customName); Button("选择图标 \(customEmoji)") { showEmoji = true }; TextField("或输入其他 Emoji", text: $customEmoji) }
                            Text("仅影响未来的分类选择，已有账目不会删除。长按自定义分类可删除。 ").font(.footnote).foregroundStyle(.secondary)
                        }.navigationTitle("自定义分类").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showCustom = false } }; ToolbarItem(placement: .confirmationAction) { Button("添加") { addCategory() }.disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
                    }.presentationDetents([.medium, .large]).sheet(isPresented: $showEmoji) { emojiSheet }
                }
                .alert("已记录", isPresented: $saved) { Button("好", role: .cancel) {} } message: { Text("账目已保存。") }
                .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private var categoryGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { ForEach(categories) { item in categoryButton(item) } } }
    }
    private var categoryMenu: some View {
        Menu {
            Button { customName = ""; customEmoji = "✨"; showCustom = true } label: { Label("自定义分类", systemImage: "plus.circle") }
            Button { sortedItems = categories; showSort = true } label: { Label("调整分类顺序", systemImage: "line.3.horizontal") }
            Divider()
            ForEach(categories) { item in
                Button { let same = category == item.name; category = same ? "" : item.name; detail = ""; merchant = "" } label: { Text("\(item.emoji)  \(item.name)\(category == item.name ? " ✓" : "")") }
            }
        } label: { Text("更多").foregroundStyle(.primary) }
    }
    private func categoryButton(_ item: CategoryItem) -> some View {
        Button {
            let wasSelected = category == item.name
            if category != item.name || wasSelected { detail = ""; merchant = "" }
            category = wasSelected ? "" : item.name; amountFocused = false
        } label: {
            HStack(spacing: 6) { Text(item.emoji); Text(item.name) }.font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 12)
                .foregroundStyle(category == item.name ? selectionColor : Color.primary)
                .background(category == item.name ? selectionColor.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().stroke(category == item.name ? selectionColor : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityLabel("\(item.name)\(category == item.name ? "，已选择" : "")")
            .contextMenu { if custom.contains(item) { Button("删除自定义分类", role: .destructive) { remove(item) } } }
    }
    private var categorySheet: some View {
        NavigationStack {
            List {
                Button { customName = ""; customEmoji = "✨"; showAllCategories = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCustom = true } } label: { Label("自定义分类", systemImage: "plus.circle") }
                Button { sortedItems = categories; showSort = true } label: { Label("调整分类顺序", systemImage: "line.3.horizontal") }
                ForEach(categories) { item in
                    Button { if category == item.name { category = "" } else { category = item.name }; detail = ""; merchant = ""; showAllCategories = false } label: { HStack { Text(item.emoji); Text(item.name); Spacer(); if category == item.name { Image(systemName: "checkmark").foregroundStyle(selectionColor) } } }
                        .contextMenu { if custom.contains(item) { Button("删除自定义分类", role: .destructive) { remove(item) } } }
                }
            }.navigationTitle("全部分类").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showAllCategories = false } } }
            .sheet(isPresented: $showSort) { sortSheet }
        }.presentationDetents([.medium, .large])
    }
    private var sortSheet: some View {
        NavigationStack {
            List { ForEach(sortedItems) { item in HStack { Text(item.emoji); Text(item.name) } }.onMove { sortedItems.move(fromOffsets: $0, toOffset: $1) } }
                .environment(\.editMode, .constant(.active)).navigationTitle("调整顺序")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { let ids = sortedItems.map(\.id); let old = (try? JSONDecoder().decode([String].self, from: Data(categoryOrder.utf8))) ?? []; let merged = ids + old.filter { !ids.contains($0) }; if let data = try? JSONEncoder().encode(merged), let string = String(data: data, encoding: .utf8) { categoryOrder = string }; showSort = false } } }
        }
    }
    private var emojiSheet: some View {
        NavigationStack { ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 18) { ForEach(["😀","✨","🍜","🍔","🍱","☕️","🥬","🍪","🚇","🚕","🛍️","👕","🏠","💡","📱","🎮","🏃","✈️","💊","📚","💻","🔁","🧧","🐈","🧻","🧴","💼","💰","🎁","🧾"], id: \.self) { symbol in Button(symbol) { customEmoji = symbol; showEmoji = false }.font(.largeTitle) } }.padding() }.navigationTitle("选择 Emoji").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showEmoji = false } } } }.presentationDetents([.medium, .large])
    }
    private var platformFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("平台").font(.headline)
            if !category.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(platformOptions + savedOptions("platform").filter { !platformOptions.contains($0) }, id: \.self) { item in Button { merchant = merchant == item ? "" : item } label: { Text("\(platformEmoji(item)) \(item)") }.buttonStyle(.bordered).tint(merchant == item ? selectionColor : .secondary) } } }
                TextField("其他平台", text: $merchant).padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("备注").font(.headline)
            TextField("写点什么", text: $note).padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            if !platform.isEmpty { TextField("旧版平台", text: $platform).padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14)) }
        }
    }
    private var platformOptions: [String] { category == "餐饮" ? ["美团", "饿了么", "大众点评"] : category == "购物" ? ["淘宝", "京东", "拼多多"] : category == "交通" || category == "打车" ? ["滴滴", "高德", "12306"] : [] }
    private func optionsKey(_ kind: String) -> String { "\(income)-\(category)-\(kind)" }
    private func savedOptions(_ kind: String) -> [String] { ((try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:])[optionsKey(kind)] ?? [] }
    private func rememberOptions() {
        var options = (try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:]
        for (kind, value) in [("detail", detail), ("platform", merchant)] {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { let key = optionsKey(kind); var values = options[key] ?? []; if !values.contains(clean) { values.append(clean) }; options[key] = values }
        }
        if let data = try? JSONEncoder().encode(options), let text = String(data: data, encoding: .utf8) { customOptionsJSON = text }
    }
    private func platformEmoji(_ name: String) -> String { ["美团":"🍱", "饿了么":"🥡", "大众点评":"⭐️", "淘宝":"🛍️", "京东":"📦", "拼多多":"🛒", "滴滴":"🚕", "高德":"🗺️", "12306":"🚄"][name] ?? "📍" }
    private func detailEmoji(_ name: String) -> String { ["早餐":"🌅", "午餐":"🍱", "晚餐":"🌙", "外卖":"🥡", "夜宵":"🌃", "蔬菜":"🥬", "水果":"🍎", "咖啡":"☕️", "奶茶":"🧋", "地铁":"🚇", "公交":"🚌", "火车":"🚄", "日用品":"🧻", "服饰":"👕", "房租":"🏠", "工资":"💼"][name] ?? "✨" }
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
    private struct RateReply: Decodable { let date: String; let rates: [String: Decimal] }
    @MainActor private func loadPreviewRate() async {
        let key = rateKey, selectedCurrency = currency, selectedDate = date
        previewRate = nil; previewDate = nil; previewKey = ""; rateFailed = false
        guard selectedCurrency != "CNY" else { rateLoading = false; return }
        if let old = entry, old.currency == selectedCurrency, Calendar.current.isDate(old.date, inSameDayAs: selectedDate), let rate = old.cnyRate { previewRate = rate; previewDate = old.rateDate; previewKey = key; rateLoading = false; return }
        rateLoading = true
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = Calendar.current.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: selectedDate)
        guard let url = URL(string: "https://api.frankfurter.dev/v1/\(day)?base=\(selectedCurrency)&symbols=CNY") else { rateLoading = false; rateFailed = true; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let result = try JSONDecoder().decode(RateReply.self, from: data)
            guard let rate = result.rates["CNY"], rate > 0 else { throw URLError(.cannotParseResponse) }
            guard !Task.isCancelled, key == rateKey else { return }
            previewRate = rate; previewDate = result.date; previewKey = key; rateLoading = false
        } catch { if !Task.isCancelled && key == rateKey { rateLoading = false; rateFailed = true } }
    }
    @MainActor private func save() async {
        let clean = amount.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !clean.isEmpty, clean.allSatisfy({ $0.isNumber || $0 == "." }), parts.count == 1 || parts[1].count <= 2, let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")), value > 0, value <= 999999999 else { error = "请输入大于零的金额，最多两位小数。"; return }
        guard !category.isEmpty else { error = "请选择分类。"; return }
        saving = true
        defer { saving = false }
        var rate: Decimal? = nil
        var usedDate: String? = nil
        if currency != "CNY" {
            guard previewKey == rateKey, let currentRate = previewRate else { error = "汇率尚未获取，请检查网络并重试。账目尚未保存。"; return }
            rate = currentRate; usedDate = previewDate
        }
        let updated = Entry(id: entry?.id ?? UUID(), amount: value, category: category, note: note.trimmingCharacters(in: .whitespacesAndNewlines), date: date, income: income, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), platform: platform.trimmingCharacters(in: .whitespacesAndNewlines), merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), payment: payment.trimmingCharacters(in: .whitespacesAndNewlines), currency: currency, cnyRate: rate, rateDate: usedDate)
        var all = ledger.entries
        if let index = all.firstIndex(where: { $0.id == updated.id }) { all[index] = updated } else { all.append(updated) }
        if ledger.save(all) { rememberOptions(); if embedded { amount = ""; note = ""; category = ""; detail = ""; platform = ""; merchant = ""; payment = ""; date = Date(); error = nil; amountFocused = false; saved = true } else { dismiss() } }
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
        let defaults = options[category] ?? []
        return defaults + savedOptions("detail").filter { !defaults.contains($0) }
    }
}

