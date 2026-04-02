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
    let onDownload: (SteamWorkshopBrowserItem) -> Void
    let onCancelDownload: () -> Void

    func makeNSView(context: Context) -> AppKitSteamWorkshopBrowserContainerView {
        AppKitSteamWorkshopBrowserContainerView(
            service: service,
            onOpen: onOpen,
            onDownload: onDownload,
            onCancelDownload: onCancelDownload
        )
    }

    func updateNSView(_ nsView: AppKitSteamWorkshopBrowserContainerView, context: Context) {
        nsView.onOpen = onOpen
        nsView.onDownload = onDownload
        nsView.onCancelDownload = onCancelDownload
    }
}

final class AppKitSteamWorkshopBrowserContainerView: NSView, ModuleFocusable {
    private enum Section {
        case main
    }

    private let service: SteamWorkshopService
    var onOpen: (SteamWorkshopBrowserItem) -> Void
    var onDownload: (SteamWorkshopBrowserItem) -> Void
    var onCancelDownload: () -> Void

    private var cancellables = Set<AnyCancellable>()
    private var itemsByID: [String: SteamWorkshopBrowserItem] = [:]
    private var orderedIDs: [String] = []

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var collectionView: NSCollectionView = {
        let collectionView = NSCollectionView()
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.translatesAutoresizingMaskIntoConstraints = false
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
        NSCollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { [weak self] _, indexPath, id in
            guard let self,
                  let item = self.itemsByID[id] else { return nil }
            let cell = AppKitSteamWorkshopBrowserItem(nibName: nil, bundle: nil)
            cell.configure(
                item: item,
                isDownloading: self.service.isDownloading(itemID: id),
                isDownloaded: self.service.isDownloaded(itemID: id),
                downloadProgressText: self.service.downloadProgressLabel(for: id),
                onOpen: { [weak self] in self?.onOpen(item) },
                onDownload: { [weak self] in self?.onDownload(item) },
                onCancelDownload: { [weak self] in self?.onCancelDownload() }
            )
            return cell
        }
    }()

    init(
        service: SteamWorkshopService,
        onOpen: @escaping (SteamWorkshopBrowserItem) -> Void,
        onDownload: @escaping (SteamWorkshopBrowserItem) -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        self.service = service
        self.onOpen = onOpen
        self.onDownload = onDownload
        self.onCancelDownload = onCancelDownload
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
        scrollView.contentView.postsBoundsChangedNotifications = true

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        service.$browserItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyItems($0) }
            .store(in: &cancellables)

        service.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLayoutItemSize() }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            service.$activeDownloadItemID,
            service.$activeDownloadProgressText,
            service.$activeDownloadProgressFraction
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.reloadVisibleItems()
        }
        .store(in: &cancellables)

        service.$downloads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.checkLoadMore()
        }
        .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let module = notification.userInfo?["module"] as? String,
                  module == ModuleIdentifier.steamWorkshop.rawValue else { return }
            self?.requestFocus()
        }

        applyItems(service.browserItems)
    }

    private func applyItems(_ items: [SteamWorkshopBrowserItem]) {
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        orderedIDs = items.map(\.id)

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(orderedIDs, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func reloadVisibleItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard indexPath.item < orderedIDs.count,
                  let cell = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { continue }
            let id = orderedIDs[indexPath.item]
            guard let item = itemsByID[id] else { continue }
            cell.configure(
                item: item,
                isDownloading: service.isDownloading(itemID: id),
                isDownloaded: service.isDownloaded(itemID: id),
                downloadProgressText: service.downloadProgressLabel(for: id),
                onOpen: { [weak self] in self?.onOpen(item) },
                onDownload: { [weak self] in self?.onDownload(item) },
                onCancelDownload: { [weak self] in self?.onCancelDownload() }
            )
        }
    }

    private func checkLoadMore() {
        guard service.hasMoreBrowserItems, !service.isLoadingMoreBrowserItems else { return }
        guard let documentView = scrollView.documentView else { return }
        let contentHeight = documentView.frame.height
        let viewportHeight = scrollView.contentView.bounds.height
        let offsetY = scrollView.contentView.bounds.origin.y
        if contentHeight - offsetY - viewportHeight < 180 {
            service.loadMoreBrowserItemsIfNeeded()
        }
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
        flowLayout.minimumInteritemSpacing = spacing
        flowLayout.minimumLineSpacing = spacing
        let totalSpacing = CGFloat(max(0, columns - 1)) * spacing
        let cardWidth = max(100, (availableWidth - totalSpacing) / CGFloat(columns))
        let previewHeight = floor(cardWidth - 28)
        let cardHeight = previewHeight + 132
        let newSize = NSSize(width: floor(cardWidth), height: floor(cardHeight))
        guard flowLayout.itemSize != newSize else { return }
        flowLayout.itemSize = newSize
        collectionView.collectionViewLayout?.invalidateLayout()
    }
}
