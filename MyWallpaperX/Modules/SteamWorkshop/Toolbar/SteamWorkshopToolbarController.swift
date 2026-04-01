//
//  SteamWorkshopToolbarController.swift
//  MyWallpaperX
//

import AppKit
import Combine

extension NSToolbarItem.Identifier {
    static let steamSource = NSToolbarItem.Identifier("ToolbarSteamSource")
    static let steamRefresh = NSToolbarItem.Identifier("ToolbarSteamRefresh")
    static let steamZoom = NSToolbarItem.Identifier("ToolbarSteamZoom")
    static let steamSearch = NSToolbarItem.Identifier("ToolbarSteamSearch")
    static let steamDownload = NSToolbarItem.Identifier("ToolbarSteamDownload")
    static let steamDownloadsTitle = NSToolbarItem.Identifier("ToolbarSteamDownloadsTitle")
    static let steamDownloadsReveal = NSToolbarItem.Identifier("ToolbarSteamDownloadsReveal")
    static let steamDownloadsSearch = NSToolbarItem.Identifier("ToolbarSteamDownloadsSearch")
}

final class SteamWorkshopToolbarController: NSObject, NSSearchFieldDelegate {
    private enum Title {
        static let browser = "Steam 创意工坊"
        static let downloads = "Steam 下载页"
    }

    weak var toolbar: NSToolbar?
    weak var window: NSWindow?
    var localModeIdentifiers: [NSToolbarItem.Identifier] = []
    var titleUpdateHandler: ((String) -> Void)?

    private(set) var isSteamWorkshopMode = false
    private var isDownloadsMode = false
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    let browserIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        NSToolbarItem.Identifier("ToolbarTitle"),
        .flexibleSpace,
        .steamDownload,
        .space,
        .steamRefresh,
        .space,
        .steamSource,
        .space,
        .steamZoom,
        .space,
        .steamSearch
    ]

    let downloadsIdentifiers: [NSToolbarItem.Identifier] = [
        .sidebarTrackingSeparator,
        .steamDownloadsTitle,
        .flexibleSpace,
        .steamDownloadsReveal,
        .space,
        .steamRefresh,
        .space,
        .steamZoom,
        .space,
        .steamDownloadsSearch
    ]

    init(toolbar: NSToolbar, window: NSWindow?) {
        self.toolbar = toolbar
        self.window = window
        super.init()
        installObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func installObservers() {
        let modeObserver = NotificationCenter.default.addObserver(
            forName: .steamWorkshopModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            let isDownloads = notification.userInfo?["isDownloads"] as? Bool ?? false
            self?.switchMode(enabled: enabled, isDownloads: isDownloads)
        }
        observers.append(modeObserver)

        SteamWorkshopService.shared.$zoomOffset
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureZoomItem()
            }
            .store(in: &cancellables)
    }

    private func switchMode(enabled: Bool, isDownloads: Bool) {
        guard enabled else {
            isSteamWorkshopMode = false
            isDownloadsMode = false
            return
        }
        isSteamWorkshopMode = true
        isDownloadsMode = isDownloads

        if isDownloads {
            configureDownloadsTitleItem()
            syncDownloadsSearchField()
        } else {
            titleUpdateHandler?(Title.browser)
            syncSourceControl()
            syncSearchField()
        }
        configureZoomItem()
    }

    func makeItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .steamSource: return sourceToolbarItem
        case .steamRefresh: return refreshToolbarItem
        case .steamZoom: return zoomToolbarItem
        case .steamSearch: return searchToolbarItem
        case .steamDownload: return downloadToolbarItem
        case .steamDownloadsTitle: return downloadsTitleItem
        case .steamDownloadsReveal: return downloadsRevealItem
        case .steamDownloadsSearch: return downloadsSearchItem
        default: return nil
        }
    }

    lazy var downloadsTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: Title.downloads)
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var downloadsTitleContainer: NSView = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 28))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(downloadsTitleLabel)
        NSLayoutConstraint.activate([
            downloadsTitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            downloadsTitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            downloadsTitleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 180),
            container.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }()

    lazy var downloadsTitleItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsTitle)
        item.label = "当前目录"
        item.paletteLabel = "当前目录"
        item.autovalidates = false
        item.isBordered = false
        item.view = downloadsTitleContainer
        return item
    }()

    lazy var downloadsRevealItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownloadsReveal)
        item.label = "打开目录"
        item.paletteLabel = "打开目录"
        item.toolTip = "在访达中打开 Steam 下载目录"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "打开目录")
        item.target = self
        item.action = #selector(handleRevealDownloads)
        return item
    }()

    lazy var downloadsSearchItem: NSSearchToolbarItem = {
        let item = NSSearchToolbarItem(itemIdentifier: .steamDownloadsSearch)
        item.searchField.delegate = self
        item.searchField.placeholderString = "搜索下载项"
        item.searchField.sendsSearchStringImmediately = true
        item.resignsFirstResponderWithCancel = true
        item.preferredWidthForSearchField = 180
        return item
    }()

    lazy var zoomControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "缩小") ?? NSImage(),
                NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "放大") ?? NSImage()
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(handleZoomAction(_:))
        )
        control.segmentStyle = .capsule
        control.setWidth(28, forSegment: 0)
        control.setWidth(28, forSegment: 1)
        return control
    }()

    lazy var zoomToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamZoom)
        item.label = "缩放"
        item.paletteLabel = "缩放"
        item.toolTip = "调整 Steam 条目卡片大小"
        item.autovalidates = false
        item.view = zoomControl
        return item
    }()

    lazy var sourceControl: NSSegmentedControl = {
        let labels = SteamWorkshopSource.allCases.map(\.displayName)
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(handleSourceAction(_:)))
        control.segmentStyle = .capsule
        for index in 0..<labels.count {
            control.setWidth(50, forSegment: index)
        }
        return control
    }()

    lazy var sourceToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamSource)
        item.label = "来源"
        item.paletteLabel = "来源"
        item.toolTip = "筛选 Steam 创意工坊来源"
        item.autovalidates = false
        item.view = sourceControl
        return item
    }()

    lazy var searchToolbarItem: NSSearchToolbarItem = {
        let item = NSSearchToolbarItem(itemIdentifier: .steamSearch)
        item.searchField.delegate = self
        item.searchField.placeholderString = "搜索 Steam 视频"
        item.searchField.sendsSearchStringImmediately = true
        item.resignsFirstResponderWithCancel = true
        item.preferredWidthForSearchField = 180
        return item
    }()

    lazy var refreshToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamRefresh)
        item.label = "刷新"
        item.paletteLabel = "刷新"
        item.toolTip = "刷新 Steam 创意工坊列表"
        item.autovalidates = false
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        item.target = self
        item.action = #selector(handleRefresh)
        return item
    }()

    lazy var downloadButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "下载当前项目")
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleDownloadCurrent)
        button.toolTip = "下载当前创意工坊项目"
        return button
    }()

    lazy var downloadToolbarItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: .steamDownload)
        item.label = "下载"
        item.paletteLabel = "下载当前项目"
        item.toolTip = "下载当前创意工坊项目"
        item.autovalidates = false
        item.view = downloadButton
        return item
    }()

    func focusSearch() {
        guard isSteamWorkshopMode else { return }
        if isDownloadsMode {
            window?.makeFirstResponder(downloadsSearchItem.searchField)
        } else {
            window?.makeFirstResponder(searchToolbarItem.searchField)
        }
    }

    func performZoom(delta: Int) {
        guard isSteamWorkshopMode else { return }
        let width = gridWidth()
        let availability = GridLayoutHelper.zoomAvailability(
            currentOffset: SteamWorkshopService.shared.zoomOffset,
            for: width,
            minCols: 2,
            maxCols: isDownloadsMode ? 4 : 5
        )
        let canZoom = delta > 0 ? availability.canZoomIn : availability.canZoomOut
        guard canZoom else { return }
        let segment = delta > 0 ? 0 : 1
        zoomControl.setSelected(true, forSegment: segment)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.zoomControl.setSelected(false, forSegment: segment)
        }
        SteamWorkshopService.shared.zoomOffset += delta
        configureZoomItem()
    }

    private func gridWidth() -> CGFloat {
        (window?.contentView?.bounds.width ?? 900) - 220
    }

    private func configureZoomItem() {
        let availability = GridLayoutHelper.zoomAvailability(
            currentOffset: SteamWorkshopService.shared.zoomOffset,
            for: gridWidth(),
            minCols: 2,
            maxCols: isDownloadsMode ? 4 : 5
        )
        zoomControl.setEnabled(availability.canZoomIn, forSegment: 0)
        zoomControl.setEnabled(availability.canZoomOut, forSegment: 1)
    }

    private func syncSourceControl() {
        let allSources = SteamWorkshopSource.allCases
        sourceControl.selectedSegment = allSources.firstIndex(of: SteamWorkshopService.shared.source) ?? 0
    }

    private func syncSearchField() {
        searchToolbarItem.searchField.stringValue = SteamWorkshopService.shared.browserQuery
    }

    private func syncDownloadsSearchField() {
        downloadsSearchItem.searchField.stringValue = SteamWorkshopService.shared.downloadsQuery
    }

    private func configureDownloadsTitleItem() {
        downloadsTitleLabel.stringValue = Title.downloads
        downloadsTitleItem.toolTip = Title.downloads
    }

    @objc private func handleSourceAction(_ sender: NSSegmentedControl) {
        let sources = SteamWorkshopSource.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < sources.count else { return }
        SteamWorkshopService.shared.source = sources[sender.selectedSegment]
    }

    @objc private func handleRefresh() {
        SteamWorkshopService.shared.refresh()
    }

    @objc private func handleRevealDownloads() {
        SteamWorkshopService.shared.revealDownloadsDirectory()
    }

    @objc private func handleDownloadCurrent() {
        SteamWorkshopService.shared.downloadCurrentItem()
    }

    @objc private func handleZoomAction(_ sender: NSSegmentedControl) {
        performZoom(delta: sender.selectedSegment == 0 ? 1 : -1)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        if field === downloadsSearchItem.searchField {
            SteamWorkshopService.shared.downloadsQuery = field.stringValue.trimmingCharacters(in: .whitespaces)
        } else {
            SteamWorkshopService.shared.browserQuery = field.stringValue.trimmingCharacters(in: .whitespaces)
        }
    }

    var allowedItemIdentifiers: [NSToolbarItem.Identifier] {
        [
            .steamSource,
            .steamRefresh,
            .steamZoom,
            .steamSearch,
            .steamDownload,
            .steamDownloadsTitle,
            .steamDownloadsReveal,
            .steamDownloadsSearch,
            .space,
            .flexibleSpace
        ]
    }
}
