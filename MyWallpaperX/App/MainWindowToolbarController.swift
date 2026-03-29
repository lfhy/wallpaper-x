//
//  MainWindowToolbarController.swift
//  MyWallpaperX
//

import AppKit
import Foundation
import Combine

final class MainWindowToolbarController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate {
    // 工具栏状态只从单一快照派生，避免按钮状态和侧边栏/网格各自计算后漂移。
    struct ToolbarAvailability {
        let selection: WallpaperSelectionContext
        let isMultiSelectMode: Bool
        let hasWallpapersInSelection: Bool
        let hasAnySelection: Bool
        let hasSingleSelection: Bool
        let hasTags: Bool

        var isSettings: Bool { selection.isSettings }
        var canUseLibraryActions: Bool { !isSettings }
    }

    struct ToolbarRefreshSignature: Equatable {
        let selection: WallpaperSelectionContext
        let isMultiSelectMode: Bool
        let hasWallpapersInSelection: Bool
        let hasAnySelection: Bool
        let hasSingleSelection: Bool
        let hasTags: Bool
        let searchQuery: String
        let isSearchEnabled: Bool
        let isFavoritedState: Bool
    }

    enum IDs {
        static let toolbar = NSToolbar.Identifier("MainWindowToolbar")
        static let sidebar = NSToolbarItem.Identifier.sidebarTrackingSeparator
        static let title = NSToolbarItem.Identifier("ToolbarTitle")
        static let navigation = NSToolbarItem.Identifier("ToolbarNavigation")
        static let `import` = NSToolbarItem.Identifier("ToolbarImport")
        static let select = NSToolbarItem.Identifier("ToolbarSelect")
        static let delete = NSToolbarItem.Identifier("ToolbarDelete")
        static let favorite = NSToolbarItem.Identifier("ToolbarFavorite")
        static let tag = NSToolbarItem.Identifier("ToolbarTag")
        static let info = NSToolbarItem.Identifier("ToolbarInfo")
        static let sort = NSToolbarItem.Identifier("ToolbarSort")
        static let zoom = NSToolbarItem.Identifier("ToolbarZoom")
        static let search = NSToolbarItem.Identifier("ToolbarSearch")
    }

    weak var window: NSWindow?
    let wallpaperManager: WallpaperManager
    var cancellables = Set<AnyCancellable>()
    var pendingToolbarRefreshWorkItem: DispatchWorkItem?
    var lastRefreshSignature: ToolbarRefreshSignature?

    lazy var toolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: IDs.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }()

    lazy var importItem = makeToolbarItem(
        identifier: IDs.import,
        symbolName: "plus.circle",
        label: "导入",
        toolTip: "导入视频",
        action: #selector(handleImportButtonAction)
    )

    lazy var selectItem = makeToolbarItem(
        identifier: IDs.select,
        symbolName: "checkmark.circle",
        label: "选择",
        toolTip: "进入选择模式",
        action: #selector(handleSelectButtonAction)
    )

    lazy var navigationControl: NSSegmentedControl = {
        // 前后切换放在一个 segmented control 里，便于共享同一条手动切换节流路径。
        let control = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "上一张") ?? NSImage(),
            NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: "下一张") ?? NSImage()
        ], trackingMode: .momentary, target: self, action: #selector(handleNavigationSegmentAction(_:)))
        control.segmentStyle = .texturedRounded
        control.setWidth(30, forSegment: 0)
        control.setWidth(30, forSegment: 1)
        control.setAccessibilityLabel("切换壁纸")
        control.toolTip = "切换上一张/下一张壁纸"
        return control
    }()

    lazy var navigationItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: IDs.navigation)
        item.label = "切换"
        item.paletteLabel = "切换"
        item.toolTip = "切换上一张/下一张壁纸"
        item.autovalidates = false
        item.view = navigationControl
        return item
    }()

    lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .left
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var titleContainerView: NSView = {
        // 标题容器保留固定宽度，避免工具栏在标题长短变化时左右跳动。
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 28))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 180),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }()

    lazy var titleItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: IDs.title)
        item.label = "当前目录"
        item.paletteLabel = "当前目录"
        item.autovalidates = false
        item.isBordered = false
        item.view = titleContainerView
        return item
    }()

    lazy var deleteItem = makeToolbarItem(
        identifier: IDs.delete,
        symbolName: "trash",
        label: "删除",
        toolTip: "删除选中壁纸",
        action: #selector(handleDeleteButtonAction)
    )

    lazy var favoriteItem = makeToolbarItem(
        identifier: IDs.favorite,
        symbolName: "heart",
        label: "收藏",
        toolTip: "收藏选中壁纸",
        action: #selector(handleFavoriteButtonAction)
    )

    lazy var tagItem = makeToolbarItem(
        identifier: IDs.tag,
        symbolName: "tag",
        label: "标签",
        toolTip: "编辑标签",
        action: #selector(handleTagButtonAction)
    )

    lazy var infoItem = makeToolbarItem(
        identifier: IDs.info,
        symbolName: "info.circle",
        label: "信息",
        toolTip: "查看信息",
        action: #selector(handleInfoButtonAction)
    )

    lazy var sortMenuButton: NSButton = {
        // 排序按钮用 NSButton + NSMenu 方式实现下拉菜单，保持与访达排序按钮一致的交互形式。
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "排序")
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleSortButtonAction(_:))
        button.toolTip = "排序方式"
        return button
    }()

    lazy var sortItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: IDs.sort)
        item.label = "排序"
        item.paletteLabel = "排序"
        item.toolTip = "排序方式"
        item.autovalidates = false
        item.view = sortMenuButton
        return item
    }()

    lazy var zoomControl: NSSegmentedControl = {
        // 缩小（-）在左，放大（+）在右，与系统惯例一致。
        let control = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "缩小") ?? NSImage(),
            NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "放大") ?? NSImage()
        ], trackingMode: .momentary, target: self, action: #selector(handleZoomSegmentAction(_:)))
        control.segmentStyle = .texturedRounded
        control.setWidth(28, forSegment: 0)
        control.setWidth(28, forSegment: 1)
        control.toolTip = "调整缩略图大小"
        return control
    }()

    lazy var zoomItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: IDs.zoom)
        item.label = "缩放"
        item.paletteLabel = "缩放"
        item.toolTip = "调整缩略图大小"
        item.autovalidates = false
        item.view = zoomControl
        return item
    }()


    lazy var searchItem: NSSearchToolbarItem = {
        // NSSearchToolbarItem 是系统专用搜索工具栏 item：
        // 自动处理胶囊边框、弹性宽度、折叠展开动画，无需手动约束。
        let item = NSSearchToolbarItem(itemIdentifier: IDs.search)
        item.searchField.delegate = self
        item.searchField.placeholderString = "搜索"
        item.searchField.sendsSearchStringImmediately = true
        item.resignsFirstResponderWithCancel = true
        item.preferredWidthForSearchField = 165
        return item
    }()

    init(window: NSWindow, wallpaperManager: WallpaperManager) {
        self.window = window
        self.wallpaperManager = wallpaperManager
        super.init()
        window.toolbar = toolbar
        installObservers()
        // 避免在 toolbar 初次布局周期内立即触发状态刷新，减少约束重入风险。
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    func installObservers() {
        // 工具栏只监听会影响按钮可用性和标题内容的状态，不订阅导入进度或缓存流水线。
        observeForRefresh(wallpaperManager.$wallpapers)
        observeForRefresh(wallpaperManager.$selectedCategory)
        observeForRefresh(wallpaperManager.$selectedTag)
        observeForRefresh(wallpaperManager.$isMultiSelectMode)
        observeForRefresh(wallpaperManager.$selectedWallpaperId)
        observeForRefresh(wallpaperManager.$selectedWallpaperIds)
        observeForRefresh(wallpaperManager.$tags)
        // 独立排序状态变化时刷新排序按钮颜色。
        observeForRefresh(wallpaperManager.$perSelectionSortStates)

        wallpaperManager.$searchQuery
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshSearchField(isSettingsSelection: self.wallpaperManager.currentSelectionContext.isSettings)
            }
            .store(in: &cancellables)
    }

    func observeForRefresh<T>(_ publisher: Published<T>.Publisher) {
        publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)
    }

    func scheduleRefresh() {
        // 短延迟合并刷新可以防止 category / selection / tags 连续变化时重复重绘工具栏。
        pendingToolbarRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        pendingToolbarRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    func makeToolbarItem(
        identifier: NSToolbarItem.Identifier,
        symbolName: String,
        label: String,
        toolTip: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = toolTip
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }

    func makeSidebarTrackingItem() -> NSToolbarItem? {
        // Sidebar tracking item 依赖当前窗口里的 split view，找不到就退化为空，避免 toolbar 创建失败。
        guard let rootView = window?.contentViewController?.view ?? window?.contentView,
              let splitView = findSplitView(in: rootView) else {
            return nil
        }
        return NSTrackingSeparatorToolbarItem(identifier: IDs.sidebar, splitView: splitView, dividerIndex: 0)
    }

    func findSplitView(in view: NSView) -> NSSplitView? {
        // 这里是递归查找主分栏，不保存外部引用，减少窗口层级变化后悬挂指针风险。
        if let splitView = view as? NSSplitView,
           splitView.isVertical,
           splitView.subviews.count > 1 {
            return splitView
        }
        for subview in view.subviews {
            if let splitView = findSplitView(in: subview) {
                return splitView
            }
        }
        return nil
    }

    func refresh() {
        // 刷新只做状态同步，不触发额外数据重建。
        let availability = toolbarAvailability()
        let isFavoritedState = availability.canUseLibraryActions
            && availability.hasAnySelection
            && wallpaperManager.areAllSelectedWallpapersFavorite(for: availability.selection)
        let signature = ToolbarRefreshSignature(
            selection: availability.selection,
            isMultiSelectMode: availability.isMultiSelectMode,
            hasWallpapersInSelection: availability.hasWallpapersInSelection,
            hasAnySelection: availability.hasAnySelection,
            hasSingleSelection: availability.hasSingleSelection,
            hasTags: availability.hasTags,
            searchQuery: wallpaperManager.searchQuery,
            isSearchEnabled: !availability.isSettings,
            isFavoritedState: isFavoritedState
        )
        if signature == lastRefreshSignature {
            return
        }
        lastRefreshSignature = signature

        refreshLeadingGroup(with: availability)
        refreshTrailingGroup(with: availability, isFavoritedState: isFavoritedState)
        refreshSearchField(isSettingsSelection: availability.isSettings)
    }

    func refreshLeadingGroup(with availability: ToolbarAvailability) {
        // 仅更新控件可用性和文案，不重建 toolbar item，避免布局抖动。
        configureImportItem(isMultiSelectMode: availability.isMultiSelectMode)
        configureSelectItem(isMultiSelectMode: availability.isMultiSelectMode)
        titleLabel.stringValue = availability.selection.displayTitle
        titleItem.toolTip = availability.selection.displayTitle
        importItem.isEnabled = availability.canUseLibraryActions
        selectItem.isEnabled = availability.canUseLibraryActions
        navigationControl.isEnabled = availability.canUseLibraryActions && availability.hasWallpapersInSelection
    }

    func refreshTrailingGroup(with availability: ToolbarAvailability, isFavoritedState: Bool) {
        // 尾部按钮同样只做状态同步，保持 toolbar 结构稳定。
        deleteItem.isEnabled = availability.canUseLibraryActions && availability.hasAnySelection
        favoriteItem.isEnabled = availability.canUseLibraryActions && availability.hasAnySelection
        tagItem.isEnabled = availability.canUseLibraryActions && availability.hasAnySelection && availability.hasTags
        infoItem.isEnabled = availability.canUseLibraryActions && availability.hasSingleSelection
        sortItem.isEnabled = availability.canUseLibraryActions
        configureFavoriteItem(isFavoritedState: isFavoritedState)
        configureSortItem()
        configureZoomItem()
    }

    func refreshSearchField(isSettingsSelection: Bool) {
        // 搜索框启用状态跟随当前选区，不让 settings 页保留误导性的可编辑状态。
        if searchItem.searchField.stringValue != wallpaperManager.searchQuery {
            searchItem.searchField.stringValue = wallpaperManager.searchQuery
        }
        let shouldEnable = !isSettingsSelection
        if searchItem.isEnabled != shouldEnable {
            searchItem.isEnabled = shouldEnable
        }
        if searchItem.searchField.isEnabled != shouldEnable {
            searchItem.searchField.isEnabled = shouldEnable
        }
    }

    @objc private func handleImportButtonAction() {
        performToolbarAction(requiresNonSettingsSelection: true, refreshAfter: true) { selection in
            UIActionHelper.handleImportOrSelectAll(
                manager: wallpaperManager,
                selection: selection,
                window: window
            )
        }
    }

    @objc private func handleSelectButtonAction() {
        performToolbarAction(requiresNonSettingsSelection: true, refreshAfter: true) { _ in
            wallpaperManager.toggleMultiSelectMode()
        }
    }

    @objc private func handleDeleteButtonAction() {
        performToolbarAction(requiresNonSettingsSelection: true) { selection in
            UIActionHelper.performDelete(
                manager: wallpaperManager,
                selection: selection,
                window: window
            )
        }
    }

    @objc private func handleNavigationSegmentAction(_ sender: NSSegmentedControl) {
        // segmented control 只负责发起方向，不负责计算目标索引。
        switch sender.selectedSegment {
        case 0:
            wallpaperManager.navigateWallpaperManually(.previous)
        case 1:
            wallpaperManager.navigateWallpaperManually(.next)
        default:
            break
        }
    }

    @objc private func handleFavoriteButtonAction() {
        performToolbarAction(requiresNonSettingsSelection: true, refreshAfter: true) { selection in
            UIActionHelper.toggleFavoriteSelection(manager: wallpaperManager, selection: selection)
        }
    }

    @objc private func handleTagButtonAction() {
        performToolbarAction(requiresNonSettingsSelection: true) { _ in
            UIActionHelper.presentTagPicker(
                manager: wallpaperManager,
                window: window
            ) { [weak self] in
                self?.refresh()
            }
        }
    }

    @objc private func handleInfoButtonAction() {
        performToolbarAction(requiresNonSettingsSelection: true) { _ in
            UIActionHelper.presentInfo(manager: wallpaperManager, window: window)
        }
    }

    func performToolbarAction(
        requiresNonSettingsSelection: Bool = false,
        refreshAfter: Bool = false,
        _ action: (WallpaperSelectionContext) -> Void
    ) {
        // 所有工具栏动作统一走 selection context，避免 toolbar 直接碰业务状态的旁路写入。
        let selection = wallpaperManager.currentSelectionContext
        if requiresNonSettingsSelection && selection.isSettings {
            return
        }
        action(selection)
        if refreshAfter {
            refresh()
        }
    }

    func toolbarAvailability() -> ToolbarAvailability {
        let selection = wallpaperManager.currentSelectionContext
        return ToolbarAvailability(
            selection: selection,
            isMultiSelectMode: wallpaperManager.isMultiSelectMode,
            hasWallpapersInSelection: selection.hasWallpapers(in: wallpaperManager),
            hasAnySelection: wallpaperManager.hasAnyWallpaperSelection,
            hasSingleSelection: wallpaperManager.hasSingleWallpaperSelection,
            hasTags: !wallpaperManager.tags.isEmpty
        )
    }

    func configureImportItem(isMultiSelectMode: Bool) {
        let symbolName = isMultiSelectMode ? "checkmark.circle" : "plus.circle"
        let toolTip = isMultiSelectMode ? "全选" : "导入"
        importItem.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "导入")
        importItem.toolTip = toolTip
    }

    func configureSelectItem(isMultiSelectMode: Bool) {
        let symbolName = isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle"
        let toolTip = isMultiSelectMode ? "退出选择模式" : "进入选择模式"
        selectItem.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "选择")
        selectItem.toolTip = toolTip
    }

    func configureFavoriteItem(isFavoritedState: Bool) {
        // 收藏按钮图标状态跟随当前选中集合的统一判定，不按单个卡片局部状态显示。
        if isFavoritedState {
            let redConfig = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            favoriteItem.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "取消收藏")?
                .withSymbolConfiguration(redConfig)
            favoriteItem.image?.isTemplate = false
            favoriteItem.toolTip = "取消收藏选中壁纸"
        } else {
            favoriteItem.image = NSImage(systemSymbolName: "heart", accessibilityDescription: "收藏")
            favoriteItem.image?.isTemplate = true
            favoriteItem.toolTip = "收藏选中壁纸"
        }
    }

    func configureSortItem() {
        // 图标始终保持默认漏斗，不随排序模式变化，避免工具栏图标频繁跳动。
        sortMenuButton.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "排序")
        let key = wallpaperManager.currentSelectionContext.scrollPersistenceKey
        let state = wallpaperManager.sortState(for: key)
        sortMenuButton.contentTintColor = state.mode == .none ? nil : .controlAccentColor
    }

    @objc func handleSortButtonAction(_ sender: NSButton) {
        // 读取当前列表的独立排序状态，构建下拉菜单。
        let key = wallpaperManager.currentSelectionContext.scrollPersistenceKey
        let state = wallpaperManager.sortState(for: key)
        let currentMode = state.mode
        let ascending = state.ascending

        let menu = NSMenu()
        for mode in WallpaperSortMode.allCases {
            let isSelected = currentMode == mode
            var title = mode.displayName
            if mode != .none && isSelected {
                title += ascending ? "  ↑" : "  ↓"
            }
            let item = NSMenuItem(title: title, action: #selector(handleSortMenuItemAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = isSelected ? .on : .off
            menu.addItem(item)
        }
        let buttonBounds = sender.convert(sender.bounds, to: nil)
        let screenRect = sender.window?.convertToScreen(buttonBounds) ?? .zero
        menu.popUp(positioning: nil, at: NSPoint(x: screenRect.minX, y: screenRect.minY), in: nil)
    }

    @objc func handleSortMenuItemAction(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? WallpaperSortMode else { return }
        let key = wallpaperManager.currentSelectionContext.scrollPersistenceKey
        var state = wallpaperManager.sortState(for: key)
        if mode == .none {
            state = SortState(mode: .none, ascending: true)
        } else if state.mode == mode {
            // 重复点击同一非 none 模式：切换升/降序
            state.ascending.toggle()
        } else {
            state = SortState(mode: mode, ascending: true)
        }
        wallpaperManager.setSortState(state, for: key)
        configureSortItem()
    }

}

extension MainWindowToolbarController {
    func controlTextDidBeginEditing(_ obj: Notification) {
        // 搜索框只有在非设置页时才进入 active 搜索态，否则会影响设置页的键盘交互。
        guard !wallpaperManager.currentSelectionContext.isSettings else { return }
        wallpaperManager.isSearchFieldActive = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // 失焦即退出搜索态，避免箭头键继续被搜索框拦住。
        wallpaperManager.isSearchFieldActive = false
    }

    func controlTextDidChange(_ obj: Notification) {
        // 直接把输入值写回 manager，工具栏不保留自己的搜索缓存。
        wallpaperManager.searchQuery = searchItem.searchField.stringValue
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // 工具栏布局固定，避免用户自定义打乱当前设计的分组顺序。
        [IDs.sidebar, IDs.title, .flexibleSpace, IDs.import, IDs.select, .space, IDs.navigation, .space, IDs.delete, IDs.favorite, IDs.tag, IDs.info, IDs.sort, .space, IDs.zoom, .space, IDs.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // 允许项与默认项保持一致，防止自定义面板暴露我们没有验证过的布局组合。
        [IDs.sidebar, IDs.title, IDs.import, IDs.select, IDs.navigation, IDs.delete, IDs.favorite, IDs.tag, IDs.info, IDs.sort, IDs.zoom, IDs.search, .space, .flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case IDs.sidebar:
            return makeSidebarTrackingItem()
        case IDs.title:
            return titleItem
        case IDs.import:
            return importItem
        case IDs.select:
            return selectItem
        case IDs.navigation:
            return navigationItem
        case IDs.delete:
            return deleteItem
        case IDs.favorite:
            return favoriteItem
        case IDs.tag:
            return tagItem
        case IDs.info:
            return infoItem
        case IDs.sort:
            return sortItem
        case IDs.zoom:
            return zoomItem
        case IDs.search:
            return searchItem
        default:
            return nil
        }
    }
}

extension MainWindowToolbarController {
    func configureZoomItem() {
        // segment 0 = 放大，offset 已是最大值（+2）时禁用；segment 1 = 缩小，offset 已是最小值（-2）时禁用。
        let offset = wallpaperManager.gridZoomOffset
        zoomControl.setEnabled(offset <  2, forSegment: 0)
        zoomControl.setEnabled(offset > -2, forSegment: 1)
    }

    @objc func handleZoomSegmentAction(_ sender: NSSegmentedControl) {
        // segment 0 = 放大（plus），segment 1 = 缩小（minus）。
        let delta = sender.selectedSegment == 0 ? 1 : -1
        let newOffset = max(-2, min(2, wallpaperManager.gridZoomOffset + delta))
        guard newOffset != wallpaperManager.gridZoomOffset else { return }
        wallpaperManager.gridZoomOffset = newOffset
        configureZoomItem()
    }
}
