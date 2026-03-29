//
//  SidebarViews.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit
import Combine

struct AppKitSidebarView: NSViewRepresentable {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Binding var selectedItem: SelectedItem

    func makeCoordinator() -> Coordinator {
        // 协调器只负责桥接 SwiftUI 的 selectedItem 绑定，不持有业务状态。
        Coordinator()
    }

    func makeNSView(context: Context) -> AppKitSidebarContainerView {
        // Sidebar 真正的状态源仍然是 WallpaperManager，SwiftUI 只挂一个容器。
        let view = AppKitSidebarContainerView(wallpaperManager: wallpaperManager)
        context.coordinator.bind(
            selectedItemGetter: { selectedItem },
            selectedItemSetter: { selectedItem = $0 }
        )
        view.configureSelectionBridge(
            selectedItemGetter: context.coordinator.selectedItemGetter,
            selectedItemSetter: context.coordinator.selectedItemSetter
        )
        view.updateSelectedItem(selectedItem)
        return view
    }

    func updateNSView(_ nsView: AppKitSidebarContainerView, context: Context) {
        // update 只刷新桥接引用和当前选中项，不重复创建 outlineView。
        context.coordinator.bind(
            selectedItemGetter: { selectedItem },
            selectedItemSetter: { selectedItem = $0 }
        )
        nsView.configureSelectionBridge(
            selectedItemGetter: context.coordinator.selectedItemGetter,
            selectedItemSetter: context.coordinator.selectedItemSetter
        )
        nsView.updateSelectedItem(selectedItem)
    }

    final class Coordinator {
        private(set) var selectedItemGetter: (() -> SelectedItem)?
        private(set) var selectedItemSetter: ((SelectedItem) -> Void)?

        func bind(
            selectedItemGetter: @escaping () -> SelectedItem,
            selectedItemSetter: @escaping (SelectedItem) -> Void
        ) {
            self.selectedItemGetter = selectedItemGetter
            self.selectedItemSetter = selectedItemSetter
        }
    }
}

final class AppKitSidebarContainerView: NSView {
    private enum SidebarSectionID: String {
        case library
        case tags
        case others

        var title: String {
            switch self {
            case .library:
                return "库"
            case .tags:
                return "标签"
            case .others:
                return "其他"
            }
        }
    }

    private enum SidebarNodeKind {
        case section(SidebarSectionID)
        case category(Category)
        case tag(String)
    }

    private final class SidebarNode: NSObject {
        let kind: SidebarNodeKind
        let title: String
        let symbolName: String?
        var count: Int?
        var children: [SidebarNode]

        init(
            kind: SidebarNodeKind,
            title: String,
            symbolName: String? = nil,
            count: Int? = nil,
            children: [SidebarNode] = []
        ) {
            self.kind = kind
            self.title = title
            self.symbolName = symbolName
            self.count = count
            self.children = children
        }

        var selectedItem: SelectedItem? {
            switch kind {
            case .category(let category):
                return .category(category)
            case .tag(let tag):
                return .tag(tag)
            case .section:
                return nil
            }
        }

        var isGroup: Bool {
            if case .section = kind {
                return true
            }
            return false
        }
    }

    private struct SidebarSnapshotSignature: Equatable {
        let wallpaperCount: Int
        let favoriteCount: Int
        let recentCount: Int
        let tags: [String]
        let tagCounts: [String: Int]
    }

    private struct SidebarLibraryStats {
        let tagCounts: [String: Int]
        let favoriteCount: Int
    }

    private let wallpaperManager: WallpaperManager
    private var cancellables = Set<AnyCancellable>()
    private var rootNodes: [SidebarNode] = []
    private var isApplyingSelection = false
    private var isReloadScheduled = false
    private var contextTag: String?
    private var currentSelectedItem: SelectedItem = .category(.myWallpapers)
    private var selectedItemGetter: (() -> SelectedItem)?
    private var selectedItemSetter: ((SelectedItem) -> Void)?
    private var rowIndexBySelectedItem: [SelectedItem: Int] = [:]
    private var lastSnapshotSignature: SidebarSnapshotSignature?
    private var pendingRecentCount: Int?
    private var isRecentCountRefreshScheduled = false
    private var lastObservedRecentCount: Int?
    private var liveDraggedTag: String?
    private var isLiveTagReordering = false
    private var liveTagOrder: [String]?
    private var lastLiveDropDestination: Int?
    private var liveTagNodeByTag: [String: SidebarNode]?

    private let scrollView: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.hasHorizontalScroller = false
        view.autohidesScrollers = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var outlineView: SidebarOutlineView = {
        let view = SidebarOutlineView()
        view.headerView = nil
        view.focusRingType = .none
        view.rowSizeStyle = .default
        view.style = .sourceList
        view.floatsGroupRows = false
        view.indentationPerLevel = 10
        view.intercellSpacing = NSSize(width: 0, height: 4)
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        view.addTableColumn(column)
        view.outlineTableColumn = column
        view.setDraggingSourceOperationMask(.move, forLocal: true)
        view.registerForDraggedTypes([.string])
        view.draggingDestinationFeedbackStyle = .none

        view.dataSource = self
        view.delegate = self
        view.rowContextMenuProvider = { [weak self] row in
            self?.makeContextMenu(forRow: row)
        }
        view.blankAreaMenuProvider = { [weak self] in
            self?.makeCreateTagMenu()
        }
        view.draggingUpdatedHandler = { [weak self] windowPoint in
            self?.handleTagDragMoved(toWindowPoint: windowPoint)
        }
        view.draggingSessionEndedHandler = { [weak self] operation in
            self?.handleTagDragEnded(operation: operation)
        }
        view.sameSelectionClickHandler = { [weak self] row in
            self?.handleSameSelectionClick(at: row)
        }
        return view
    }()

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        super.init(frame: .zero)
        setupViewHierarchy()
        reloadSidebarData()
        setupObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // 窗口级可见后再做一次强制重载，确保 outline view 的 row 高和拖拽注册已生效。
        DispatchQueue.main.async { [weak self] in
            self?.reloadSidebarData(forceReload: true)
        }
    }

    func configureSelectionBridge(
        selectedItemGetter: (() -> SelectedItem)?,
        selectedItemSetter: ((SelectedItem) -> Void)?
    ) {
        // 这里保存的是外部绑定入口，不是当前选中状态本身。
        self.selectedItemGetter = selectedItemGetter
        self.selectedItemSetter = selectedItemSetter
    }

    func updateSelectedItem(_ selectedItem: SelectedItem) {
        // 由外部状态驱动 sidebar 的选中高亮，而不是让 sidebar 自己决定当前页面。
        currentSelectedItem = selectedItem
        applySelection(for: selectedItem)
    }

    private func setupViewHierarchy() {
        // Sidebar 只保留滚动层和 outline view，不额外包装中间容器，减少 hit-test 干扰。
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.documentView = outlineView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupObservers() {
        // 结构变化、重置和导入是三类会影响整棵树的信号，其他变化尽量走局部 count 刷新。
        let structuralChangePublishers: [AnyPublisher<Void, Never>] = [
            wallpaperManager.$wallpapers.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(structuralChangePublishers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.scheduleReloadSidebarData()
            }
            .store(in: &cancellables)

        wallpaperManager.$tags
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleReloadSidebarData() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .wallpaperManagerDidResetToFreshInstallState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleManagerRefreshNotification(forceReload: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .wallpaperManagerDidImportPersonalSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleManagerRefreshNotification(forceReload: true)
            }
            .store(in: &cancellables)

        wallpaperManager.$recentlyUsedWallpapers
            .map(\.count)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.scheduleRecentlyUsedCountRefresh(count)
            }
            .store(in: &cancellables)
    }

    private func sidebarLibraryStats() -> SidebarLibraryStats {
        // 统计只做一次主库遍历，把收藏数和标签计数合并计算，避免双遍历。
        var tagCounts: [String: Int] = [:]
        var favoriteCount = 0
        for wallpaper in wallpaperManager.wallpapers {
            if wallpaper.isFavorite {
                favoriteCount += 1
            }
            for tag in wallpaper.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return SidebarLibraryStats(tagCounts: tagCounts, favoriteCount: favoriteCount)
    }

    private func currentTagOrder() -> [String] {
        liveTagOrder ?? wallpaperManager.tags
    }

    private func makeSidebarSnapshotSignature(tagOrder: [String]? = nil) -> SidebarSnapshotSignature {
        let tags = tagOrder ?? currentTagOrder()
        let stats = sidebarLibraryStats()
        let wallpapersCount = wallpaperManager.wallpapers.count
        let recentCount = wallpaperManager.recentlyUsedWallpapers.count
        return SidebarSnapshotSignature(
            wallpaperCount: wallpapersCount,
            favoriteCount: stats.favoriteCount,
            recentCount: recentCount,
            tags: tags,
            tagCounts: stats.tagCounts
        )
    }

    private func rebuildNodes(using signature: SidebarSnapshotSignature, tagOrder: [String]) {
        // 只有签名真的变化时才重建树，避免无关的 wallpaper 写回把拖拽状态和 row 映射冲掉。
        let wallpapersCount = signature.wallpaperCount
        let recentCount = signature.recentCount
        let tagCounts = signature.tagCounts
        var sections: [SidebarNode] = []

        let librarySection = SidebarNode(
            kind: .section(.library),
            title: SidebarSectionID.library.title,
            children: [
                SidebarNode(
                    kind: .category(.myWallpapers),
                    title: "我的壁纸",
                    symbolName: "film",
                    count: wallpapersCount
                ),
                SidebarNode(
                    kind: .category(.favorites),
                    title: "特别喜爱",
                    symbolName: "heart.fill",
                    count: signature.favoriteCount
                )
            ]
        )
        sections.append(librarySection)

        if !tagOrder.isEmpty {
            let tagChildren = tagOrder.map { tag in
                SidebarNode(
                    kind: .tag(tag),
                    title: tag,
                    symbolName: "tag",
                    count: tagCounts[tag, default: 0]
                )
            }
            sections.append(
                SidebarNode(
                    kind: .section(.tags),
                    title: SidebarSectionID.tags.title,
                    children: tagChildren
                )
            )
        }

        let othersSection = SidebarNode(
            kind: .section(.others),
            title: SidebarSectionID.others.title,
            children: [
                SidebarNode(
                    kind: .category(.recentlyUsed),
                    title: "最近使用",
                    symbolName: "clock.arrow.circlepath",
                    count: recentCount
                ),
                SidebarNode(
                    kind: .category(.settings),
                    title: "设置",
                    symbolName: "gearshape",
                    count: nil
                )
            ]
        )
        sections.append(othersSection)

        rootNodes = sections
    }

    private func handleManagerRefreshNotification(forceReload: Bool) {
        if forceReload {
            lastSnapshotSignature = nil
        }
        reloadSidebarData(forceReload: forceReload)
    }

    private func reloadSidebarData(forceReload: Bool = false) {
        let previousSelection = currentSelectedItem
        let tagOrder = currentTagOrder()
        let snapshotSignature = makeSidebarSnapshotSignature(tagOrder: tagOrder)
        if !forceReload, snapshotSignature == lastSnapshotSignature {
            applySelection(for: previousSelection)
            return
        }
        lastSnapshotSignature = snapshotSignature
        lastObservedRecentCount = snapshotSignature.recentCount
        rebuildNodes(using: snapshotSignature, tagOrder: tagOrder)
        outlineView.reloadData()
        expandAllSections()
        rebuildRowIndexMap()
        applySelection(for: previousSelection)
    }

    private func scheduleReloadSidebarData() {
        // 多个结构变化同帧到来时合并成一次 reload，避免 outlineView 重建抖动。
        guard !isReloadScheduled else { return }
        isReloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isReloadScheduled = false
            self.reloadSidebarData()
        }
    }

    private func scheduleRecentlyUsedCountRefresh(_ count: Int) {
        // 最近使用计数变化是轻量更新，优先尝试局部刷新，不直接全量重建。
        pendingRecentCount = count
        guard !isRecentCountRefreshScheduled else { return }
        isRecentCountRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRecentCountRefreshScheduled = false
            let recentCount = self.pendingRecentCount ?? self.wallpaperManager.recentlyUsedWallpapers.count
            self.pendingRecentCount = nil
            self.refreshRecentlyUsedCountIfNeeded(recentCount)
        }
    }

    private func refreshRecentlyUsedCountIfNeeded(_ count: Int) {
        // 只有 count 真变了才刷新对应行，避免最近使用快照频繁写入造成重复 redraw。
        if lastObservedRecentCount == count {
            return
        }
        lastObservedRecentCount = count

        guard updateRecentlyUsedNodeCount(count),
              let row = rowIndex(for: .category(.recentlyUsed)) else {
            scheduleReloadSidebarData()
            return
        }

        syncSnapshotRecentCount(count)
        outlineView.reloadData(
            forRowIndexes: IndexSet(integer: row),
            columnIndexes: IndexSet(integer: 0)
        )
    }

    private func updateRecentlyUsedNodeCount(_ count: Int) -> Bool {
        // 直接改当前树上的最近使用节点计数，不重建整个侧边栏。
        for section in rootNodes {
            for child in section.children {
                if case .category(.recentlyUsed) = child.kind {
                    child.count = count
                    return true
                }
            }
        }
        return false
    }

    private func syncSnapshotRecentCount(_ count: Int) {
        guard let signature = lastSnapshotSignature else { return }
        if signature.recentCount == count {
            return
        }
        lastSnapshotSignature = SidebarSnapshotSignature(
            wallpaperCount: signature.wallpaperCount,
            favoriteCount: signature.favoriteCount,
            recentCount: count,
            tags: signature.tags,
            tagCounts: signature.tagCounts
        )
    }

    private func expandAllSections() {
        for section in rootNodes {
            outlineView.expandItem(section)
        }
    }

    private func rebuildRowIndexMap() {
        var rowMap: [SelectedItem: Int] = [:]
        rowMap.reserveCapacity(max(8, outlineView.numberOfRows))
        guard outlineView.numberOfRows > 0 else {
            rowIndexBySelectedItem = rowMap
            return
        }
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? SidebarNode,
                  let selectedItem = node.selectedItem else {
                continue
            }
            rowMap[selectedItem] = row
        }
        rowIndexBySelectedItem = rowMap
    }

    private func applySelection(for selectedItem: SelectedItem) {
        // 外部 selection 和 outlineView selection 必须保持单向同步，避免回写循环。
        guard outlineView.numberOfRows > 0 else { return }
        if let row = rowIndex(for: selectedItem) {
            let target = IndexSet(integer: row)
            guard outlineView.selectedRowIndexes != target else { return }
            isApplyingSelection = true
            outlineView.selectRowIndexes(target, byExtendingSelection: false)
            isApplyingSelection = false
            outlineView.scrollRowToVisible(row)
        } else if !outlineView.selectedRowIndexes.isEmpty {
            isApplyingSelection = true
            outlineView.deselectAll(nil)
            isApplyingSelection = false
        }
    }

    private func handleSameSelectionClick(at row: Int) {
        guard row >= 0,
              row < outlineView.numberOfRows,
              let node = outlineView.item(atRow: row) as? SidebarNode,
              let selected = node.selectedItem else {
            return
        }
        NotificationCenter.default.post(
            name: .appKitRequestScrollToTopForCurrentSelection,
            object: selected.selectionContext.scrollPersistenceKey
        )
    }

    private func rowIndex(for selectedItem: SelectedItem) -> Int? {
        if let row = rowIndexBySelectedItem[selectedItem] {
            return row
        }
        guard outlineView.numberOfRows > 0 else { return nil }
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? SidebarNode,
                  node.selectedItem == selectedItem else {
                continue
            }
            rowIndexBySelectedItem[selectedItem] = row
            return row
        }
        return nil
    }

    private func selectedItemAccessor() -> UIActionHelper.SelectedItemAccessor {
        // 菜单动作通过 accessor 回写到外部 selection bridge，不直接操作 outlineView。
        UIActionHelper.SelectedItemAccessor(
            get: { [weak self] in
                self?.selectedItemGetter?() ?? .category(.myWallpapers)
            },
            set: { [weak self] newValue in
                self?.selectedItemSetter?(newValue)
                self?.currentSelectedItem = newValue
            }
        )
    }

    private func makeCreateTagMenu() -> NSMenu {
        let menu = NSMenu(title: "SidebarMenu")
        let createItem = NSMenuItem(
            title: "新建标签",
            action: #selector(handleCreateTag(_:)),
            keyEquivalent: ""
        )
        createItem.target = self
        menu.addItem(createItem)
        return menu
    }

    private func makeContextMenu(forRow row: Int) -> NSMenu? {
        // 右键菜单会顺手校正一次当前节点选择，保证菜单动作作用于用户命中的那一项。
        guard row >= 0, row < outlineView.numberOfRows,
              let node = outlineView.item(atRow: row) as? SidebarNode else {
            return makeCreateTagMenu()
        }

        if let selected = node.selectedItem {
            applySelection(for: selected)
            selectedItemSetter?(selected)
        }

        let menu = makeCreateTagMenu()
        contextTag = nil

        if case .tag(let tag) = node.kind {
            contextTag = tag
            menu.addItem(.separator())

            let renameItem = NSMenuItem(
                title: "重命名",
                action: #selector(handleRenameTag(_:)),
                keyEquivalent: ""
            )
            renameItem.target = self
            menu.addItem(renameItem)

            let deleteItem = NSMenuItem(
                title: "删除",
                action: #selector(handleDeleteTag(_:)),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.isEnabled = true
            menu.addItem(deleteItem)
        }

        return menu
    }

    @objc private func handleCreateTag(_ sender: Any?) {
        // 标签创建/重命名/删除都走 UIActionHelper，避免侧边栏自己直接改 model。
        UIActionHelper.presentCreateTag(
            manager: wallpaperManager,
            window: appModalHostWindow()
        )
    }

    @objc private func handleRenameTag(_ sender: Any?) {
        guard let tag = contextTag else { return }
        UIActionHelper.presentRenameTag(
            manager: wallpaperManager,
            oldTag: tag,
            selectedItem: selectedItemAccessor(),
            window: appModalHostWindow()
        )
    }

    @objc private func handleDeleteTag(_ sender: Any?) {
        guard let tag = contextTag else { return }
        UIActionHelper.presentDeleteTag(
            manager: wallpaperManager,
            tag: tag,
            selectedItem: selectedItemAccessor(),
            window: appModalHostWindow()
        )
    }

    private func tagsSectionNode() -> SidebarNode? {
        rootNodes.first {
            if case .section(.tags) = $0.kind {
                return true
            }
            return false
        }
    }
}

extension AppKitSidebarContainerView: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SidebarNode else {
            return rootNodes.count
        }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? SidebarNode else {
            return rootNodes[index]
        }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? SidebarNode,
              case .tag(let tag) = node.kind else {
            return nil
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tag, forType: .string)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        writeItems items: [Any],
        to pasteboard: NSPasteboard
    ) -> Bool {
        guard let node = items.first as? SidebarNode,
              case .tag(let tag) = node.kind else {
            return false
        }
        pasteboard.clearContents()
        pasteboard.setString(tag, forType: .string)
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let draggedTag = info.draggingPasteboard.string(forType: .string),
              wallpaperManager.tags.contains(draggedTag) else {
            return false
        }
        return true
    }
}

extension AppKitSidebarContainerView: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return node.isGroup
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return !node.isGroup
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? SidebarNode else { return 28 }
        return node.isGroup ? 24 : 30
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard let node = item as? SidebarNode,
              !node.isGroup else {
            return nil
        }
        let rowView = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("SidebarRowView"), owner: self) as? SidebarRowView ?? {
            let view = SidebarRowView()
            view.identifier = NSUserInterfaceItemIdentifier("SidebarRowView")
            return view
        }()
        return rowView
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }

        if node.isGroup {
            let identifier = NSUserInterfaceItemIdentifier("SidebarGroupCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
                let newCell = NSTableCellView()
                newCell.identifier = identifier
                let textField = NSTextField(labelWithString: "")
                textField.font = .systemFont(ofSize: 12, weight: .semibold)
                textField.textColor = .secondaryLabelColor
                textField.translatesAutoresizingMaskIntoConstraints = false
                newCell.addSubview(textField)
                newCell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: newCell.centerYAnchor)
                ])
                return newCell
            }()
            cell.textField?.stringValue = node.title
            return cell
        }

        let identifier = NSUserInterfaceItemIdentifier("SidebarLeafCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? SidebarRowCellView ?? {
            let newCell = SidebarRowCellView()
            newCell.identifier = identifier
            return newCell
        }()
        cell.configure(
            title: node.title,
            symbolName: node.symbolName,
            count: node.count
        )
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? SidebarNode,
              let selected = node.selectedItem else {
            return
        }
        currentSelectedItem = selected
        selectedItemSetter?(selected)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItems draggedItems: [Any]
    ) {
        guard let node = draggedItems.first as? SidebarNode,
              case .tag(let tag) = node.kind else {
            liveDraggedTag = nil
            isLiveTagReordering = false
            liveTagOrder = nil
            lastLiveDropDestination = nil
            return
        }

        liveDraggedTag = tag
        isLiveTagReordering = true
        liveTagOrder = wallpaperManager.tags
        lastLiveDropDestination = nil
        liveTagNodeByTag = tagsSectionNode()?.children.reduce(into: [:]) { partialResult, node in
            if case .tag(let tag) = node.kind {
                partialResult[tag] = node
            }
        }
        session.animatesToStartingPositionsOnCancelOrFail = false
        if let row = rowIndex(for: .tag(tag)),
           let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView {
            rowView.suppressSelectionDuringDrag = true
            rowView.needsDisplay = true
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateDraggingPresentation()
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        if let liveTagOrder, liveTagOrder != wallpaperManager.tags {
            wallpaperManager.tags = liveTagOrder
            wallpaperManager.saveTags()
        }
        isLiveTagReordering = false
        liveDraggedTag = nil
        self.liveTagOrder = nil
        lastLiveDropDestination = nil
        liveTagNodeByTag = nil
        if let row = rowIndex(for: currentSelectedItem),
           let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView {
            rowView.suppressSelectionDuringDrag = false
            rowView.needsDisplay = true
        }
        updateDraggingPresentation()
        rebuildRowIndexMap()
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let draggedTag = info.draggingPasteboard.string(forType: .string),
              wallpaperManager.tags.contains(draggedTag) else {
            return []
        }
        return .move
    }

}

private extension AppKitSidebarContainerView {
    func handleTagDragMoved(toWindowPoint windowPoint: NSPoint) {
        guard isLiveTagReordering,
              let draggedTag = liveDraggedTag,
              let tagOrder = liveTagOrder,
              let sourceIndex = tagOrder.firstIndex(of: draggedTag),
              let targetIndex = liveTagDropIndex(forWindowPoint: windowPoint, tagOrder: tagOrder) else {
            return
        }

        let clampedTarget = max(0, min(targetIndex, tagOrder.count))
        var destination = clampedTarget
        if sourceIndex < destination {
            destination -= 1
        }
        guard sourceIndex != destination,
              destination >= 0,
              destination <= tagOrder.count else {
            return
        }
        guard let tagsSection = tagsSectionNode() else {
            return
        }

        if lastLiveDropDestination == destination {
            return
        }
        lastLiveDropDestination = destination

        let updatedTags = moveTag(in: tagOrder, from: sourceIndex, to: destination)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            outlineView.beginUpdates()
            liveTagOrder = updatedTags
            reorderLiveTagsSection(with: updatedTags)
            outlineView.moveItem(at: sourceIndex, inParent: tagsSection, to: destination, inParent: tagsSection)
            outlineView.endUpdates()
        }
    }

    func handleTagDragEnded(operation: NSDragOperation) {
        isLiveTagReordering = false
        liveDraggedTag = nil
        rebuildRowIndexMap()
    }

    func moveTag(in tags: [String], from sourceIndex: Int, to destination: Int) -> [String] {
        var updated = tags
        let moved = updated.remove(at: sourceIndex)
        updated.insert(moved, at: destination)
        return updated
    }

    func reorderLiveTagsSection(with updatedTags: [String]) {
        guard let tagsSection = tagsSectionNode() else { return }
        let nodeByTag = liveTagNodeByTag ?? tagsSection.children.reduce(into: [:]) { partialResult, node in
            if case .tag(let tag) = node.kind {
                partialResult[tag] = node
            }
        }
        tagsSection.children = updatedTags.compactMap { nodeByTag[$0] }
    }

    func updateDraggingPresentation() {
        guard outlineView.numberOfRows > 0 else { return }
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? SidebarNode,
                  case .tag(let tag) = node.kind,
                  let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarRowCellView else {
                continue
            }
            let dragging = isLiveTagReordering && liveDraggedTag == tag
            cell.setDraggingPresentation(dragging)
            if let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView {
                rowView.suppressSelectionDuringDrag = dragging
                rowView.needsDisplay = true
            }
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingImageForRowsWith dragRows: IndexSet,
        tableColumns: [NSTableColumn],
        event: NSEvent,
        offset dragImageOffset: NSPointPointer
    ) -> NSImage {
        guard let row = dragRows.first,
              let rowView = outlineView.rowView(atRow: row, makeIfNecessary: true) as? SidebarRowView else {
            return NSImage(size: .zero)
        }

        let previous = rowView.suppressSelectionDuringDrag
        rowView.suppressSelectionDuringDrag = true
        rowView.needsDisplay = true

        let size = rowView.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        if let rep = rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds) {
            rowView.cacheDisplay(in: rowView.bounds, to: rep)
            image.addRepresentation(rep)
        }
        image.unlockFocus()

        rowView.suppressSelectionDuringDrag = previous
        rowView.needsDisplay = true
        dragImageOffset.pointee = NSPoint(x: 0, y: 0)
        return image
    }

    func liveTagDropIndex(forWindowPoint windowPoint: NSPoint, tagOrder: [String]) -> Int? {
        let location = outlineView.convert(windowPoint, from: nil)
        let row = outlineView.row(at: location)

        guard row >= 0 else {
            return tagOrder.count
        }

        guard let node = outlineView.item(atRow: row) as? SidebarNode else {
            return nil
        }

        switch node.kind {
        case .section(.tags):
            return max(0, min(tagOrder.count, tagOrder.count))
        case .tag(let hoveredTag):
            guard tagOrder.contains(hoveredTag) else { return nil }
            let hoveredIndex = tagOrder.firstIndex(of: hoveredTag) ?? 0
            let rowRect = outlineView.rect(ofRow: row)
            let insertAfterRow = location.y < rowRect.midY
            let destination = insertAfterRow ? hoveredIndex + 1 : hoveredIndex
            return max(0, min(destination, tagOrder.count))
        default:
            return nil
        }
    }
}
