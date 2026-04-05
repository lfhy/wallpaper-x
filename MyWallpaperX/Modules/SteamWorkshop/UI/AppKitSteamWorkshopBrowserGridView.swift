//
//  AppKitSteamWorkshopBrowserGridView.swift
//  MyWallpaperX
//

import AppKit
import SwiftUI
import Combine

struct AppKitSteamWorkshopBrowserGridView: NSViewRepresentable {
    @ObservedObject var service: SteamWorkshopService
    let onOpen: (SteamWorkshopBrowserItem) -> Void
    let onAuthor: (SteamWorkshopBrowserItem) -> Void
    let onDownload: (SteamWorkshopBrowserItem) -> Void
    let onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    let onCancelDownload: (SteamWorkshopBrowserItem) -> Void

    func makeNSView(context: Context) -> AppKitSteamWorkshopBrowserContainerView {
        AppKitSteamWorkshopBrowserContainerView(
            service: service,
            onOpen: onOpen,
            onAuthor: onAuthor,
            onDownload: onDownload,
            onSetAsWallpaper: onSetAsWallpaper,
            onCancelDownload: onCancelDownload
        )
    }

    func updateNSView(_ nsView: AppKitSteamWorkshopBrowserContainerView, context: Context) {
        nsView.onOpen = onOpen
        nsView.onAuthor = onAuthor
        nsView.onDownload = onDownload
        nsView.onSetAsWallpaper = onSetAsWallpaper
        nsView.onCancelDownload = onCancelDownload
    }
}

final class AppKitSteamWorkshopBrowserContainerView: NSView, ModuleFocusable, NSCollectionViewDelegateFlowLayout {
    private enum Section {
        case main
        case status
    }

    private enum FooterState: Equatable {
        case hidden
        case ready
        case loading
        case exhausted

        var logLabel: String {
            switch self {
            case .hidden: return "hidden"
            case .ready: return "ready"
            case .loading: return "loading"
            case .exhausted: return "exhausted"
            }
        }
    }

    private static let footerItemID = "__steam_workshop_grid_footer__"
    private static let footerReadyMessage = "继续下滑以加载更多项目。"
    private static let footerExhaustedMessage = "已到达当前可抓取内容底部。受 Steam 官方页面可见性与分页限制影响，部分作品可能无法完整抓取；如需核对，请以 Steam 官方网页为准。"

    private let service: SteamWorkshopService
    var onOpen: (SteamWorkshopBrowserItem) -> Void
    var onAuthor: (SteamWorkshopBrowserItem) -> Void
    var onDownload: (SteamWorkshopBrowserItem) -> Void
    var onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    var onCancelDownload: (SteamWorkshopBrowserItem) -> Void

    private var cancellables = Set<AnyCancellable>()
    private var itemsByID: [String: SteamWorkshopBrowserItem] = [:]
    private var orderedIDs: [String] = []
    private var displayIDs: [String] = []
    private var footerState: FooterState = .hidden
    private var isApplyingSnapshot = false
    private var pendingFooterSnapshotRefresh = false
    private var moduleActivationObserver: NSObjectProtocol?
    private var lastPrioritizedVisibleIDs: [String] = []

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var collectionView: SteamWorkshopKeyboardCollectionView = {
        let collectionView = SteamWorkshopKeyboardCollectionView()
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.keyboardDelegate = self
        collectionView.cardPressStateHandler = { [weak self] indexPath, pressed in
            guard let self,
                  let item = self.collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { return }
            item.applyPressedState(pressed)
        }
        return collectionView
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return layout
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, String> = {
        let dataSource = NSCollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { [weak self] _, indexPath, id in
            guard let self else { return nil }
            if id == Self.footerItemID {
                let item = AppKitSteamWorkshopBrowserFooterItem()
                item.configure(
                    text: self.footerText(for: self.footerState),
                    showsProgress: self.footerState == .loading
                )
                return item
            }
            guard let item = self.itemsByID[id] else { return nil }
            let cell = AppKitSteamWorkshopBrowserItem(nibName: nil, bundle: nil)
            self.configureCell(cell, for: id)
            return cell
        }
        return dataSource
    }()

    init(
        service: SteamWorkshopService,
        onOpen: @escaping (SteamWorkshopBrowserItem) -> Void,
        onAuthor: @escaping (SteamWorkshopBrowserItem) -> Void,
        onDownload: @escaping (SteamWorkshopBrowserItem) -> Void,
        onSetAsWallpaper: @escaping (SteamWorkshopDownloadRecord) -> Void,
        onCancelDownload: @escaping (SteamWorkshopBrowserItem) -> Void
    ) {
        self.service = service
        self.onOpen = onOpen
        self.onAuthor = onAuthor
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
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
        scrollView.contentView.postsBoundsChangedNotifications = true

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        service.$displayedBrowserItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyItems($0) }
            .store(in: &cancellables)

        service.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLayoutItemSize() }
            .store(in: &cancellables)

        service.$activeDownloadItemID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)

        service.$downloads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)

        service.$previewReloadToken
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.forceReloadVisiblePreviews()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            service.$isLoadingMoreBrowserItems,
            service.$hasMoreBrowserItems
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.refreshFooterState()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.updateBrowserScrollMetrics()
            self.prioritizeVisibleItemsForHydration()
            self.checkLoadMore()
        }
        .store(in: &cancellables)

        service.$pendingBrowserScrollRestoreOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] offsetY in
                guard let self, let offsetY else { return }
                self.restoreScrollOffset(offsetY)
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

        applyItems(service.displayedBrowserItems)
    }

    private func applyItems(_ items: [SteamWorkshopBrowserItem]) {
        let previousItemsByID = itemsByID
        let previousOrderedIDs = orderedIDs
        let previousFooterState = footerState
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        orderedIDs = items.map(\.id)
        footerState = resolvedFooterState()
        displayIDs = orderedIDs + (footerState == .hidden ? [] : [Self.footerItemID])
        let changedIDs = orderedIDs.filter { id in
            guard let previous = previousItemsByID[id], let current = itemsByID[id] else { return false }
            return previous != current
        }
        let structureUnchanged = previousOrderedIDs == orderedIDs && previousFooterState == footerState
        if structureUnchanged {
            if !changedIDs.isEmpty {
                reloadVisibleMetadata(for: Set(changedIDs))
            } else if footerState != .hidden {
                configureVisibleFooterIfNeeded()
            }
            updateBrowserScrollMetrics()
            prioritizeVisibleItemsForHydration()
            checkLoadMore()
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(orderedIDs, toSection: .main)
        if footerState != .hidden {
            snapshot.appendSections([.status])
            snapshot.appendItems([Self.footerItemID], toSection: .status)
        }
        isApplyingSnapshot = true
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.isApplyingSnapshot = false
            if !changedIDs.isEmpty {
                self.reloadVisibleItems()
            }
            self.refreshFooterState(forceReload: true)
            self.updateBrowserScrollMetrics()
            self.prioritizeVisibleItemsForHydration()
            self.checkLoadMore()
        }
    }

    private func reloadVisibleMetadata(for changedIDs: Set<String>) {
        guard !changedIDs.isEmpty else { return }
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: indexPath), changedIDs.contains(id) else { continue }
            guard let cell = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { continue }
            guard itemsByID[id] != nil else { continue }
            configureMetadataCell(cell, for: id)
        }
    }

    private func reloadVisibleItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
            if id == Self.footerItemID {
                guard let footerItem = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserFooterItem else { continue }
                footerItem.configure(
                    text: footerText(for: footerState),
                    showsProgress: footerState == .loading
                )
                continue
            }
            guard let cell = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { continue }
            guard itemsByID[id] != nil else { continue }
            configureCell(cell, for: id)
        }
    }

    private func forceReloadVisiblePreviews() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: indexPath), id != Self.footerItemID else { continue }
            guard let cell = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { continue }
            guard itemsByID[id] != nil else { continue }
            cell.forceReloadPreview()
        }
    }

    private func configureCell(_ cell: AppKitSteamWorkshopBrowserItem, for id: String) {
        guard let item = itemsByID[id] else { return }
        cell.configure(
            displayContext: .browser,
            item: item,
            downloadRecord: service.latestDownloadRecord(for: id),
            isDownloading: service.isDownloading(itemID: id),
            isDownloaded: service.isDownloaded(itemID: id),
            isKeyboardFocused: false,
            onOpen: { [weak self] in self?.onOpen(item) },
            onAuthor: { [weak self] in self?.onAuthor(item) },
            onDownload: { [weak self] in self?.onDownload(item) },
            onSetAsWallpaper: { [weak self] in
                guard let self, let record = self.service.playableDownloadRecord(for: id) else { return }
                self.onSetAsWallpaper(record)
            },
            onCancelDownload: { [weak self] in self?.onCancelDownload(item) }
        )
    }

    private func configureMetadataCell(_ cell: AppKitSteamWorkshopBrowserItem, for id: String) {
        guard let item = itemsByID[id] else { return }
        cell.configureMetadataOnly(
            displayContext: .browser,
            item: item,
            downloadRecord: service.latestDownloadRecord(for: id),
            isDownloading: service.isDownloading(itemID: id),
            isDownloaded: service.isDownloaded(itemID: id),
            isKeyboardFocused: false,
            onOpen: { [weak self] in self?.onOpen(item) },
            onAuthor: { [weak self] in self?.onAuthor(item) },
            onDownload: { [weak self] in self?.onDownload(item) },
            onSetAsWallpaper: { [weak self] in
                guard let self, let record = self.service.playableDownloadRecord(for: id) else { return }
                self.onSetAsWallpaper(record)
            },
            onCancelDownload: { [weak self] in self?.onCancelDownload(item) }
        )
    }

    private func checkLoadMore() {
        guard service.hasMoreBrowserItems, !service.isLoadingMoreBrowserItems else { return }
        guard let documentView = scrollView.documentView else { return }
        let contentHeight = documentView.frame.height
        let viewportHeight = scrollView.contentView.bounds.height
        let offsetY = scrollView.contentView.bounds.origin.y
        guard contentHeight > 0, viewportHeight > 0 else { return }
        let preloadDistance = max(720, viewportHeight * 2.5)
        if contentHeight - offsetY - viewportHeight < preloadDistance {
            service.loadMoreBrowserItemsIfNeeded()
        }
    }

    private func handleEscapeKey() -> Bool {
        guard service.selectedBrowserItem != nil else { return false }
        InspectorHostActions.postClose()
        return true
    }

    private func indexPathForItemID(_ id: String) -> IndexPath? {
        guard let index = orderedIDs.firstIndex(of: id) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    private func cellForItemID(_ id: String) -> AppKitSteamWorkshopBrowserItem? {
        guard let indexPath = indexPathForItemID(id) else { return nil }
        return collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem
    }

    private func prioritizeVisibleItemsForHydration() {
        let visibleIDs = collectionView.indexPathsForVisibleItems()
            .sorted()
            .compactMap { indexPath -> String? in
                guard let id = dataSource.itemIdentifier(for: indexPath), id != Self.footerItemID else { return nil }
                return id
            }
        guard !visibleIDs.isEmpty else { return }
        let prioritized = Array(visibleIDs.prefix(16))
        guard prioritized != lastPrioritizedVisibleIDs else { return }
        lastPrioritizedVisibleIDs = prioritized
        service.prioritizeVisibleBrowserItemIDs(prioritized)
    }

    private func updateLayoutItemSize() {
        let inset = flowLayout.sectionInset
        let availableWidth = max(0, bounds.width - inset.left - inset.right)
        let columns = GridLayoutHelper.columnCount(
            for: availableWidth,
            zoomOffset: service.zoomOffset
        )
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

    private func restoreScrollOffset(_ offsetY: CGFloat) {
        guard let documentView = scrollView.documentView else {
            service.consumePendingBrowserScrollRestoreOffset()
            return
        }
        let maxOffsetY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        let clampedOffsetY = min(max(0, offsetY), maxOffsetY)
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clampedOffsetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateBrowserScrollMetrics()
        service.consumePendingBrowserScrollRestoreOffset()
    }

    private func updateBrowserScrollMetrics() {
        guard let documentView = scrollView.documentView else { return }
        service.updateBrowserScrollMetrics(
            offsetY: scrollView.contentView.bounds.origin.y,
            contentHeight: documentView.frame.height,
            viewportHeight: scrollView.contentView.bounds.height
        )
    }

    private func refreshFooterState(forceReload: Bool = false) {
        let previousState = footerState
        let newState = resolvedFooterState()
        let stateChanged = newState != footerState
        footerState = newState
        updateLayoutItemSize()
        guard stateChanged || forceReload else { return }
        let visibilityChanged = previousState == .hidden || newState == .hidden
        if stateChanged && visibilityChanged {
            scheduleFooterSnapshotRefresh()
            return
        }
        configureVisibleFooterIfNeeded()
    }

    private func resolvedFooterState() -> FooterState {
        if service.isLoadingMoreBrowserItems {
            return .loading
        }
        if service.hasMoreBrowserItems, !orderedIDs.isEmpty {
            return .ready
        }
        if !service.hasMoreBrowserItems, !orderedIDs.isEmpty {
            return .exhausted
        }
        return .hidden
    }

    private func configureVisibleFooterIfNeeded() {
        collectionView.visibleItems().compactMap { $0 as? AppKitSteamWorkshopBrowserFooterItem }.forEach {
            $0.configure(
                text: footerText(for: footerState),
                showsProgress: footerState == .loading
            )
        }
    }

    private func footerText(for state: FooterState) -> String {
        switch state {
        case .hidden:
            return ""
        case .ready:
            return Self.footerReadyMessage
        case .loading:
            return "正在加载更多项目…"
        case .exhausted:
            return Self.footerExhaustedMessage
        }
    }

    private func scheduleFooterSnapshotRefresh() {
        pendingFooterSnapshotRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.pendingFooterSnapshotRefresh else { return }
            guard !self.isApplyingSnapshot else {
                return
            }
            self.pendingFooterSnapshotRefresh = false
            self.applyItems(self.service.displayedBrowserItems)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        guard let id = dataSource.itemIdentifier(for: indexPath) else {
            return flowLayout.itemSize
        }
        if id == Self.footerItemID {
            let inset = flowLayout.sectionInset
            let width = max(120, bounds.width - inset.left - inset.right)
            let height: CGFloat = footerState == .exhausted ? 52 : 40
            return NSSize(width: floor(width), height: height)
        }
        return flowLayout.itemSize
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if id == Self.footerItemID {
            (item as? AppKitSteamWorkshopBrowserFooterItem)?.configure(
                text: footerText(for: footerState),
                showsProgress: footerState == .loading
            )
            return
        }

        guard let cell = item as? AppKitSteamWorkshopBrowserItem else { return }
        configureCell(cell, for: id)
        prioritizeVisibleItemsForHydration()
    }
}

extension AppKitSteamWorkshopBrowserContainerView: SteamWorkshopKeyboardDelegate {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            return handleEscapeKey()
        default:
            return false
        }
    }
}

private final class AppKitSteamWorkshopBrowserFooterItem: NSCollectionViewItem {
    override func loadView() {
        view = AppKitSteamWorkshopBrowserFooterView(frame: .zero)
    }

    func configure(text: String, showsProgress: Bool) {
        (view as? AppKitSteamWorkshopBrowserFooterView)?.configure(text: text, showsProgress: showsProgress)
    }
}

private final class AppKitSteamWorkshopBrowserFooterView: NSView {
    private let stackView = NSStackView()
    private let progressIndicator = NSProgressIndicator()
    private let statusIconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(text: String, showsProgress: Bool) {
        textField.stringValue = text
        progressIndicator.isHidden = !showsProgress
        statusIconView.isHidden = showsProgress
        if showsProgress {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        identifier = NSUserInterfaceItemIdentifier("SteamWorkshopBrowserFooterView")

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        statusIconView.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "没有更多内容")
        statusIconView.contentTintColor = .secondaryLabelColor

        textField.font = .systemFont(ofSize: 12)
        textField.textColor = .secondaryLabelColor
        textField.alignment = .center
        textField.lineBreakMode = .byTruncatingTail

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .gravityAreas
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(progressIndicator)
        stackView.addArrangedSubview(statusIconView)
        stackView.addArrangedSubview(textField)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24)
        ])
    }
}
