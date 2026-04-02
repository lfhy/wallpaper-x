//
//  AppKitSteamWorkshopBrowserItem.swift
//  MyWallpaperX
//

import AppKit

final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.012
    private let cardView = NSView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let secondaryMetaLabel = NSTextField(labelWithString: "")
    private let detailButton = NSButton(title: "查看详情", target: nil, action: nil)
    private let actionButton = NSButton(title: "下载", target: nil, action: nil)

    private var imageTask: Task<Void, Never>?
    private var currentPreviewURL: URL?
    private var onOpen: (() -> Void)?
    private var onDownload: (() -> Void)?
    private var onCancelDownload: (() -> Void)?
    private var currentIsDownloading = false
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false

    private enum Layout {
        static let outerInset: CGFloat = 4
        static let contentInset: CGFloat = 10
        static let buttonHeight: CGFloat = 30
        static let buttonWidth: CGFloat = 92
    }

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        buildHierarchy()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentPreviewURL = nil
        previewImageView.image = nil
        onOpen = nil
        onDownload = nil
        onCancelDownload = nil
        currentIsDownloading = false
    }

    func configure(
        item: SteamWorkshopBrowserItem,
        isDownloading: Bool,
        isDownloaded: Bool,
        downloadProgressText: String?,
        onOpen: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onDownload = onDownload
        self.onCancelDownload = onCancelDownload
        self.currentIsDownloading = isDownloading

        titleLabel.stringValue = item.title
        metaLabel.stringValue = item.primaryMetaText
        secondaryMetaLabel.stringValue = localizedSecondaryMetaText(for: item)

        if isDownloading {
            actionButton.title = "取消下载"
            actionButton.isEnabled = true
            actionButton.bezelColor = NSColor.controlColor
        } else if isDownloaded {
            actionButton.title = "已下载"
            actionButton.isEnabled = false
            actionButton.bezelColor = NSColor.systemGreen
        } else {
            actionButton.title = "下载"
            actionButton.isEnabled = true
            actionButton.bezelColor = NSColor.controlAccentColor
        }

        loadPreview(from: item.previewImageURL)
        applyHoverStyle(animated: false)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let bounds = view.bounds
        cardView.frame = bounds.insetBy(dx: Layout.outerInset, dy: Layout.outerInset)
        let contentWidth = cardView.bounds.width - Layout.contentInset * 2
        let previewSide = contentWidth

        previewContainer.frame = CGRect(
            x: Layout.contentInset,
            y: cardView.bounds.height - Layout.contentInset - previewSide,
            width: contentWidth,
            height: previewSide
        )
        previewImageView.frame = previewContainer.bounds

        let textTop = previewContainer.frame.minY - 10
        titleLabel.frame = CGRect(x: Layout.contentInset, y: textTop - 38, width: contentWidth, height: 36)
        metaLabel.frame = CGRect(x: Layout.contentInset, y: titleLabel.frame.minY - 18, width: contentWidth, height: 15)
        secondaryMetaLabel.frame = CGRect(x: Layout.contentInset, y: metaLabel.frame.minY - 18, width: contentWidth, height: 15)

        let buttonsY = Layout.contentInset
        detailButton.frame = CGRect(x: Layout.contentInset, y: buttonsY, width: Layout.buttonWidth, height: Layout.buttonHeight)
        actionButton.frame = CGRect(x: cardView.bounds.width - Layout.contentInset - Layout.buttonWidth, y: buttonsY, width: Layout.buttonWidth, height: Layout.buttonHeight)
        refreshTrackingArea()
    }

    private func refreshTrackingArea() {
        if let trackingAreaRef {
            view.removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: view.bounds, options: options, owner: self, userInfo: nil)
        view.addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    private func buildHierarchy() {
        view.wantsLayer = true

        cardView.wantsLayer = true
        cardView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        cardView.layer?.cornerRadius = 16
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0
        cardView.layer?.shadowRadius = 16
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 14
        previewContainer.layer?.masksToBounds = true
        cardView.addSubview(previewContainer)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewContainer.addSubview(previewImageView)

        configureLabel(titleLabel, font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor)
        titleLabel.maximumNumberOfLines = 2
        cardView.addSubview(titleLabel)

        configureLabel(metaLabel, font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        cardView.addSubview(metaLabel)

        configureLabel(secondaryMetaLabel, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        secondaryMetaLabel.maximumNumberOfLines = 1
        cardView.addSubview(secondaryMetaLabel)

        detailButton.bezelStyle = .rounded
        detailButton.target = self
        detailButton.action = #selector(handleOpen)
        cardView.addSubview(detailButton)

        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(handleAction)
        cardView.addSubview(actionButton)
    }

    private func configureLabel(_ label: NSTextField, font: NSFont, color: NSColor) {
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
        applyHoverStyle(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        applyHoverStyle(animated: true)
    }

    private func loadPreview(from url: URL?) {
        guard currentPreviewURL != url else { return }
        currentPreviewURL = url
        previewImageView.image = nil
        imageTask?.cancel()

        guard let url else { return }
        imageTask = Task(priority: .userInitiated) { [weak self] in
            guard let self,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            await MainActor.run {
                guard self.currentPreviewURL == url else { return }
                self.previewImageView.image = image
            }
        }
    }

    private func localizedValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        switch value {
        case "Video": return "视频"
        case "Everyone": return "全年龄"
        case "Mature": return "成人"
        case "Unspecified": return "未标注"
        case "Wallpaper": return "壁纸"
        case "Scene": return "场景"
        case "Web": return "网页"
        case "Application": return "应用"
        case "Anime": return "动漫"
        case "Technology": return "科技"
        case "Landscape": return "风景"
        case "Space": return "太空"
        case "Sci-Fi": return "科幻"
        case "Fantasy": return "奇幻"
        case "Game": return "游戏"
        case "Nature": return "自然"
        default: return value
        }
    }

    private func localizedSecondaryMetaText(for item: SteamWorkshopBrowserItem) -> String {
        [
            localizedValue(item.workshopTypeText),
            localizedValue(item.ageRatingText),
            localizedValue(item.genreText)
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
    }

    private func applyHoverStyle(animated: Bool) {
        let changes = {
            self.cardView.layer?.borderColor = (
                self.isHovering
                    ? NSColor.white.withAlphaComponent(0.42).cgColor
                    : NSColor.white.withAlphaComponent(0.10).cgColor
            )
            self.cardView.layer?.shadowOpacity = self.isHovering ? 0.18 : 0
            self.cardView.layer?.transform = self.isHovering
                ? CATransform3DMakeScale(1.012, 1.012, 1)
                : CATransform3DIdentity
        }

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            changes()
            CATransaction.commit()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            changes()
        }
    }

    @objc private func handleOpen() {
        onOpen?()
    }

    @objc private func handleAction() {
        if currentIsDownloading {
            onCancelDownload?()
        } else {
            onDownload?()
        }
    }
}
