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
    private var moduleActivationObserver: NSObjectProtocol?

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
        cv.backgroundColors = [.clear]
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.keyboardDelegate = self
        cv.cardPressStateHandler = { [weak self] indexPath, pressed in
            guard let self,
                  let item = self.collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { return }
            item.applyPressedState(pressed)
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

        service.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLayoutItemSize()
            }
            .store(in: &cancellables)

        service.$activeDownloadItemID
            .combineLatest(service.$activeDownloadProgressFraction, service.$activeDownloadProgressText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
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
            item: displayItem,
            downloadRecord: record,
            downloadProgressFraction: record.id == service.activeDownloadItemID ? service.activeDownloadProgressFraction : nil,
            downloadProgressText: record.status == .downloading ? record.sizeText : nil,
            isDownloading: record.status == .downloading,
            isDownloaded: record.status == .ready && record.isPlayable,
            isKeyboardFocused: record.id == keyboardFocusedID,
            onOpen: { [weak self] in
                self?.onOpen(displayItem)
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
                case .downloading:
                    self.service.cancelActiveDownload()
                }
            },
            onSetAsWallpaper: { [weak self] in self?.onSetAsWallpaper(record) },
            onCancelDownload: { [weak self] in self?.service.cancelActiveDownload() }
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
        case .downloading:
            service.cancelActiveDownload()
        }
        return true
    }

    private func scrollToItem(_ id: String) {
        guard let indexPath = indexPathForItemID(id) else { return }
        collectionView.scrollToItems(at: Set([indexPath]), scrollPosition: .centeredVertically)
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
        var indexPaths = Set<IndexPath>()
        if let prev = previous, let path = indexPathForItemID(prev) {
            indexPaths.insert(path)
        }
        if let nextID = next, let path = indexPathForItemID(nextID) {
            indexPaths.insert(path)
        }
        guard !indexPaths.isEmpty else { return }
        collectionView.reloadItems(at: indexPaths)
    }
}

extension AppKitSteamWorkshopDownloadsContainerView: SteamWorkshopKeyboardDelegate {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 126:
            return moveFocus(delta: -1)
        case 124, 125:
            return moveFocus(delta: 1)
        case 36, 76:
            return handleReturnKey()
        default:
            break
        }
        return false
    }
}
