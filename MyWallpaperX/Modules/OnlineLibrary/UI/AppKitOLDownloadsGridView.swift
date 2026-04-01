//
//  AppKitOLDownloadsGridView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//
//  AppKit NSCollectionView 容器，管理已下载在线视频的网格。
//  列数逻辑复用 GridLayoutHelper（zoomOffset 与在线库共享）。
//

import AppKit
import SwiftUI
import Combine
import AVFoundation
import QuickLook
import QuickLookUI

final class OnlineDownloadsBridge {
    static let shared = OnlineDownloadsBridge()
    weak var container: AppKitOLDownloadsContainerView?
    weak var toolbarController: OnlineLibraryToolbarController?
    /// 当前「已下载项」视图是否挂载在窗口中（用于框架层区分浏览页 vs 已下载项）
    var isActive: Bool = false

    func focusGrid() { container?.focusGrid() }
    func focusSearch() { container?.focusSearch() }
    func selectAll() { container?.selectAll(); refreshToolbar() }
    func toggleMultiSelect() { container?.toggleMultiSelect(); refreshToolbar() }
    func deleteSelected() { container?.deleteSelected(); refreshToolbar() }
    func previewSelected() { container?.previewSelected() }
    func setSelectedAsWallpaper() { container?.setSelectedAsWallpaper() }
    func moveSelection(_ keyCode: UInt16) { container?.moveSelectionByArrowKey(keyCode); refreshToolbar() }
    func showInfo() { container?.showInfo() }
    func revealInFinder() { container?.revealInFinder() }

    var hasAnySelection: Bool { container?.hasAnySelection ?? false }
    var hasSingleSelection: Bool { container?.hasSingleSelection ?? false }
    var isMultiSelectMode: Bool { container?.isMultiSelectModeEnabled ?? false }
    var hasAnyItems: Bool { container?.hasAnyItems ?? false }
    var selectedCount: Int { container?.selectedCount ?? 0 }

    func refreshToolbar() {
        toolbarController?.refreshDownloadsToolbarState()
    }
}

final class OLDownloadsQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = OLDownloadsQuickLookController()
    private var previewIDs: [Int] = []
    private var previewItems: [URL] = []
    private var activeIndex: Int = 0
    private var selectionSync: ((Int) -> Void)?

    func open(ids: [Int], urls: [URL], index: Int, selectionSync: @escaping (Int) -> Void) {
        guard !urls.isEmpty, ids.count == urls.count else { return }
        previewIDs = ids
        previewItems = urls
        activeIndex = min(max(0, index), urls.count - 1)
        self.selectionSync = selectionSync
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = activeIndex
        panel.makeKeyAndOrderFront(nil)
    }

    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItems[index] as NSURL
    }

    func previewPanelCurrentPreviewItemIndexDidChange(_ panel: QLPreviewPanel!) {
        let index = panel.currentPreviewItemIndex
        guard index >= 0, index < previewIDs.count else { return }
        activeIndex = index
        selectionSync?(previewIDs[index])
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let disallowed: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowed).isEmpty else { return false }
        
        // 这里接管空格/方向键/ESC，避免系统把事件交回主窗口后再次触发预览开关。
        switch event.keyCode {
        case 49: // Space
            close()
            return true
        case 123, 124, 125, 126: // Arrows
            OnlineDownloadsBridge.shared.moveSelection(event.keyCode)
            panel.reloadData()
            return true
        case 53: // ESC
            close()
            return true
        default:
            return false
        }
    }
}

final class AppKitOLDownloadsCollectionView: NSCollectionView {
    var onBackgroundLeftClick: (() -> Void)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    var primaryClickHandler: ((IndexPath, NSEvent) -> Void)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var deleteHandler: (() -> Void)?
    var spaceHandler: (() -> Void)?
    var enterHandler: (() -> Void)?
    var selectAllHandler: (() -> Void)?
    var arrowHandler: ((UInt16) -> Void)?
    private(set) var lastPrimaryClickIndexPath: IndexPath?
    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        pendingPressReleaseWorkItem?.cancel()
        pendingPressReleaseWorkItem = nil

        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        lastPrimaryClickIndexPath = indexPath

        if let ip = indexPathForItem(at: point) {
            pressedCardIndexPath = ip
            pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
            cardPressStateHandler?(ip, true)
            primaryClickHandler?(ip, event)
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.type == .leftMouseUp else { return }

        if let ip = pressedCardIndexPath {
            let elapsed = ProcessInfo.processInfo.systemUptime - pressedCardTimestamp
            let remaining = max(0, UIInteractionAnimation.minimumPressVisualDuration - elapsed)
            let releaseWork = DispatchWorkItem { [weak self] in
                self?.cardPressStateHandler?(ip, false)
            }
            pendingPressReleaseWorkItem = releaseWork
            if remaining <= 0 {
                releaseWork.perform()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: releaseWork)
            }
            pressedCardIndexPath = nil
        }

        let point = convert(event.locationInWindow, from: nil)
        if lastPrimaryClickIndexPath == nil, indexPathForItem(at: point) == nil {
            onBackgroundLeftClick?()
        }
        lastPrimaryClickIndexPath = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, // Return
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            enterHandler?(); return
        }
        if event.keyCode == 0, // Cmd+A
           event.modifierFlags.intersection([.command]) == .command,
           event.modifierFlags.intersection([.control, .option, .shift]).isEmpty {
            selectAllHandler?(); return
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Delete
            deleteHandler?(); return
        }
        if event.keyCode == 49 { // Space
            spaceHandler?(); return
        }
        let arrows: Set<UInt16> = [123, 124, 125, 126]
        if arrows.contains(event.keyCode) {
            arrowHandler?(event.keyCode); return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        return contextMenuProvider?(indexPath)
    }

    override func selectAll(_ sender: Any?) {
        // 拦截系统 Cmd+A 分发，走自定义全选路径（不触发 NSCollectionView 默认全选行为）
        selectAllHandler?()
    }
}

// MARK: - SwiftUI 桥接

struct AppKitOLDownloadsGridView: NSViewRepresentable {
    func makeNSView(context: Context) -> AppKitOLDownloadsContainerView {
        let v = AppKitOLDownloadsContainerView()
        return v
    }
    func updateNSView(_ nsView: AppKitOLDownloadsContainerView, context: Context) {
        nsView.reloadIfNeeded()
    }
}

// MARK: - 容器

final class AppKitOLDownloadsContainerView: NSView, ModuleFocusable {
    private enum Section { case main }

    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var entries: [OLDownloadedEntry] = []
    private var filteredEntries: [OLDownloadedEntry] = []
    private var searchQuery: String = ""
    private var orderedIDs: [Int] = []
    private var orderedIndexByID: [Int: Int] = [:]
    private var entriesByID: [Int: OLDownloadedEntry] = [:]
    private var currentPlayingNormalizedPath: String?
    private var selectedIDs: Set<Int> = []
    private var selectedAnchorID: Int?
    private var isMultiSelectMode = false
    private var lastComputedColumns: Int = 3
    private var lastAppliedSnapshotIDs: [Int] = []
    private var suppressDownloadedIDsReload = false
    private var pendingPostDeletionSelectionIndex: Int?
    private var sortMode: WallpaperSortMode = {
        let raw = UserDefaults.standard.string(forKey: "OLDownloadsSortMode") ?? ""
        return WallpaperSortMode(rawValue: raw) ?? .none
    }()
    private var sortAscending: Bool = {
        if UserDefaults.standard.object(forKey: "OLDownloadsSortAscending") == nil { return true }
        return UserDefaults.standard.bool(forKey: "OLDownloadsSortAscending")
    }()

    private var effectiveSelectedIDs: Set<Int> {
        if !selectedIDs.isEmpty {
            return selectedIDs
        }
        if let anchor = selectedAnchorID {
            return [anchor]
        }
        return []
    }

    private var primarySelectedID: Int? {
        selectedAnchorID ?? selectedIDs.first
    }

    var hasAnySelection: Bool {
        !effectiveSelectedIDs.isEmpty
    }

    var hasSingleSelection: Bool {
        effectiveSelectedIDs.count == 1
    }

    var isMultiSelectModeEnabled: Bool {
        isMultiSelectMode
    }

    var hasAnyItems: Bool {
        !orderedIDs.isEmpty
    }

    var selectedCount: Int {
        effectiveSelectedIDs.count
    }

    private let emptyLabel: NSTextField = {
        let l = NSTextField(labelWithString: "暂无已下载视频壁纸")
        l.alignment = .center
        l.textColor = .secondaryLabelColor
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var searchField: NSSearchField = {
        let f = NSSearchField()
        f.placeholderString = "搜索已下载项"
        f.sendsSearchStringImmediately = true
        f.translatesAutoresizingMaskIntoConstraints = false
        f.target = self
        f.action = #selector(handleSearchFieldChanged(_:))
        return f
    }()


    private let scrollView: NSScrollView = {
        let s = NSScrollView()
        s.drawsBackground = false
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var collectionView: AppKitOLDownloadsCollectionView = {
        let cv = AppKitOLDownloadsCollectionView()
        cv.isSelectable = false
        cv.backgroundColors = [.clear]
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        let l = NSCollectionViewFlowLayout()
        l.minimumInteritemSpacing = 8
        l.minimumLineSpacing = 16
        l.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return l
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, Int> = {
        NSCollectionViewDiffableDataSource<Section, Int>(
            collectionView: collectionView
        ) { [weak self] cv, indexPath, id -> NSCollectionViewItem? in
            guard let self, let entry = self.entriesByID[id] else { return nil }
            // 直接 init，避免 makeItem 触发 nib 查找导致崩溃
            let item = AppKitOLDownloadsItem(nibName: nil, bundle: nil)
            item.configure(
                entry: entry,
                isSelected: self.effectiveSelectedIDs.contains(id),
                isMultiSelectMode: self.isMultiSelectMode,
                isPlaying: self.normalizedPath(entry.localURL.path) == self.currentPlayingNormalizedPath
            )
            return item
        }
    }()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func setup() {
        AppKitOLDownloadsItem.resetHoverTrackingActivation()
        OnlineDownloadsBridge.shared.container = self
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = dataSource
        collectionView.onBackgroundLeftClick = { [weak self] in
            self?.handleBackgroundClick()
        }
        collectionView.cardPressStateHandler = { [weak self] indexPath, isPressed in
            guard let self,
                  let cell = self.collectionView.item(at: indexPath) as? AppKitOLDownloadsItem
            else { return }
            cell.applyPressedState(isPressed)
        }
        collectionView.primaryClickHandler = { [weak self] indexPath, event in
            self?.handlePrimaryClick(indexPath: indexPath, event: event)
        }
        collectionView.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
        }
        collectionView.enterHandler = { [weak self] in self?.setSelectedAsWallpaper() }
        collectionView.selectAllHandler = { [weak self] in self?.selectAll() }
        collectionView.deleteHandler = { [weak self] in self?.deleteSelected() }
        collectionView.spaceHandler = { [weak self] in self?.previewSelected() }
        collectionView.arrowHandler = { [weak self] key in self?.moveSelectionByArrowKey(key) }
        scrollView.documentView = collectionView

        addSubview(scrollView)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // 观察 zoomOffset 和 downloadedIDs 变化
        OnlineLibraryService.shared.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLayoutItemSize() }
            .store(in: &cancellables)

        OnlineLibraryService.shared.$downloadedIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.suppressDownloadedIDsReload else { return }
                self.reloadEntries()
            }
            .store(in: &cancellables)

        let playbackObserver = NotificationCenter.default.addObserver(
            forName: .onlineDownloadsPlaybackPathDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let path = notification.userInfo?["path"] as? String
            self.currentPlayingNormalizedPath = path.map(self.normalizedPath)
            self.refreshVisiblePlaybackItems(forceReload: true)
        }
        observers.append(playbackObserver)

        let deleteObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsDeleteSelected, object: nil, queue: .main
        ) { [weak self] _ in self?.deleteSelected() }
        observers.append(deleteObserver)

        let reloadObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsReload, object: nil, queue: .main
        ) { [weak self] _ in self?.reloadEntries() }
        observers.append(reloadObserver)

        let selectAllObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsSelectAll, object: nil, queue: .main
        ) { [weak self] _ in self?.selectAll() }
        observers.append(selectAllObserver)

        let toggleMultiObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsToggleMultiSelect, object: nil, queue: .main
        ) { [weak self] _ in self?.toggleMultiSelect() }
        observers.append(toggleMultiObserver)

        let previewObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsPreviewSelected, object: nil, queue: .main
        ) { [weak self] _ in self?.previewSelected() }
        observers.append(previewObserver)

        let setAsWallpaperObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsSetAsWallpaper, object: nil, queue: .main
        ) { [weak self] _ in self?.setSelectedAsWallpaper() }
        observers.append(setAsWallpaperObserver)

        let sortObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsSortDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let modeRaw = notification.userInfo?["mode"] as? String,
               let mode = WallpaperSortMode(rawValue: modeRaw) {
                self.sortMode = mode
                UserDefaults.standard.set(mode.rawValue, forKey: "OLDownloadsSortMode")
            }
            if let ascending = notification.userInfo?["ascending"] as? Bool {
                self.sortAscending = ascending
                UserDefaults.standard.set(ascending, forKey: "OLDownloadsSortAscending")
            }
            self.reloadEntries()
        }
        observers.append(sortObserver)

        let searchObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsSearchQueryChanged, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let q = notification.userInfo?["query"] as? String ?? ""
            self.searchQuery = q
            self.applyFilterAndSnapshot()
        }
        observers.append(searchObserver)

        let focusObserver = NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive, object: nil, queue: .main
        ) { [weak self] notification in
            guard let module = notification.userInfo?["module"] as? String,
                  module == ModuleIdentifier.onlineLibrary.rawValue
            else { return }
            self?.requestFocus()
        }
        observers.append(focusObserver)

        reloadEntries()
    }

    // MARK: - 重载

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        OnlineDownloadsBridge.shared.isActive = (window != nil)
    }

    func reloadIfNeeded() {
        // updateNSView 调用入口（轻量 no-op）
    }

    private func reloadEntries() {
        let dir = OnlineLibraryService.downloadDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            entries = []
            applyFilterAndSnapshot()
            return
        }
        var loaded: [OLDownloadedEntry] = files.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("online_"), name.hasSuffix(".mp4"),
                  let id = Int(name.dropFirst("online_".count).dropLast(".mp4".count))
            else { return nil }
            return Self.makeEntry(id: id, localURL: url)
        }

        loaded.sort { lhs, rhs in
            switch sortMode {
            case .none:
                let lDate = (try? lhs.localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rDate = (try? rhs.localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return sortAscending ? (lDate < rDate) : (lDate > rDate)
            case .name:
                let compare = lhs.localURL.lastPathComponent.localizedStandardCompare(rhs.localURL.lastPathComponent)
                return sortAscending ? (compare == .orderedAscending) : (compare == .orderedDescending)
            case .size:
                let lSize = (try? lhs.localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
                let rSize = (try? rhs.localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
                return sortAscending ? (lSize < rSize) : (lSize > rSize)
            case .dateAdded:
                let lDate = (try? lhs.localURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                    ?? (try? lhs.localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
                let rDate = (try? rhs.localURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                    ?? (try? rhs.localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
                return sortAscending ? (lDate < rDate) : (lDate > rDate)
            }
        }

        entries = loaded
        applyFilterAndSnapshot()
    }

    @objc private func handleSearchFieldChanged(_ sender: NSSearchField) {
        let q = sender.stringValue
        searchQuery = q
        applyFilterAndSnapshot()
    }

    private func applyFilterAndSnapshot() {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filteredEntries = entries
        } else {
            filteredEntries = entries.filter {
                $0.localURL.lastPathComponent.lowercased().contains(q)
            }
        }
        applyEntries(filteredEntries)
    }

    private func applyEntries(_ newEntries: [OLDownloadedEntry]) {
        // newEntries 可以是过滤后的子集，不覆盖 entries（全量）
        entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        orderedIDs = newEntries.map { $0.id }
        orderedIndexByID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) })
        selectedIDs = effectiveSelectedIDs.intersection(Set(orderedIDs))
        if let anchor = selectedAnchorID, !orderedIDs.contains(anchor) {
            selectedAnchorID = nil
        }
        if selectedIDs.isEmpty, let first = orderedIDs.first {
            selectedIDs = [first]
            selectedAnchorID = first
        }

        let isEmpty = orderedIDs.isEmpty
        emptyLabel.stringValue = searchQuery.isEmpty ? "暂无已下载视频壁纸" : "无匹配结果"
        emptyLabel.isHidden = !isEmpty
        applySnapshot(ids: orderedIDs)
        DispatchQueue.main.async {
            OnlineDownloadsBridge.shared.refreshToolbar()
        }
    }

    private func applySnapshot(ids: [Int]) {
        let isReorder = !lastAppliedSnapshotIDs.isEmpty
            && ids.count == lastAppliedSnapshotIDs.count
            && Set(ids) == Set(lastAppliedSnapshotIDs)
        let visibleCount = collectionView.indexPathsForVisibleItems().count
        let animateThreshold = max(20, visibleCount + 20)
        let isInsertDelete = !lastAppliedSnapshotIDs.isEmpty
            && !isReorder
            && abs(ids.count - lastAppliedSnapshotIDs.count) <= animateThreshold
        let shouldAnimate = isInsertDelete

        var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
        snapshot.appendSections([.main])
        snapshot.appendItems(ids, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: shouldAnimate) { [weak self] in
            guard let self else { return }
            self.lastAppliedSnapshotIDs = ids
            self.resolveSelectionAfterSnapshot()
            self.reloadVisibleSelectionItems(forceReload: true)
            self.refreshVisiblePlaybackItems(forceReload: true)
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateLayoutItemSize()
    }

    private func updateLayoutItemSize() {
        let inset = flowLayout.sectionInset
        let available = max(0, bounds.width - inset.left - inset.right)
        let cols = GridLayoutHelper.columnCount(
            for: available,
            zoomOffset: OnlineLibraryService.shared.zoomOffset,
            minCols: 3, maxCols: 6
        )
        lastComputedColumns = cols
        let hoverScale: CGFloat = AppKitOLDownloadsItem.hoverScale
        let estimatedW = max(100, (available - flowLayout.minimumInteritemSpacing * CGFloat(max(0, cols - 1))) / CGFloat(cols))
        let minSpacing = estimatedW * (hoverScale - 1.0)
        let spacing = max(8, minSpacing)
        flowLayout.minimumInteritemSpacing = spacing
        flowLayout.minimumLineSpacing = spacing
        let totalSpacing = CGFloat(max(0, cols - 1)) * spacing
        let cardW = max(100, (available - totalSpacing) / CGFloat(cols))
        let cardH = max(56, cardW / (16.0 / 9.0))
        let newSize = NSSize(width: floor(cardW), height: floor(cardH + 2))
        guard flowLayout.itemSize != newSize else { return }
        flowLayout.itemSize = newSize
        // 布局变化与悬停视觉同步生效，避免渐变层在缩放期间出现跟随滞后。
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    // MARK: - 外部接入 API（供主控层后续挂接）

    func requestFocus() {
        window?.makeFirstResponder(collectionView)
    }

    func focusGrid() {
        requestFocus()
    }

    func focusSearch() {
        // 搜索聚焦由工具栏 olDownloadsSearch 承担，此处保留为空以兼容 bridge 调用
    }

    func selectAll() {
        // 未进入多选模式时自动先进入，对齐视频库/图片库行为
        if !isMultiSelectMode {
            isMultiSelectMode = true
            collectionView.allowsMultipleSelection = true
            if let anchor = selectedAnchorID {
                selectedIDs = [anchor]
            } else if let first = orderedIDs.first {
                selectedAnchorID = first
                selectedIDs = [first]
            }
            reloadVisibleSelectionItems(forceReload: true)
        }
        selectedIDs = Set(orderedIDs)
        reloadVisibleSelectionItems()
        OnlineDownloadsBridge.shared.refreshToolbar()
    }

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if isMultiSelectMode {
            if let anchor = selectedAnchorID {
                selectedIDs = [anchor]
            } else if let first = orderedIDs.first {
                selectedAnchorID = first
                selectedIDs = [first]
            }
        } else if let anchor = selectedAnchorID {
            selectedIDs = [anchor]
        }
        collectionView.allowsMultipleSelection = isMultiSelectMode
        reloadVisibleSelectionItems(forceReload: true)
    }

    func deleteSelected() {
        let targets = Array(effectiveSelectedIDs)
        guard !targets.isEmpty else { return }
        let all = entries
        let currentIndex = all.firstIndex { $0.id == (primarySelectedID ?? targets.first!) } ?? 0
        pendingPostDeletionSelectionIndex = currentIndex
        suppressDownloadedIDsReload = true
        for id in targets {
            guard let entry = entriesByID[id] else { continue }
            let local = OLLocalFile(url: entry.localURL, fileSize: 0, creationDate: Date())
            OnlineLibraryService.shared.deleteLocalFile(local)
        }
        suppressDownloadedIDsReload = false
        reloadEntries()
    }

    func showInfo() {
        let id = primarySelectedID
        guard let id, let entry = entriesByID[id] else { return }
        let path = entry.localURL.path
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let fileSize = attributes[.size] as? Int64 ?? 0
        let fileSizeMB = Double(fileSize) / (1024 * 1024)
        let creationDate = attributes[.creationDate] as? Date ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let dateText = formatter.string(from: creationDate)

        let infoText = """
        文件名: \(entry.localURL.lastPathComponent)
        大小: \(String(format: "%.2f MB", fileSizeMB))
        格式: \(entry.localURL.pathExtension.uppercased())
        持续时间: \(entry.durationString.isEmpty ? "未知" : entry.durationString)
        分辨率: \(entry.resolutionString ?? "未知")
        添加时间: \(dateText)
        路径: \(path)
        """
        let alert = makeAppAlert(title: "视频信息", message: infoText, buttons: ["好"])
        presentAppAlert(alert, in: appModalHostWindow())
    }

    func revealInFinder() {
        let ids = Array(effectiveSelectedIDs)
        let urls = ids.compactMap { entriesByID[$0]?.localURL }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func previewSelected() {
        let targets: [Int]
        let startID: Int
        if isMultiSelectMode {
            let effectiveIDs = effectiveSelectedIDs
            if !effectiveIDs.isEmpty {
                targets = orderedIDs.filter { effectiveIDs.contains($0) }
                startID = primarySelectedID ?? targets.first ?? orderedIDs.first ?? 0
            } else if let anchor = selectedAnchorID {
                targets = [anchor]
                startID = anchor
            } else {
                targets = []
                startID = 0
            }
        } else {
            targets = orderedIDs
            startID = primarySelectedID ?? orderedIDs.first ?? 0
        }
        let urls = targets.compactMap { entriesByID[$0]?.localURL }
        guard !urls.isEmpty else { return }
        let startIndex = max(0, targets.firstIndex(of: startID) ?? 0)
        OLDownloadsQuickLookController.shared.open(
            ids: targets,
            urls: urls,
            index: startIndex,
            selectionSync: { [weak self] id in
                self?.syncSelectionFromQuickLook(id: id)
            }
        )
    }

    func setSelectedAsWallpaper() {
        let id = primarySelectedID
        guard let id else { return }
        setLocalAsWallpaper(id: id)
    }

    func moveSelectionByArrowKey(_ keyCode: UInt16) {
        guard !orderedIDs.isEmpty else { return }
        guard let currentID = primarySelectedID ?? orderedIDs.first,
              let idx = orderedIDs.firstIndex(of: currentID) else { return }
        let cols = max(1, lastComputedColumns)
        var newIdx = idx
        switch keyCode {
        case 123: newIdx = max(0, idx - 1)
        case 124: newIdx = min(orderedIDs.count - 1, idx + 1)
        case 126: newIdx = max(0, idx - cols)
        case 125: newIdx = min(orderedIDs.count - 1, idx + cols)
        default: return
        }
        guard newIdx != idx else { return }
        let targetID = orderedIDs[newIdx]
        selectedAnchorID = targetID
        if isMultiSelectMode {
            selectedIDs = [targetID]
        } else {
            selectedIDs = [targetID]
        }
        reloadVisibleSelectionItems()
        scrollToSelectedItemIfNeeded()
        OnlineDownloadsBridge.shared.refreshToolbar()
    }

    private func handlePrimaryClick(indexPath: IndexPath, event: NSEvent) {
        guard indexPath.item < orderedIDs.count else { return }
        let id = orderedIDs[indexPath.item]
        if isMultiSelectMode {
            if event.modifierFlags.contains(.command) {
                if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
            } else {
                selectedIDs = [id]
            }
        } else {
            selectedIDs = [id]
        }
        selectedAnchorID = id
        reloadVisibleSelectionItems()
        OnlineDownloadsBridge.shared.refreshToolbar()
        if let item = collectionView.item(at: indexPath) as? AppKitOLDownloadsItem {
            let point = item.view.convert(event.locationInWindow, from: nil)
            if item.shouldTriggerPlayAction(at: point) {
                setLocalAsWallpaper(id: id)
            }
        }
    }

    private func setLocalAsWallpaper(id: Int) {
        if let entry = entriesByID[id] {
            currentPlayingNormalizedPath = normalizedPath(entry.localURL.path)
            refreshVisiblePlaybackItems(forceReload: true)
        }
        OnlineLibraryService.shared.setLocalFileAsWallpaper(id: id)
    }

    private func reloadVisibleSelectionItems(forceReload: Bool = false) {
        let visible = collectionView.indexPathsForVisibleItems()
        var fallbackReloadPaths = Set<IndexPath>()
        for ip in visible {
            guard ip.item < orderedIDs.count,
                  ip.item >= 0 else { continue }
            let id = orderedIDs[ip.item]
            if let cell = collectionView.item(at: ip) as? AppKitOLDownloadsItem {
                cell.applySelectionState(effectiveSelectedIDs.contains(id), multiSelectMode: isMultiSelectMode)
            } else if forceReload {
                fallbackReloadPaths.insert(ip)
            }
        }
        if !fallbackReloadPaths.isEmpty {
            collectionView.reloadItems(at: fallbackReloadPaths)
        }
    }

    private func refreshVisiblePlaybackItems(forceReload: Bool = false) {
        let visible = collectionView.indexPathsForVisibleItems()
        var fallbackReloadPaths = Set<IndexPath>()
        for ip in visible {
            guard ip.item >= 0, ip.item < orderedIDs.count else { continue }
            let id = orderedIDs[ip.item]
            guard let entry = entriesByID[id] else { continue }
            let shouldBePlaying = normalizedPath(entry.localURL.path) == currentPlayingNormalizedPath
            if let cell = collectionView.item(at: ip) as? AppKitOLDownloadsItem {
                cell.applyPlayingState(isPlaying: shouldBePlaying)
            } else if forceReload {
                fallbackReloadPaths.insert(ip)
            }
        }
        if !fallbackReloadPaths.isEmpty {
            collectionView.reloadItems(at: fallbackReloadPaths)
        }
    }

    private func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        if let indexPath, indexPath.item < orderedIDs.count {
            let id = orderedIDs[indexPath.item]
            selectedAnchorID = id
            if !isMultiSelectMode || !selectedIDs.contains(id) {
                selectedIDs = [id]
            }
            reloadVisibleSelectionItems()
        }
        guard !effectiveSelectedIDs.isEmpty else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let setItem = NSMenuItem(title: "设为壁纸", action: #selector(contextSetAsWallpaper), keyEquivalent: "")
        setItem.target = self
        setItem.isEnabled = !isMultiSelectMode && primarySelectedID != nil
        setItem.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: "设为壁纸")
        menu.addItem(setItem)

        let infoItem = NSMenuItem(title: "详细信息", action: #selector(contextShowInfo), keyEquivalent: "")
        infoItem.target = self
        infoItem.isEnabled = !isMultiSelectMode && primarySelectedID != nil
        infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "详细信息")
        menu.addItem(infoItem)

        let revealItem = NSMenuItem(title: "查看文件", action: #selector(contextRevealInFinder), keyEquivalent: "")
        revealItem.target = self
        revealItem.isEnabled = !isMultiSelectMode && primarySelectedID != nil
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "在访达中显示")
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "删除", action: #selector(contextDeleteSelected), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = !selectedIDs.isEmpty || selectedAnchorID != nil
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func contextSetAsWallpaper() {
        setSelectedAsWallpaper()
    }

    @objc private func contextShowInfo() {
        showInfo()
    }

    @objc private func contextRevealInFinder() {
        revealInFinder()
    }

    @objc private func contextDeleteSelected() {
        deleteSelected()
    }

    private func syncSelectionFromQuickLook(id: Int) {
        guard orderedIndexByID[id] != nil else { return }
        selectedAnchorID = id
        selectedIDs = [id]
        reloadVisibleSelectionItems()
        scrollToSelectedItemIfNeeded()
    }

    private func handleBackgroundClick() {
        guard !isMultiSelectMode else { return }
        selectedIDs = []
        selectedAnchorID = nil
        reloadVisibleSelectionItems()
    }

    private func scrollToSelectedItemIfNeeded() {
        guard !isMultiSelectMode,
              let selectedID = primarySelectedID,
              let index = orderedIndexByID[selectedID] else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard let attrs = flowLayout.layoutAttributesForItem(at: indexPath) else { return }
        let itemFrame = attrs.frame
        let visibleRect = scrollView.contentView.bounds
        guard !visibleRect.contains(itemFrame) else { return }
        let targetY: CGFloat
        if itemFrame.minY < visibleRect.minY {
            targetY = max(0, itemFrame.minY - 4)
        } else {
            targetY = itemFrame.maxY - visibleRect.height + 4
        }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visibleRect.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func resolveSelectionAfterSnapshot() {
        guard let desiredIndex = pendingPostDeletionSelectionIndex else { return }
        pendingPostDeletionSelectionIndex = nil
        guard !orderedIDs.isEmpty else {
            selectedAnchorID = nil
            selectedIDs = []
            return
        }
        let nextIndex = min(desiredIndex, orderedIDs.count - 1)
        let nextID = orderedIDs[nextIndex]
        selectedAnchorID = nextID
        selectedIDs = [nextID]
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func makeEntry(id: Int, localURL: URL) -> OLDownloadedEntry {
        let asset = AVURLAsset(url: localURL)
        let durationSeconds = max(0, Int(asset.duration.seconds.rounded()))
        var resolution: String?
        if let track = asset.tracks(withMediaType: .video).first {
            let transformed = track.naturalSize.applying(track.preferredTransform)
            let width = Int(abs(transformed.width).rounded())
            let height = Int(abs(transformed.height).rounded())
            if width > 0, height > 0 {
                resolution = "\(width)×\(height)"
            }
        }
        return OLDownloadedEntry(
            id: id,
            localURL: localURL,
            fileSize: (try? localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0,
            duration: durationSeconds,
            resolutionString: resolution
        )
    }
}

extension Notification.Name {
    static let olDownloadsDeleteSelected    = Notification.Name("OLDownloadsDeleteSelected")
    static let olDownloadsSelectAll         = Notification.Name("OLDownloadsSelectAll")
    static let olDownloadsToggleMultiSelect = Notification.Name("OLDownloadsToggleMultiSelect")
    static let olDownloadsPreviewSelected   = Notification.Name("OLDownloadsPreviewSelected")
    static let olDownloadsSetAsWallpaper    = Notification.Name("OLDownloadsSetAsWallpaper")
    static let olDownloadsReload            = Notification.Name("OLDownloadsReload")
    static let olDownloadsSortDidChange     = Notification.Name("OLDownloadsSortDidChange")
    static let olDownloadsSearchQueryChanged  = Notification.Name("OLDownloadsSearchQueryChanged")
}
