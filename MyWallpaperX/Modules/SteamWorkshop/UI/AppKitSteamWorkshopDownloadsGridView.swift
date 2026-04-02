//
//  AppKitSteamWorkshopDownloadsGridView.swift
//  MyWallpaperX
//

import AppKit
import SwiftUI
import Combine

struct AppKitSteamWorkshopDownloadsGridView: NSViewRepresentable {
    @ObservedObject var service: SteamWorkshopService
    let onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    let onReveal: (SteamWorkshopDownloadRecord) -> Void

    func makeNSView(context: Context) -> AppKitSteamWorkshopDownloadsContainerView {
        AppKitSteamWorkshopDownloadsContainerView(
            service: service,
            onSetAsWallpaper: onSetAsWallpaper,
            onReveal: onReveal
        )
    }

    func updateNSView(_ nsView: AppKitSteamWorkshopDownloadsContainerView, context: Context) {
        nsView.onSetAsWallpaper = onSetAsWallpaper
        nsView.onReveal = onReveal
    }
}

final class AppKitSteamWorkshopDownloadsContainerView: NSView, ModuleFocusable {
    private enum Section {
        case main
    }

    private let service: SteamWorkshopService
    var onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    var onReveal: (SteamWorkshopDownloadRecord) -> Void

    private var cancellables = Set<AnyCancellable>()
    private var orderedIDs: [String] = []
    private var recordsByID: [String: SteamWorkshopDownloadRecord] = [:]
    private var moduleActivationObserver: NSObjectProtocol?

    private let scrollView: NSScrollView = {
        let s = NSScrollView()
        s.drawsBackground = false
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var collectionView: NSCollectionView = {
        let cv = NSCollectionView()
        cv.isSelectable = false
        cv.backgroundColors = [.clear]
        cv.translatesAutoresizingMaskIntoConstraints = false
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
            let item = AppKitSteamWorkshopDownloadsItem(nibName: nil, bundle: nil)
            item.configure(
                record: record,
                onSetAsWallpaper: { [weak self] in self?.onSetAsWallpaper(record) },
                onReveal: { [weak self] in self?.onReveal(record) }
            )
            return item
        }
    }()

    init(
        service: SteamWorkshopService,
        onSetAsWallpaper: @escaping (SteamWorkshopDownloadRecord) -> Void,
        onReveal: @escaping (SteamWorkshopDownloadRecord) -> Void
    ) {
        self.service = service
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
            }
            .store(in: &cancellables)

        service.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLayoutItemSize()
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
