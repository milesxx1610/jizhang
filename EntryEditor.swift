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

private struct RevealBlur: ViewModifier {
    let radius: CGFloat
    let scale: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius).scaleEffect(scale, anchor: .center) }
}
private struct ViewportBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct OptionsBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct EntryEditor: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("customCategories") private var customJSON = "[]"
    @AppStorage("categoryOrder") private var categoryOrder = "[]"
    @AppStorage("customEntryOptions") private var customOptionsJSON = "{}"
    @AppStorage("customOptionEmoji") private var customOptionEmojiJSON = "{}"
    let entry: Entry?
    let embedded: Bool
    let tabSelection: Int?
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
    @State private var showCurrency = false
    @State private var viewportBottom: CGFloat = 0
    @State private var optionsBottom: CGFloat = 0
    @State private var showOptionSort = false
    @State private var showCustomOption = false
    @State private var customOptionKind = ""
    @State private var optionSortKind = ""
    @State private var optionSortItems: [String] = []
    @Namespace private var typeSelection
    @State private var typeDrag: CGFloat = 0
    @State private var sortedItems: [CategoryItem] = []
    @State private var previewRate: Decimal?
    @State private var previewKey = ""
    @State private var previewDate: String?
    @State private var rateLoading = false
    @State private var rateFailed = false
    @State private var customName = ""
    @State private var customEmoji = ""
    @State private var saved = false
    @State private var saving = false
    @State private var keyboardVisible = false
    @State private var holdDetailFieldUntilKeyboardHides = false
    @State private var holdPlatformFieldUntilKeyboardHides = false
    @State private var deleteName: String?
    @State private var deleteKind = ""
    @FocusState private var amountFocused: Bool
    @FocusState private var detailFocused: Bool
    @FocusState private var platformFocused: Bool
    private func dismissKeyboard() {
        amountFocused = false; detailFocused = false; platformFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    private func selectionFeedback() { UISelectionFeedbackGenerator().selectionChanged() }
    private var custom: [CategoryItem] { (try? JSONDecoder().decode([CategoryItem].self, from: Data(customJSON.utf8))) ?? [] }
    private var hiddenCategories: [String] { ((try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:])["hiddenCategories"] ?? [] }
    private var categories: [CategoryItem] {
        let all = ((income ? incomeCategories : expenseCategories) + custom.filter { $0.income == income }).filter { !hiddenCategories.contains($0.id) }
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

    init(entry: Entry?, embedded: Bool = false, tabSelection: Int? = nil) {
        self.entry = entry; self.embedded = embedded; self.tabSelection = tabSelection
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
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("让每一份收支都有迹可循").font(.subheadline).foregroundStyle(.secondary)
                    typeToggle
                        .onChange(of: income) { _, _ in category = ""; detail = "" }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("金额").font(.subheadline).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Button { amountFocused = false; showCurrency = true } label: {
                                Text(currency == "USD" ? "$" : currency == "JPY" ? "JPY" : "¥")
                                    .font(.system(size: 27, weight: .medium)).foregroundStyle(.secondary)
                                    .contentTransition(.opacity)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currency)
                                    .fixedSize()
                            }
                            .buttonStyle(.plain).accessibilityLabel("选择货币，当前\(currency)")
                            .popover(isPresented: $showCurrency, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                currencyPicker.presentationCompactAdaptation(.popover)
                            }
                            TextField("0.00", text: $amount).keyboardType(.decimalPad).focused($amountFocused).font(.system(size: 38, weight: .bold, design: .rounded)).accessibilityLabel("金额").frame(minWidth: 60)
                            if currency != "CNY", previewKey == rateKey, let rate = previewRate, let value = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")), value > 0 { Text("≈ ¥\(NSDecimalNumber(decimal: value * rate).doubleValue.formatted(.number.precision(.fractionLength(2))))").font(.caption).foregroundStyle(.secondary).fixedSize() }
                            if amountFocused && !amount.isEmpty { Button { amount = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("清除金额") }
                        }
                        DatePicker("日期", selection: $date, displayedComponents: .date).font(.subheadline).padding(.top, 6)
                        if currency != "CNY" {
                            VStack(alignment: .leading, spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(rateLoading ? "正在获取参考汇率…" : rateFailed ? "汇率获取失败，请检查网络。" : "按参考汇率折算，实际扣款可能不同。")
                                        if rateFailed { Button("重试") { Task { await loadPreviewRate() } } }
                                    }
                                    let hasRate = !rateLoading && !rateFailed && previewKey == rateKey && previewRate != nil
                                    Text(hasRate ? "参考汇率：1 \(currency) = \(NSDecimalNumber(decimal: previewRate ?? 0).stringValue) CNY" : " ")
                                        .contentTransition(.opacity)
                                        .opacity(hasRate ? 1 : 0)
                                        .accessibilityHidden(!hasRate)
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currency)
                            .transition(revealTransition)
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    HStack { Text("分类").font(.headline); Spacer(); categoryMenu }
                    categoryGrid
                    if !category.isEmpty && !categories.contains(where: { $0.name == category }) { Text("原有分类：\(category)").font(.subheadline).foregroundStyle(.secondary) }
                    if !category.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("细分").font(.headline); Spacer(); optionMenu(kind: "detail") }
                            if !detailOptions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack { ForEach(detailOptions, id: \.self) { item in Button {
                                        if keyboardVisible && !detailOptions.contains(detail) {
                                            holdDetailFieldUntilKeyboardHides = true
                                            dismissKeyboard()
                                        }
                                        detail = detail == item ? "" : item; selectionFeedback()
                                    } label: { Text("\(detailEmoji(item)) \(item)") }.buttonStyle(.bordered).tint(detail == item ? selectionColor : .secondary).contextMenu { Button("删除细分", role: .destructive) { deleteKind = "detail"; deleteName = item } } } }.padding(.horizontal, 20)
                                }.padding(.horizontal, -20)
                            }
                            Group {
                                if !detailOptions.contains(detail) || holdDetailFieldUntilKeyboardHides {
                                    TextField("其他细分", text: $detail).focused($detailFocused).padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                        .transition(revealTransition)
                                }
                            }.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: !detailOptions.contains(detail) || holdDetailFieldUntilKeyboardHides)
                        }.transition(revealTransition)
                    }
                    platformFields
                }.padding(20).padding(.bottom, 24)
                    .modifier(TabArrival(selected: tabSelection ?? -1, tab: 1, showsBackground: false))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currency != "CNY")
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: category.isEmpty)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: category)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: allPlatforms.contains(merchant))
            }.background(GeometryReader { geometry in
                Color.clear.preference(key: ViewportBottomKey.self, value: geometry.frame(in: .global).maxY)
            })
                .onPreferenceChange(ViewportBottomKey.self) { viewportBottom = $0 }
                .onPreferenceChange(OptionsBottomKey.self) { optionsBottom = $0 }
                .onChange(of: category) { oldValue, newValue in
                    guard oldValue.isEmpty, !newValue.isEmpty else { return }
                    Task { @MainActor in
                        // Wait for the inserted content to acquire its final layout.
                        try? await Task.sleep(for: .milliseconds(250))
                        guard category == newValue, optionsBottom > viewportBottom else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            proxy.scrollTo("platform-end", anchor: .bottom)
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .modifier(SoftTopScrollEdge())
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { dismissKeyboard() }
                .sensoryFeedback(.selection, trigger: amount)
                .sensoryFeedback(.selection, trigger: category)
                .sensoryFeedback(.selection, trigger: income)
                .sensoryFeedback(.success, trigger: saved)
                .safeAreaInset(edge: .bottom) {
                    if !keyboardVisible {
                        Button { Task { await save() } } label: { Text(saving ? "正在获取汇率…" : "保存").font(.headline).frame(maxWidth: .infinity).frame(height: 68).foregroundStyle(Color(uiColor: .systemBackground)).background(Color(uiColor: .label), in: Capsule()) }.disabled(saving)
                            .buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                    holdDetailFieldUntilKeyboardHides = false
                    holdPlatformFieldUntilKeyboardHides = false
                }
                .navigationTitle(embedded ? "记账" : "编辑账目")
                .navigationBarTitleDisplayMode(embedded ? .large : .inline)
                .toolbar { if !embedded { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } }
                .task(id: rateKey) { await loadPreviewRate() }
                .sheet(isPresented: $showSort) { sortSheet }
                .sheet(isPresented: $showOptionSort) { optionSortSheet }
                .sheet(isPresented: $showCustomOption) { customOptionSheet }
                .sheet(isPresented: $showCustom) {
                    NavigationStack {
                        Form {
                            Section("新分类") { TextField("名称，例如：猫粮", text: $customName); iconInput }
                            Text("仅影响未来的分类选择，已有账目不会删除。长按自定义分类可删除。 ").font(.footnote).foregroundStyle(.secondary)
                        }.scrollDismissesKeyboard(.interactively).onTapGesture { dismissKeyboard() }
                            .navigationTitle("自定义分类").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showCustom = false } }; ToolbarItem(placement: .confirmationAction) { Button("添加") { addCategory() }.disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
                    }.presentationDetents([.medium, .large])
                }
                .alert("删除「\(deleteName ?? "")」？", isPresented: Binding(get: { deleteName != nil }, set: { if !$0 { deleteName = nil } })) {
                    Button("取消", role: .cancel) { deleteName = nil }
                    Button("删除", role: .destructive) { if let name = deleteName { deleteOption(name, kind: deleteKind) }; deleteName = nil }
                } message: { Text("只从选择列表中移除，不会删除或修改已有账目。") }
                .alert("已记录", isPresented: $saved) { Button("好", role: .cancel) {} } message: { Text("账目已保存。") }
                .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) { error = nil } } message: { Text(error ?? "") }
            }
        }
    }
    private var currencyPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择货币").font(.headline).padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            ForEach([("CNY", "人民币 CNY"), ("JPY", "日元 JPY"), ("USD", "美元 USD")], id: \.0) { option in
                Button {
                    showCurrency = false
                    if currency != option.0 { selectionFeedback() }
                    currency = option.0
                } label: {
                    HStack { Text(option.1); Spacer(); if currency == option.0 { Image(systemName: "checkmark") } }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).padding(.horizontal, 16).padding(.vertical, 12)
                }.buttonStyle(.plain)
            }
        }.frame(width: 200).padding(.bottom, 8)
    }
    private var typeToggle: some View {
        GeometryReader { geometry in
            let width = (geometry.size.width - 6) / 2
            let offset = min(max((income ? width : 0) + typeDrag, 0), width)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(uiColor: .tertiarySystemFill))
                Capsule().fill(selectionColor).frame(width: width, height: 44).offset(x: 3 + offset)
                HStack(spacing: 0) {
                    ForEach([false, true], id: \.self) { value in
                        Button { withAnimation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.9)) { income = value } } label: {
                            Text(value ? "收入" : "支出").font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .foregroundStyle(income == value ? Color.white : Color.secondary)
                                .contentShape(Rectangle().inset(by: -8))
                        }.buttonStyle(.plain).accessibilityAddTraits(income == value ? .isSelected : [])
                    }
                }.padding(3)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 3)
                .onChanged { value in
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { typeDrag = value.translation.width }
                }
                .onEnded { value in
                    let target = min(max((income ? width : 0) + value.translation.width, 0), width) > width / 2
                    withAnimation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.9)) {
                        income = target
                        typeDrag = 0
                    }
                })
        }.frame(height: 50).frame(maxWidth: 310).frame(maxWidth: .infinity)
    }
    private var categoryGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { ForEach(categories) { item in categoryButton(item) } }.padding(.horizontal, 20) }.padding(.horizontal, -20)
    }
    private var categoryMenu: some View {
        Menu {
            Button { customName = ""; customEmoji = ""; showCustom = true } label: { Label("自定义分类", systemImage: "plus.circle") }
            Button { sortedItems = categories; showSort = true } label: { Label("调整分类顺序", systemImage: "line.3.horizontal") }
            if hiddenCategories.contains(where: { $0.hasPrefix("\(income)-") }) { Button("恢复已删除分类") { restoreCategories() } }
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
        }.buttonStyle(.plain).accessibilityLabel("\(item.name)\(category == item.name ? "，已选择" : "")")
            .contextMenu { Button("删除分类", role: .destructive) { deleteKind = "category"; deleteName = item.name } }
    }
    private var categorySheet: some View {
        NavigationStack {
            List {
                Button { customName = ""; customEmoji = ""; showAllCategories = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCustom = true } } label: { Label("自定义分类", systemImage: "plus.circle") }
                Button { sortedItems = categories; showSort = true } label: { Label("调整分类顺序", systemImage: "line.3.horizontal") }
                ForEach(categories) { item in
                    Button { if category == item.name { category = "" } else { category = item.name }; detail = ""; merchant = ""; showAllCategories = false } label: { HStack { Text(item.emoji); Text(item.name); Spacer(); if category == item.name { Image(systemName: "checkmark").foregroundStyle(selectionColor) } } }
                        .contextMenu { Button("删除分类", role: .destructive) { deleteKind = "category"; deleteName = item.name } }
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
    private var iconInput: some View {
        HStack {
            Text("图标")
            TextField("✨ 输入图标", text: $customEmoji)
                .keyboardType(.default)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("输入图标")
        }
    }
    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .modifier(active: RevealBlur(radius: 3, scale: 0.985), identity: RevealBlur(radius: 0, scale: 1))),
            removal: .opacity
        )
    }
    private var platformFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !category.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                HStack { Text("平台").font(.headline); Spacer(); optionMenu(kind: "platform") }
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(allPlatforms, id: \.self) { item in Button {
                    if keyboardVisible && !allPlatforms.contains(merchant) {
                        holdPlatformFieldUntilKeyboardHides = true
                        dismissKeyboard()
                    }
                    merchant = merchant == item ? "" : item; selectionFeedback()
                } label: { Text("\(platformEmoji(item)) \(item)") }.buttonStyle(.bordered).tint(merchant == item ? selectionColor : .secondary).contextMenu { Button("删除平台", role: .destructive) { deleteKind = "platform"; deleteName = item } } } }.padding(.horizontal, 20) }.padding(.horizontal, -20)
                if !allPlatforms.contains(merchant) || holdPlatformFieldUntilKeyboardHides {
                    TextField("其他平台", text: $merchant).focused($platformFocused).padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        .transition(revealTransition)
                }
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: OptionsBottomKey.self, value: geometry.frame(in: .global).maxY)
                })
                .id("platform-end")
                .transition(revealTransition)
            }
            Text("备注").font(.headline)
            TextField("写点什么", text: $note).padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            if !platform.isEmpty { TextField("旧版平台", text: $platform).padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14)) }
        }
    }
    private func optionMenu(kind: String) -> some View {
        let options = kind == "detail" ? detailOptions : allPlatforms
        return Menu {
            Button { customOptionKind = kind; customName = ""; customEmoji = ""; showCustomOption = true } label: { Label("自定义", systemImage: "plus.circle") }
            Button { optionSortKind = kind; optionSortItems = options; showOptionSort = true } label: { Label("调整顺序", systemImage: "line.3.horizontal") }
            if !savedOptions(kind + "Hidden").isEmpty { Button("恢复已删除选项") { setSavedOptions([], kind: kind + "Hidden") } }
            Divider()
            ForEach(options, id: \.self) { item in
                Button { if kind == "detail" { detail = detail == item ? "" : item } else { merchant = merchant == item ? "" : item }; selectionFeedback() } label: { Text("\(kind == "detail" ? detailEmoji(item) : platformEmoji(item))  \(item)") }
            }
        } label: { Text("更多").foregroundStyle(.primary) }
    }
    private var customOptionSheet: some View {
        NavigationStack {
            Form {
                Section(customOptionKind == "detail" ? "新细分" : "新平台") {
                    TextField("名称", text: $customName)
                    iconInput
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { dismissKeyboard() }
            .navigationTitle(customOptionKind == "detail" ? "自定义细分" : "自定义平台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showCustomOption = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { addCustomOption() }
                        .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.presentationDetents([.medium, .large])
    }
    private func addCustomOption() {
        let name = String(customName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !name.isEmpty else { return }
        let kind = customOptionKind
        let hidden = savedOptions(kind + "Hidden")
        if hidden.contains(name) { setSavedOptions(hidden.filter { $0 != name }, kind: kind + "Hidden") }
        let existing = kind == "detail" ? detailOptions : allPlatforms
        if !existing.contains(name) {
            var options = (try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:]
            options[optionsKey(kind), default: []].append(name)
            guard let data = try? JSONEncoder().encode(options), let text = String(data: data, encoding: .utf8) else { return }
            customOptionsJSON = text
            var icons = (try? JSONDecoder().decode([String: String].self, from: Data(customOptionEmojiJSON.utf8))) ?? [:]
            let symbol = String(customEmoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
            icons[optionsKey(kind) + "-" + name] = symbol.isEmpty ? "✨" : symbol
            if let data = try? JSONEncoder().encode(icons), let text = String(data: data, encoding: .utf8) { customOptionEmojiJSON = text }
        }
        if kind == "detail" { detail = name } else { merchant = name }
        selectionFeedback()
        showCustomOption = false
    }
    private func removeCustomOption(_ name: String, kind: String) {
        var options = (try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:]
        let key = optionsKey(kind)
        options[key]?.removeAll { $0 == name }
        if let data = try? JSONEncoder().encode(options), let text = String(data: data, encoding: .utf8) { customOptionsJSON = text }
        var icons = (try? JSONDecoder().decode([String: String].self, from: Data(customOptionEmojiJSON.utf8))) ?? [:]
        icons.removeValue(forKey: key + "-" + name)
        if let data = try? JSONEncoder().encode(icons), let text = String(data: data, encoding: .utf8) { customOptionEmojiJSON = text }
        if kind == "detail" && detail == name { detail = "" }
        if kind == "platform" && merchant == name { merchant = "" }
    }
    private func customOptionEmoji(_ name: String, kind: String) -> String? {
        let icons = (try? JSONDecoder().decode([String: String].self, from: Data(customOptionEmojiJSON.utf8))) ?? [:]
        return icons[optionsKey(kind) + "-" + name]
    }
    private var optionSortSheet: some View {
        NavigationStack {
            List { ForEach(optionSortItems, id: \.self) { item in Text("\(optionSortKind == "detail" ? detailEmoji(item) : platformEmoji(item))  \(item)") }.onMove { optionSortItems.move(fromOffsets: $0, toOffset: $1) } }
                .environment(\.editMode, .constant(.active)).navigationTitle("调整顺序")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") {
                    var values = (try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:]
                    values[optionsKey(optionSortKind + "Order")] = optionSortItems
                    if let data = try? JSONEncoder().encode(values), let text = String(data: data, encoding: .utf8) { customOptionsJSON = text }
                    showOptionSort = false
                } } }
        }
    }
    private func orderedOptions(_ options: [String], kind: String) -> [String] {
        let order = savedOptions(kind + "Order")
        return order.filter { options.contains($0) } + options.filter { !order.contains($0) }
    }
    private var allPlatforms: [String] { orderedOptions((platformOptions + savedOptions("platform").filter { !platformOptions.contains($0) }).filter { !savedOptions("platformHidden").contains($0) }, kind: "platform") }
    private var platformOptions: [String] { ["线下"] + (category == "餐饮" ? ["外卖", "美团", "饿了么", "大众点评"] : category == "购物" ? ["淘宝", "京东", "拼多多"] : category == "交通" || category == "打车" ? ["滴滴", "高德", "12306"] : []) }
    private func optionsKey(_ kind: String) -> String { "\(income)-\(category)-\(kind)" }
    private func savedOptions(_ kind: String) -> [String] { ((try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:])[optionsKey(kind)] ?? [] }
    private func setSavedOptions(_ values: [String], kind: String) {
        var all = (try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:]
        all[optionsKey(kind)] = values
        if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { customOptionsJSON = text }
    }
    private func restoreCategories() { setHiddenCategories(hiddenCategories.filter { !$0.hasPrefix("\(income)-") }) }
    private func setHiddenCategories(_ values: [String]) {
        var all = (try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:]
        all["hiddenCategories"] = values
        if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { customOptionsJSON = text }
    }
    private func deleteOption(_ name: String, kind: String) {
        if kind == "category" {
            guard let item = categories.first(where: { $0.name == name }) else { return }
            if custom.contains(item) { remove(item); if category.isEmpty { detail = ""; merchant = "" } }
            else { var hidden = hiddenCategories; if !hidden.contains(item.id) { hidden.append(item.id) }; setHiddenCategories(hidden); if category == name { category = ""; detail = ""; merchant = "" } }
        } else {
            var hidden = savedOptions(kind + "Hidden")
            if !hidden.contains(name) { hidden.append(name) }
            setSavedOptions(hidden, kind: kind + "Hidden")
            if kind == "detail" && detail == name { detail = "" }
            if kind == "platform" && merchant == name { merchant = "" }
        }
    }
    private func rememberOptions() {
        var options = (try? JSONDecoder().decode([String: [String]].self, from: Data(customOptionsJSON.utf8))) ?? [:]
        for (kind, value) in [("detail", detail), ("platform", merchant)] {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { let key = optionsKey(kind); var values = options[key] ?? []; if !values.contains(clean) { values.append(clean) }; options[key] = values; let hiddenKey = optionsKey(kind + "Hidden"); options[hiddenKey]?.removeAll { $0 == clean } }
        }
        if let data = try? JSONEncoder().encode(options), let text = String(data: data, encoding: .utf8) { customOptionsJSON = text }
    }
    private func platformEmoji(_ name: String) -> String { if let icon = customOptionEmoji(name, kind: "platform") { return icon }; if savedOptions("platform").contains(name) && !platformOptions.contains(name) { return "" }; return ["线下":"🏪", "外卖":"🥡", "美团":"🍱", "饿了么":"🥡", "大众点评":"⭐️", "淘宝":"🛍️", "京东":"📦", "拼多多":"🛒", "滴滴":"🚕", "高德":"🗺️", "12306":"🚄"][name] ?? (savedOptions("platform").contains(name) && !platformOptions.contains(name) ? "" : "📍") }
    private func detailEmoji(_ name: String) -> String { if let icon = customOptionEmoji(name, kind: "detail") { return icon }; if savedOptions("detail").contains(name) && !defaultDetailOptions.contains(name) { return "" }; return ["早餐":"🌅", "午餐":"🍱", "晚餐":"🌙", "外卖":"🥡", "夜宵":"🌃", "蔬菜":"🥬", "水果":"🍎", "咖啡":"☕️", "奶茶":"🧋", "地铁":"🚇", "公交":"🚌", "火车":"🚄", "日用品":"🧻", "服饰":"👕", "房租":"🏠", "工资":"💼"][name] ?? (savedOptions("detail").contains(name) && !defaultDetailOptions.contains(name) ? "" : "✨") }
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
        if (income ? incomeCategories : expenseCategories).contains(where: { $0.name == name }) { setHiddenCategories(hiddenCategories.filter { $0 != "\(income)-\(name)" }); category = name; showCustom = false; return }
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
        guard !clean.isEmpty else { error = "请先输入金额。"; return }
        guard parts.count <= 2, clean.allSatisfy({ $0.isNumber || $0 == "." }), parts.count == 1 || parts[1].count <= 3, let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")), value <= 999999999 else { error = "请输入有效金额，最多三位小数。"; return }
        guard value > 0 else { error = "金额需要大于零。"; return }
        saving = true
        defer { saving = false }
        var rate: Decimal? = nil
        var usedDate: String? = nil
        if currency != "CNY" {
            guard previewKey == rateKey, let currentRate = previewRate else { error = "汇率尚未获取，请检查网络并重试。账目尚未保存。"; return }
            rate = currentRate; usedDate = previewDate
        }
        let updated = Entry(id: entry?.id ?? UUID(), amount: value, category: category.isEmpty ? "未分类" : category, note: note.trimmingCharacters(in: .whitespacesAndNewlines), date: date, income: income, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), platform: platform.trimmingCharacters(in: .whitespacesAndNewlines), merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), payment: payment.trimmingCharacters(in: .whitespacesAndNewlines), currency: currency, cnyRate: rate, rateDate: usedDate)
        var all = ledger.entries
        if let index = all.firstIndex(where: { $0.id == updated.id }) { all[index] = updated } else { all.append(updated) }
        if ledger.save(all) { rememberOptions(); if embedded { amount = ""; note = ""; category = ""; detail = ""; platform = ""; merchant = ""; payment = ""; date = Date(); error = nil; amountFocused = false; saved = true } else { dismiss() } }
        else { error = "保存失败，请重试。" }
    }
    private var defaultDetailOptions: [String] {
        let options: [String: [String]] = [
            "餐饮": ["早餐", "午餐", "晚餐", "夜宵"], "买菜": ["蔬菜", "水果", "肉蛋", "超市"],
            "咖啡饮品": ["咖啡", "奶茶", "饮料"], "交通": ["地铁", "公交", "火车", "共享单车"],
            "购物": ["日用品", "服饰", "电子产品", "礼物", "其他"], "住房": ["房租", "物业", "维修"],
            "水电": ["水费", "电费", "燃气"], "娱乐": ["游戏", "电影", "音乐", "聚会"],
            "学习": ["课程", "书籍", "文具", "考试"], "医疗": ["挂号", "药品", "检查"],
            "旅行": ["机票", "住宿", "门票"], "订阅": ["软件", "影音", "云服务"],
            "工资": ["基本工资", "绩效", "补贴"], "兼职": ["项目", "劳务"], "退款": ["购物退款", "其他退款"]
        ]
        return options[category] ?? []
    }
    private var detailOptions: [String] {
        let defaults = defaultDetailOptions
        return orderedOptions((defaults + savedOptions("detail").filter { !defaults.contains($0) && !(category == "餐饮" && $0 == "外卖") }).filter { !savedOptions("detailHidden").contains($0) }, kind: "detail")
    }
}
