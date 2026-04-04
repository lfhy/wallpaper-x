//
//  AppKitSteamWorkshopDownloadsGridView.swift
//  MyWallpaperX
//

import AppKit
import SwiftUI
import Combine

struct AppKitSteamWorkshopDownloadsGridView: NSViewRepresentable {
    @ObservedObject var service: SteamWorkshopService
    let onOpen: (SteamWorkshopBrowserItem) -> Void
    let onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    let onReveal: (SteamWorkshopDownloadRecord) -> Void

    func makeNSView(context: Context) -> AppKitSteamWorkshopDownloadsContainerView {
        AppKitSteamWorkshopDownloadsContainerView(
            service: service,
            onOpen: onOpen,
            onSetAsWallpaper: onSetAsWallpaper,
            onReveal: onReveal
        )
    }

    func updateNSView(_ nsView: AppKitSteamWorkshopDownloadsContainerView, context: Context) {
        nsView.onOpen = onOpen
        nsView.onSetAsWallpaper = onSetAsWallpaper
        nsView.onReveal = onReveal
    }
}

final class AppKitSteamWorkshopDownloadsContainerView: NSView, ModuleFocusable {
    private enum Section {
        case main
    }

    private let service: SteamWorkshopService
    var onOpen: (SteamWorkshopBrowserItem) -> Void
    var onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    var onReveal: (SteamWorkshopDownloadRecord) -> Void

    private var cancellables = Set<AnyCancellable>()
    private var orderedIDs: [String] = []
    private var recordsByID: [String: SteamWorkshopDownloadRecord] = [:]
    private var keyboardFocusedID: String?
    private var currentColumnCount = 1
    private var moduleActivationObserver: NSObjectProtocol?
    private var isApplyingSelectionSnapshot = false

    private let scrollView: NSScrollView = {
        let s = NSScrollView()
        s.drawsBackground = false
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var collectionView: SteamWorkshopKeyboardCollectionView = {
        let cv = SteamWorkshopKeyboardCollectionView()
        cv.isSelectable = false
        cv.allowsEmptySelection = true
        cv.backgroundColors = [.clear]
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.keyboardDelegate = self
        cv.cardPressStateHandler = { [weak self] indexPath, pressed in
            guard let self,
                  let item = self.collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { return }
            item.applyPressedState(pressed)
        }
        cv.primaryClickHandler = { [weak self] indexPath in
            self?.handlePrimaryClick(at: indexPath) ?? false
        }
        cv.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
        }
        cv.onBackgroundLeftClick = { [weak self] in
            self?.handleBackgroundClick()
        }
        return cv
    }()

    private let emptyLabel: NSTextField = {
        let label = NSTextField(labelWithString: "当前 workshop 目录里还没有已下载的视频项目")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        let l = NSCollectionViewFlowLayout()
        l.minimumInteritemSpacing = 8
        l.minimumLineSpacing = 8
        l.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return l
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, String> = {
        NSCollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { [weak self] _, _, id in
            guard let self,
                  let record = self.recordsByID[id] else { return nil }
            let item = AppKitSteamWorkshopBrowserItem(nibName: nil, bundle: nil)
            self.configureDownloadItem(item, for: record)
            return item
        }
    }()

    init(
        service: SteamWorkshopService,
        onOpen: @escaping (SteamWorkshopBrowserItem) -> Void,
        onSetAsWallpaper: @escaping (SteamWorkshopDownloadRecord) -> Void,
        onReveal: @escaping (SteamWorkshopDownloadRecord) -> Void
    ) {
        self.service = service
        self.onOpen = onOpen
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onReveal = onReveal
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let moduleActivationObserver {
            NotificationCenter.default.removeObserver(moduleActivationObserver)
        }
    }

    func requestFocus() {
        window?.makeFirstResponder(collectionView)
    }

    override func layout() {
        super.layout()
        updateLayoutItemSize()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = dataSource
        collectionView.delegate = self
        scrollView.documentView = collectionView

        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        service.$downloads
            .combineLatest(service.$downloadsQuery)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.applyRecords(self?.service.filteredDownloads ?? [])
                self?.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        service.$selectedDownloadID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySelection()
                self?.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        service.$selectedDownloadIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySelection()
                self?.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        service.$isDownloadsMultiSelectMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMultiSelect in
                guard let self else { return }
                self.collectionView.allowsMultipleSelection = isMultiSelect
                self.applySelection()
                self.refreshVisibleDownloadItems()
            }
            .store(in: &cancellables)

        service.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLayoutItemSize()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            service.$downloadsSortMode,
            service.$downloadsSortAscending
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.applyRecords(self?.service.filteredDownloads ?? [])
            self?.refreshVisibleDownloadItems()
        }
        .store(in: &cancellables)

        moduleActivationObserver = NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let module = notification.userInfo?["module"] as? String,
                  module == ModuleIdentifier.steamWorkshop.rawValue else { return }
            self?.requestFocus()
        }

        applyRecords(service.filteredDownloads)
    }

    private func applyRecords(_ records: [SteamWorkshopDownloadRecord]) {
        recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        orderedIDs = records.map(\.id)

        if let selectedID = service.selectedDownloadID,
           orderedIDs.contains(selectedID) == false {
            service.selectDownload(itemID: nil)
        }

        emptyLabel.isHidden = !orderedIDs.isEmpty

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(orderedIDs, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
        ensureKeyboardFocus()
    }

    private func configureDownloadItem(_ item: AppKitSteamWorkshopBrowserItem, for record: SteamWorkshopDownloadRecord) {
        let displayItem = record.displayItem ?? fallbackDisplayItem(for: record)
        item.configure(
            displayContext: .downloads,
            item: displayItem,
            downloadRecord: record,
            isDownloading: record.status == .downloading,
            isDownloaded: record.status == .ready && record.isPlayable,
            isMultiSelectMode: service.isDownloadsMultiSelectMode,
            isKeyboardFocused: service.effectiveSelectedDownloadIDs.contains(record.id),
            onOpen: { [weak self] in
                self?.presentDownloadDetail(for: record.id)
            },
            onAuthor: { [weak self] in
                self?.onReveal(record)
            },
            onDownload: { [weak self] in
                guard let self else { return }
                switch record.status {
                case .ready:
                    if record.isPlayable {
                        self.onSetAsWallpaper(record)
                    }
                case .failed:
                    self.service.downloadWorkshopItem(id: record.id, pageTitle: record.title)
                case .queued:
                    self.service.cancelDownload(itemID: record.id)
                case .downloading:
                    self.service.cancelDownload(itemID: record.id)
                }
            },
            onSetAsWallpaper: { [weak self] in self?.onSetAsWallpaper(record) },
            onCancelDownload: { [weak self] in self?.service.cancelDownload(itemID: record.id) }
        )
        item.setPrefersCircularPlayBadge(record.status == .ready && record.isPlayable)
    }

    private func refreshVisibleDownloadItems() {
        for visibleItem in collectionView.visibleItems() {
            guard let item = visibleItem as? AppKitSteamWorkshopBrowserItem,
                  let indexPath = collectionView.indexPath(for: item),
                  indexPath.item < orderedIDs.count else { continue }
            let id = orderedIDs[indexPath.item]
            guard let record = recordsByID[id] else { continue }
            configureDownloadItem(item, for: record)
        }
    }

    private func fallbackDisplayItem(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: record.id,
            title: record.title,
            author: "未知作者",
            authorProfileURL: nil,
            authorWorkshopURL: nil,
            hasAdultContent: false,
            summary: record.description,
            descriptionText: record.description,
            tags: record.tags,
            workshopTypeText: "Video",
            ageRatingText: nil,
            genreText: nil,
            categoryText: "Wallpaper",
            previewImageURL: record.previewURL,
            previewVideoURL: nil,
            previewAssetKind: .stillImage,
            fileSizeText: record.sizeText,
            resolutionText: nil,
            postedText: nil,
            updatedText: nil,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: SteamWorkshopService.makeDetailURL(id: record.id)
        )
    }

    private func updateLayoutItemSize() {
        let inset = flowLayout.sectionInset
        let availableWidth = max(0, bounds.width - inset.left - inset.right)
        let columns = GridLayoutHelper.columnCount(
            for: availableWidth,
            zoomOffset: service.zoomOffset
        )
        currentColumnCount = max(1, columns)
        let hoverScale: CGFloat = AppKitSteamWorkshopBrowserItem.hoverScale
        let baseSpacing: CGFloat = 8
        let estimatedWidth = max(100, (availableWidth - baseSpacing * CGFloat(max(0, columns - 1))) / CGFloat(columns))
        let minSpacing = estimatedWidth * (hoverScale - 1.0)
        let spacing = max(baseSpacing, minSpacing)
        let verticalSpacing = spacing + 2
        flowLayout.minimumInteritemSpacing = spacing
        flowLayout.minimumLineSpacing = verticalSpacing
        let totalSpacing = CGFloat(max(0, columns - 1)) * spacing
        let cardWidth = max(100, (availableWidth - totalSpacing) / CGFloat(columns))
        let newSize = NSSize(width: floor(cardWidth), height: floor(cardWidth))
        guard flowLayout.itemSize != newSize else { return }
        flowLayout.itemSize = newSize
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    private func ensureKeyboardFocus() {
        guard !orderedIDs.isEmpty else {
            keyboardFocusedID = nil
            service.replaceSelectedDownloads(with: [], primaryID: nil)
            return
        }
        if let focusedID = keyboardFocusedID, orderedIDs.contains(focusedID) {
            reloadKeyboardFocus(previous: nil, next: focusedID)
            return
        }
        focusItem(at: 0)
    }

    private func focusItem(at index: Int) {
        guard index >= 0, index < orderedIDs.count else { return }
        let nextID = orderedIDs[index]
        let previousID = keyboardFocusedID
        guard previousID != nextID else {
            reloadKeyboardFocus(previous: previousID, next: nextID)
            scrollToItem(nextID)
            return
        }
        keyboardFocusedID = nextID
        if !service.isDownloadsMultiSelectMode {
            service.selectDownload(itemID: nextID)
        }
        reloadKeyboardFocus(previous: previousID, next: nextID)
        scrollToItem(nextID)
    }

    private func moveFocus(delta: Int) -> Bool {
        guard !orderedIDs.isEmpty else { return false }
        let current = focusedIndex ?? 0
        let next = min(max(0, current + delta), orderedIDs.count - 1)
        guard next != current || keyboardFocusedID == nil else { return false }
        focusItem(at: next)
        return true
    }

    private var focusedIndex: Int? {
        guard let id = keyboardFocusedID else { return nil }
        return orderedIDs.firstIndex(of: id)
    }

    private func handleReturnKey() -> Bool {
        guard let id = keyboardFocusedID,
              let record = recordsByID[id] else { return false }
        switch record.status {
        case .ready:
            if record.isPlayable {
                onSetAsWallpaper(record)
            }
        case .failed:
            service.downloadWorkshopItem(id: record.id, pageTitle: record.title)
        case .queued:
            service.cancelDownload(itemID: record.id)
        case .downloading:
            service.cancelDownload(itemID: record.id)
        }
        return true
    }

    private func handleBackgroundClick() {
        guard !service.isDownloadsMultiSelectMode else { return }
        keyboardFocusedID = nil
        service.selectDownload(itemID: nil)
    }

    private func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        if let indexPath,
           indexPath.item >= 0,
           indexPath.item < orderedIDs.count {
            let id = orderedIDs[indexPath.item]
            keyboardFocusedID = id
            if service.isDownloadsMultiSelectMode {
                if !service.selectedDownloadIDs.contains(id) {
                    service.replaceSelectedDownloads(with: [id], primaryID: id)
                }
            } else if service.selectedDownloadID != id {
                service.selectDownload(itemID: id)
            }
            reloadKeyboardFocus(previous: nil, next: id)
        }

        let selection = service.effectiveSelectedDownloadIDs
        guard !selection.isEmpty else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false

        if !service.isDownloadsMultiSelectMode,
           let record = service.selectedDownloadRecord {
            if record.status == .ready, record.isPlayable {
                let setItem = NSMenuItem(title: "设为壁纸", action: #selector(contextSetAsWallpaper), keyEquivalent: "")
                setItem.target = self
                setItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "设为壁纸")
                menu.addItem(setItem)
            } else if case .failed = record.status {
                let retryItem = NSMenuItem(title: "重新下载", action: #selector(contextRetryDownload), keyEquivalent: "")
                retryItem.target = self
                retryItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "重新下载")
                menu.addItem(retryItem)
            } else if record.status == .queued || record.status == .downloading {
                let cancelItem = NSMenuItem(title: "取消下载", action: #selector(contextCancelDownload), keyEquivalent: "")
                cancelItem.target = self
                cancelItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消下载")
                menu.addItem(cancelItem)
            }

            let infoItem = NSMenuItem(title: "信息", action: #selector(contextShowInfo), keyEquivalent: "")
            infoItem.target = self
            infoItem.isEnabled = service.canShowSelectedDownloadInfo
            infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "信息")
            menu.addItem(infoItem)

            let revealItem = NSMenuItem(title: "查看文件", action: #selector(contextRevealItem), keyEquivalent: "")
            revealItem.target = self
            revealItem.isEnabled = service.canRevealSelectedDownload
            revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "查看文件")
            menu.addItem(revealItem)
            menu.addItem(.separator())
        }

        let deleteItem = NSMenuItem(title: "删除", action: #selector(contextDeleteSelected), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = service.canDeleteSelectedDownload
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        menu.addItem(deleteItem)
        return menu
    }

    private func handlePrimaryClick(at indexPath: IndexPath) -> Bool {
        guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { return true }
        let id = orderedIDs[indexPath.item]
        if !service.isDownloadsMultiSelectMode {
            let previousID = keyboardFocusedID
            keyboardFocusedID = id
            reloadKeyboardFocus(previous: previousID, next: id)
            service.selectDownload(itemID: id)
            return true
        }

        var selectedIDs = service.selectedDownloadIDs
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        keyboardFocusedID = id
        service.replaceSelectedDownloads(with: selectedIDs, primaryID: id)
        return true
    }

    private func scrollToItem(_ id: String) {
        guard let indexPath = indexPathForItemID(id),
              let attrs = flowLayout.layoutAttributesForItem(at: indexPath) else { return }
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

    private func indexPathForItemID(_ id: String) -> IndexPath? {
        guard let index = orderedIDs.firstIndex(of: id) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    private func cellForItemID(_ id: String) -> AppKitSteamWorkshopBrowserItem? {
        guard let indexPath = indexPathForItemID(id) else { return nil }
        return collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem
    }

    private func reloadKeyboardFocus(previous: String?, next: String?) {
        updateKeyboardFocusItem(withID: previous, focused: false)
        updateKeyboardFocusItem(withID: next, focused: true)
    }

    private func applySelection() {
        let selectedIndexPaths = Set(collectionView.selectionIndexPaths)
        guard !selectedIndexPaths.isEmpty else { return }
        isApplyingSelectionSnapshot = true
        collectionView.deselectItems(at: selectedIndexPaths)
        isApplyingSelectionSnapshot = false
    }

    private func presentDownloadDetail(for id: String) {
        guard recordsByID[id] != nil else { return }
        service.presentDownloadInfo(for: id)
    }

    private func updateKeyboardFocusItem(withID id: String?, focused: Bool) {
        guard let id else { return }
        if let item = cellForItemID(id) {
            item.setKeyboardFocus(focused)
            return
        }
        guard let indexPath = indexPathForItemID(id) else { return }
        collectionView.reloadItems(at: Set([indexPath]))
    }
}

extension AppKitSteamWorkshopDownloadsContainerView: SteamWorkshopKeyboardDelegate {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool {
        if event.keyCode == 0,
           event.modifierFlags.intersection([.command]) == .command,
           event.modifierFlags.intersection([.control, .option, .shift]).isEmpty,
           service.isDownloadsMultiSelectMode {
            service.replaceSelectedDownloads(with: Set(orderedIDs), primaryID: keyboardFocusedID ?? orderedIDs.first)
            return true
        }

        if service.isDownloadsMultiSelectMode {
            let arrows: Set<UInt16> = [123, 124, 125, 126]
            return arrows.contains(event.keyCode)
        }
        switch event.keyCode {
        case 123:
            return moveFocus(delta: -1)
        case 124:
            return moveFocus(delta: 1)
        case 126:
            return moveFocus(delta: -currentColumnCount)
        case 125:
            return moveFocus(delta: currentColumnCount)
        case 36, 76:
            return handleReturnKey()
        default:
            break
        }
        return false
    }
}

extension AppKitSteamWorkshopDownloadsContainerView: NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelectionSnapshot else { return }
        let selectedIDs = Set<String>(collectionView.selectionIndexPaths.compactMap { indexPath in
            guard indexPath.item < orderedIDs.count else { return nil }
            return orderedIDs[indexPath.item]
        })
        guard !selectedIDs.isEmpty else {
            service.replaceSelectedDownloads(with: [], primaryID: nil)
            return
        }
        let selectedID = indexPaths.first.flatMap { path in
            path.item < orderedIDs.count ? orderedIDs[path.item] : nil
        } ?? selectedIDs.first
        let previousID = keyboardFocusedID
        keyboardFocusedID = selectedID
        service.replaceSelectedDownloads(with: selectedIDs, primaryID: selectedID)
        reloadKeyboardFocus(previous: previousID, next: selectedID)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingSelectionSnapshot else { return }
        let remainingIDs = Set<String>(collectionView.selectionIndexPaths.compactMap { indexPath in
            guard indexPath.item < orderedIDs.count else { return nil }
            return orderedIDs[indexPath.item]
        })
        let previousID = keyboardFocusedID
        keyboardFocusedID = remainingIDs.contains(previousID ?? "") ? previousID : remainingIDs.first
        service.replaceSelectedDownloads(with: remainingIDs, primaryID: keyboardFocusedID)
        reloadKeyboardFocus(previous: previousID, next: keyboardFocusedID)
    }
}

extension AppKitSteamWorkshopDownloadsContainerView {
    @objc private func contextSetAsWallpaper() {
        guard let record = service.selectedDownloadRecord, record.status == .ready, record.isPlayable else { return }
        onSetAsWallpaper(record)
    }

    @objc private func contextRetryDownload() {
        guard let record = service.selectedDownloadRecord else { return }
        guard case .failed = record.status else { return }
        service.downloadWorkshopItem(id: record.id, pageTitle: record.title)
    }

    @objc private func contextCancelDownload() {
        guard let record = service.selectedDownloadRecord else { return }
        switch record.status {
        case .queued, .downloading:
            service.cancelDownload(itemID: record.id)
        case .ready, .failed:
            break
        }
    }

    @objc private func contextShowInfo() {
        service.presentSelectedDownloadInfo()
    }

    @objc private func contextRevealItem() {
        service.revealSelectedDownload()
    }

    @objc private func contextDeleteSelected() {
        service.deleteSelectedDownload()
    }
}
