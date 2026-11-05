import SwiftUI
import Charts
import UniformTypeIdentifiers
import UIKit

private let accent = Color(red: 0.12, green: 0.52, blue: 0.44)
private func moneyText(_ value: Decimal, currency: String = "CNY") -> String { (value as NSDecimalNumber).doubleValue.formatted(.currency(code: currency).precision(.fractionLength(2...3))) }
private func monthItems(_ entries: [Entry], _ date: Date) -> [Entry] { entries.filter { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month) }.sorted { $0.date > $1.date } }
private func sum(_ entries: [Entry], income: Bool) -> Decimal { entries.filter { $0.income == income }.reduce(0) { $0 + ($1.cnyAmount ?? 0) } }

private final class RapidTabBarController: UITabBarController {
    var onVisible: ((UIWindow) -> Void)?
    var onHidden: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let window = view.window { onVisible?(window) }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onHidden?()
    }
}

struct LedgerTabs: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var target: EditorTarget?
    @State private var selected = 1

    var body: some View {
        NativeLedgerTabs(target: $target, selected: $selected, ledger: ledger, reduceMotion: reduceMotion)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .sheet(item: $target) { EntryEditor(entry: $0.entry).environmentObject(ledger).tint(accent) }
            .alert("提示", isPresented: Binding(get: { ledger.error != nil }, set: { if !$0 { ledger.error = nil } })) {
                Button("知道了") { ledger.error = nil }
            } message: { Text(ledger.error ?? "") }
    }
}

private struct NativeLedgerTabs: UIViewControllerRepresentable {
    @Binding var target: EditorTarget?
    @Binding var selected: Int
    let ledger: Ledger
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func pages() -> [AnyView] {
        [AnyView(Dashboard(target: $target, selected: selected).environmentObject(ledger).tint(accent)),
         AnyView(EntryEditor(entry: nil, embedded: true, tabSelection: selected).environmentObject(ledger).tint(accent)),
         AnyView(Insights(selected: selected).environmentObject(ledger).tint(accent))]
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = RapidTabBarController()
        controller.delegate = context.coordinator
        controller.onVisible = { [weak coordinator = context.coordinator, weak controller] window in
            guard let coordinator, let controller else { return }
            coordinator.installRapidTap(on: window, controller: controller)
        }
        controller.onHidden = { [weak coordinator = context.coordinator] in coordinator?.removeRapidTap() }
        controller.view.tintColor = UIColor(red: 0.12, green: 0.52, blue: 0.44, alpha: 1)
        let icons = ["list.bullet.rectangle", "plus.circle.fill", "chart.bar.xaxis"]
        let labels = ["明细", "记账", "统计"]
        let hosts = pages().enumerated().map { index, page in
            let host = UIHostingController(rootView: page)
            host.tabBarItem = UITabBarItem(title: nil, image: UIImage(systemName: icons[index]), tag: index)
            host.tabBarItem.accessibilityLabel = labels[index]
            return host
        }
        controller.setViewControllers(hosts, animated: false)
        controller.selectedIndex = selected
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.parent = self
        for (host, page) in zip(controller.viewControllers ?? [], pages()) {
            (host as? UIHostingController<AnyView>)?.rootView = page
        }
        if controller.selectedIndex != selected { controller.selectedIndex = selected }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate, UIGestureRecognizerDelegate {
        var parent: NativeLedgerTabs
        private var activeTransition: LedgerTabTransition?
        private weak var controller: UITabBarController?
        private var rapidTap: UITapGestureRecognizer?
        private var rapidTarget: Int?
        init(_ parent: NativeLedgerTabs) { self.parent = parent }

        func installRapidTap(on window: UIWindow, controller: UITabBarController) {
            self.controller = controller
            if rapidTap?.view === window { return }
            removeRapidTap()
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleRapidTap(_:)))
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            window.addGestureRecognizer(gesture)
            rapidTap = gesture
        }

        func removeRapidTap() {
            if let rapidTap { rapidTap.view?.removeGestureRecognizer(rapidTap) }
            rapidTap = nil
            rapidTarget = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            rapidTarget = nil
            guard gestureRecognizer === rapidTap, activeTransition?.isRunning == true,
                  let controller, let window = controller.view.window,
                  controller.presentedViewController == nil else { return false }
            let bar = controller.tabBar
            let point = touch.location(in: bar)
            let bounds = bar.bounds
            // The current iPhone layout has three items; ignore the outer margin.
            guard !bar.isHidden, bar.window === window, bounds.width > 0,
                  bounds.insetBy(dx: bounds.width * 0.14, dy: 0).contains(point),
                  controller.viewControllers?.count == 3 else { return false }
            let visualIndex = min(2, max(0, Int((point.x - bounds.minX) / bounds.width * 3)))
            rapidTarget = bar.effectiveUserInterfaceLayoutDirection == .rightToLeft ? 2 - visualIndex : visualIndex
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func handleRapidTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let index = rapidTarget, let controller else { return }
            rapidTarget = nil
            guard controller.selectedIndex != index else { return }
            let interruptedView = activeTransition?.finishImmediately()
            activeTransition = nil
            controller.selectedIndex = index
            interruptedView?.transform = .identity
            parent.selected = index
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            let interruptedView = activeTransition?.finishImmediately()
            activeTransition = nil
            if viewController === tabBarController.selectedViewController, let interruptedView {
                UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    interruptedView.transform = .identity
                }
            }
            return true
        }
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard let index = tabBarController.viewControllers?.firstIndex(of: viewController), index != parent.selected else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            parent.selected = index
        }
        func tabBarController(_ tabBarController: UITabBarController, animationControllerForTransitionFrom fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            guard !parent.reduceMotion else { return nil }
            let transition = LedgerTabTransition()
            activeTransition = transition
            return transition
        }
    }
}

private final class LedgerTabTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private var context: UIViewControllerContextTransitioning?
    private var fromView: UIView?
    private var toView: UIView?
    private var fromTransform = CGAffineTransform.identity
    private var toTransform = CGAffineTransform.identity
    private var finished = false
    var isRunning: Bool { context != nil && !finished }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.23 }

    @discardableResult func finishImmediately() -> UIView? {
        guard !finished, let context, let toView else { return nil }
        let isVisible = context.containerView.subviews.last === toView
        let visibleTransform = isVisible ? toView.layer.presentation()?.affineTransform() : nil
        let cancelled = context.transitionWasCancelled
        finish(cancelled: cancelled)
        guard !cancelled, let visibleTransform else { return nil }
        toView.transform = visibleTransform
        return toView
    }

    private func finish(cancelled: Bool) {
        guard !finished, let context else { return }
        finished = true
        fromView?.layer.removeAllAnimations()
        toView?.layer.removeAllAnimations()
        fromView?.transform = fromTransform
        toView?.transform = toTransform
        if cancelled { toView?.removeFromSuperview() }
        else if let toView { context.containerView.bringSubviewToFront(toView) }
        context.completeTransition(!cancelled)
        self.context = nil
        fromView = nil
        toView = nil
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let toController = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            return
        }
        let container = context.containerView
        // The scaled pages can briefly expose the transition container at the edges.
        // Use the same dynamic background as the pages, including in dark mode.
        container.backgroundColor = .systemGroupedBackground
        let originalToTransform = to.transform
        self.context = context
        fromView = from
        toView = to
        // An interrupted incoming page may already be partially scaled. Restore
        // it when it leaves so it is ready the next time the tab is shown.
        fromTransform = .identity
        toTransform = originalToTransform
        to.frame = context.finalFrame(for: toController)
        to.transform = CGAffineTransform(scaleX: 0.996, y: 0.996)
        container.insertSubview(to, belowSubview: from)
        UIView.animate(withDuration: 0.07, delay: 0, options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]) {
            from.transform = CGAffineTransform(scaleX: 0.996, y: 0.996)
        } completion: { _ in
            guard !self.finished else { return }
            if context.transitionWasCancelled {
                self.finish(cancelled: true)
                return
            }
            container.bringSubviewToFront(to)
            UIView.animate(withDuration: 0.16, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
                to.transform = originalToTransform
            } completion: { _ in
                self.finish(cancelled: context.transitionWasCancelled)
            }
        }
    }
}

// The UIKit transition animates complete pages, including the save area.
struct TabArrival: ViewModifier {
    let selected: Int
    let tab: Int
    var showsBackground = true
    func body(content: Content) -> some View { content }
}

struct SoftTopScrollEdge: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectStyle(.soft, for: .top) }
        else { content }
    }
}

private struct Dashboard: View {
    @EnvironmentObject private var ledger: Ledger
    @Binding var target: EditorTarget?
    let selected: Int
    @State private var month = Date()
    @State private var deleting: Entry?
    @State private var showingSearch = false
    @AppStorage("monthlyBudget") private var budget = 0.0
    private var items: [Entry] { monthItems(ledger.entries, month) }
    var body: some View {
        let visibleEntries = items
        let entriesByDay = Dictionary(grouping: visibleEntries) { Calendar.current.startOfDay(for: $0.date) }
        let days = entriesByDay.keys.sorted(by: >)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if items.contains(where: { $0.cnyAmount == nil }) { Text("部分外币账目缺少汇率，未计入人民币汇总。请编辑并重新保存。") .font(.footnote).foregroundStyle(.orange) }
                    summary
                    if budget > 0 { budgetCard }
                    HStack(alignment: .firstTextBaseline) { Text("账目明细").font(.title3.bold()); Spacer(); Text("\(visibleEntries.count) 笔").font(.subheadline).foregroundStyle(.secondary) }
                    if visibleEntries.isEmpty {
                        ContentUnavailableView("还没有账目", systemImage: "tray", description: Text("点击底部记账按钮记录收支"))
                    } else {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(days, id: \.self) { day in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(day, format: .dateTime.month().day().weekday(.wide)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    VStack(spacing: 0) {
                                        ForEach(entriesByDay[day] ?? []) { entry in
                                            Button { target = EditorTarget(entry: entry) } label: { EntryRow(entry: entry) }.buttonStyle(.plain)
                                                .contextMenu { Button("编辑") { target = EditorTarget(entry: entry) }; Button("删除", role: .destructive) { deleting = entry } }
                                            if entry.id != entriesByDay[day]?.last?.id { Divider().padding(.leading, 64) }
                                        }
                                    }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 40)
                    .modifier(TabArrival(selected: selected, tab: 0, showsBackground: false))
            }
            .modifier(SoftTopScrollEdge())
            .scrollBounceBehavior(.always, axes: .vertical)
            .background {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            }
            .navigationTitle("明细").navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("搜索账目")
                Button { target = EditorTarget(entry: nil) } label: { Image(systemName: "plus") }.accessibilityLabel("记一笔")
            } }
            .fullScreenCover(isPresented: $showingSearch) {
                NavigationStack {
                    LedgerSearch().environmentObject(ledger)
                }.tint(accent)
            }
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

private struct LedgerSearch: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var editing: EditorTarget?
    @FocusState private var searchFocused: Bool

    private var matches: [Entry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return ledger.entries.filter { entry in
            [entry.category, entry.detail ?? "", entry.platform ?? "", entry.merchant ?? "", entry.payment ?? "", entry.note]
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        let groups = Dictionary(grouping: matches) { Calendar.current.startOfDay(for: $0.date) }
        let days = groups.keys.sorted(by: >)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索分类、平台或备注", text: $query).focused($searchFocused)
                        .submitLabel(.search)
                }.padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("搜索全部账目", systemImage: "magnifyingglass", description: Text("输入分类、平台或备注"))
                } else if days.isEmpty {
                    ContentUnavailableView("没有找到相关账目", systemImage: "magnifyingglass", description: Text("试试其他关键词"))
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(days, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(day, format: .dateTime.year().month().day().weekday(.wide)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                VStack(spacing: 0) {
                                    ForEach(groups[day] ?? []) { entry in
                                        Button { searchFocused = false; editing = EditorTarget(entry: entry) } label: { EntryRow(entry: entry) }.buttonStyle(.plain)
                                        if entry.id != groups[day]?.last?.id { Divider().padding(.leading, 64) }
                                    }
                                }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            }
                        }
                    }
                }
            }.padding(20).frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading)
                .background { Color.clear.contentShape(Rectangle()).onTapGesture { searchFocused = false } }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("搜索账目").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("返回") { searchFocused = false; dismiss() }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searchFocused = true
        }
        .sheet(item: $editing) { EntryEditor(entry: $0.entry).environmentObject(ledger).tint(accent) }
    }
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
            VStack(alignment: .leading, spacing: 5) { Text(entry.category).font(.body.weight(.medium)); let subtitle = [entry.detail ?? "", entry.merchant ?? "", entry.payment ?? "", entry.platform ?? "", entry.note].filter { !$0.isEmpty }.joined(separator: " · "); if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; if let rate = entry.cnyRate, let converted = entry.cnyAmount { Text("约 \(moneyText(converted)) · 汇率 \(NSDecimalNumber(decimal: rate).stringValue) · \(entry.rateDate ?? "")").font(.caption2).foregroundStyle(.secondary) } }
            Spacer(minLength: 4)
            Text((entry.income ? "+" : "−") + moneyText(entry.amount, currency: entry.currency ?? "CNY")).font(.body.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(14).contentShape(Rectangle())
    }
}

private struct Insights: View {
    @EnvironmentObject private var ledger: Ledger
    let selected: Int
    @State private var month = Date()
    @State private var showingSettings = false
    private var items: [Entry] { monthItems(ledger.entries, month) }
    private var categories: [(name: String, value: Double)] {
        let groups = Dictionary(grouping: items.filter { !$0.income }, by: \.category)
        return groups.map { (name: $0.key, value: ($0.value.reduce(Decimal.zero) { $0 + ($1.cnyAmount ?? 0) } as NSDecimalNumber).doubleValue) }.sorted { $0.value > $1.value }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Button { shift(-1) } label: { Image(systemName: "chevron.left") }; Spacer(); Text(month, format: .dateTime.year().month()).font(.headline); Spacer(); Button { shift(1) } label: { Image(systemName: "chevron.right") } }.padding(.vertical, 10)
                    if items.contains(where: { $0.cnyAmount == nil }) { Text("部分外币账目缺少汇率，未计入统计。") .font(.footnote).foregroundStyle(.orange) }
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
                    .modifier(TabArrival(selected: selected, tab: 2, showsBackground: false))
            }.modifier(SoftTopScrollEdge())
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("统计").navigationBarTitleDisplayMode(.large)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("设置") } }
                .sheet(isPresented: $showingSettings) { Preferences() }
        }.tint(accent)
    }
    private func shift(_ n: Int) { if let next = Calendar.current.date(byAdding: .month, value: n, to: month) { month = next } }
}

private struct Preferences: View {
    @EnvironmentObject private var ledger: Ledger
    @Environment(\.dismiss) private var dismiss
    @AppStorage("monthlyBudget") private var budget = 0.0
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingBackup: LedgerBackup?
    @State private var importError: String?
    @State private var restored = false
    @State private var document = LedgerDocument(data: Data())
    var body: some View {
        NavigationStack {
            Form {
                Section("月度预算") {
                    NavigationLink { BudgetSettings() } label: {
                        LabeledContent("月度预算", value: budget > 0 ? moneyText(Decimal(budget)) : "未设置")
                    }
                }
                Section("数据与备份") {
                    Label("数据保存在本机", systemImage: "iphone")
                    Button { do { document = LedgerDocument(data: try ledger.exportData()); exporting = true } catch { ledger.error = "读取账目失败，无法导出。" } } label: { Label("导出账目备份", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("导入备份", systemImage: "square.and.arrow.down") }
                    NavigationLink { BackupInformation() } label: { Label("备份说明", systemImage: "info.circle") }
                }
                Section("关于") { LabeledContent("版本", value: "2.0 测试版") }
            }.navigationTitle("设置")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "记账备份") { result in if case .failure = result { ledger.error = "导出失败，请重试。" } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        pendingBackup = try ledger.decodeBackup(Data(contentsOf: url))
                    } catch { importError = "无法读取或验证备份，请检查文件。当前数据没有改变。" }
                }
                .alert("替换当前数据？", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } })) {
                    Button("导入并替换", role: .destructive) {
                        if let backup = pendingBackup { do { try ledger.restore(backup); restored = true } catch { importError = "导入失败，当前账目未被替换。" } }
                        pendingBackup = nil
                    }
                    Button("取消", role: .cancel) { pendingBackup = nil }
                } message: { Text("将导入 \(pendingBackup?.entries.count ?? 0) 笔账目，并替换备份中包含的账目和设置。建议先导出当前备份。") }
                .alert("导入完成", isPresented: $restored) { Button("好", role: .cancel) {} }
                .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) { Button("好", role: .cancel) { importError = nil } } message: { Text(importError ?? "") }
        }
    }
}

private struct BudgetSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("monthlyBudget") private var budget = 0.0
    @State private var input = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                HStack { Text("¥"); TextField("不设置", text: $input).keyboardType(.decimalPad).focused($focused) }
                Button("保存预算") {
                    guard let value = Double(input.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0, value <= 999999999 else { invalid = true; return }
                    budget = value
                    dismiss()
                }
            } footer: { Text("输入 0 可关闭月度预算。") }
        }
        .navigationTitle("月度预算").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { focused = false }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focused = false } } }
        .onAppear { input = budget > 0 ? String(format: "%.2f", budget) : "" }
        .alert("请输入有效的预算金额", isPresented: $invalid) { Button("好", role: .cancel) {} }
    }
}

private struct BackupInformation: View {
    var body: some View {
        Form {
            Section("备份内容") { Text("备份包含账目、预算，以及自定义分类、细分、平台、图标和顺序。") }
            Section("导入备份") { Text("导入会替换备份中包含的对应数据；旧版备份中缺少的设置会保留当前值。建议导入前先导出当前备份。") }
            Section("数据保存") { Text("数据保存在本机。请妥善保管备份；删除 App 可能导致本地数据丢失。") }
        }.navigationTitle("备份说明").navigationBarTitleDisplayMode(.inline)
    }
}

private struct LedgerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

