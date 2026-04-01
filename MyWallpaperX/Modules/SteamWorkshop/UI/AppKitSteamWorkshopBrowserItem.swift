//
//  AppKitSteamWorkshopBrowserItem.swift
//  MyWallpaperX
//

import AppKit

final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    private let cardView = NSView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let secondaryMetaLabel = NSTextField(wrappingLabelWithString: "")
    private let authorLabel = NSTextField(labelWithString: "")
    private let tagLabel = NSTextField(wrappingLabelWithString: "")
    private let adultBadge = NSTextField(labelWithString: "成人内容")
    private let previewKindBadge = NSTextField(labelWithString: "")
    private let progressBadge = NSTextField(labelWithString: "")
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
        authorLabel.stringValue = item.author
        tagLabel.stringValue = [
            localizedValue(item.workshopTypeText),
            localizedValue(item.ageRatingText),
            localizedValue(item.genreText),
            localizedValue(item.categoryText)
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "  ·  ")

        adultBadge.isHidden = !item.hasAdultContent
        previewKindBadge.stringValue = previewBadgeText(for: item.previewAssetKind)
        progressBadge.stringValue = downloadProgressText ?? "下载中"
        progressBadge.isHidden = !isDownloading

        actionButton.title = isDownloading ? "取消下载" : "下载"
        actionButton.bezelColor = isDownloading ? NSColor.controlColor : NSColor.controlAccentColor

        loadPreview(from: item.previewImageURL)
        applyHoverStyle(animated: false)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let bounds = view.bounds
        cardView.frame = bounds
        let contentWidth = bounds.width - 24
        let previewHeight = floor((bounds.width - 24) / (16.0 / 9.0))

        previewContainer.frame = CGRect(x: 12, y: bounds.height - 12 - previewHeight, width: contentWidth, height: previewHeight)
        previewImageView.frame = previewContainer.bounds

        let badgeHeight: CGFloat = 22
        let previewBadgeWidth = max(60, min(92, previewKindBadge.intrinsicContentSize.width + 18))
        previewKindBadge.frame = CGRect(x: 10, y: 10, width: previewBadgeWidth, height: badgeHeight)

        if !adultBadge.isHidden {
            let adultWidth = max(66, min(96, adultBadge.intrinsicContentSize.width + 18))
            adultBadge.frame = CGRect(x: previewContainer.bounds.width - adultWidth - 10, y: previewContainer.bounds.height - badgeHeight - 10, width: adultWidth, height: badgeHeight)
        }

        if !progressBadge.isHidden {
            progressBadge.frame = CGRect(x: 10, y: 10, width: min(contentWidth - 20, 160), height: badgeHeight)
        }

        let textTop = previewContainer.frame.minY - 12
        titleLabel.frame = CGRect(x: 12, y: textTop - 40, width: contentWidth, height: 38)
        metaLabel.frame = CGRect(x: 12, y: titleLabel.frame.minY - 19, width: contentWidth, height: 16)
        secondaryMetaLabel.frame = CGRect(x: 12, y: metaLabel.frame.minY - 30, width: contentWidth, height: 28)
        authorLabel.frame = CGRect(x: 12, y: secondaryMetaLabel.frame.minY - 18, width: contentWidth, height: 16)
        tagLabel.frame = CGRect(x: 12, y: authorLabel.frame.minY - 28, width: contentWidth, height: 24)

        detailButton.frame = CGRect(x: 12, y: 12, width: 86, height: 30)
        actionButton.frame = CGRect(x: detailButton.frame.maxX + 8, y: 12, width: 86, height: 30)
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
        cardView.layer?.cornerRadius = 18
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0
        cardView.layer?.shadowRadius = 20
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 16
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cardView.addSubview(previewContainer)

        previewImageView.imageScaling = .scaleAxesIndependently
        previewImageView.imageAlignment = .alignCenter
        previewContainer.addSubview(previewImageView)

        configureLabel(titleLabel, font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor)
        titleLabel.maximumNumberOfLines = 2
        cardView.addSubview(titleLabel)

        configureLabel(metaLabel, font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        cardView.addSubview(metaLabel)

        configureLabel(secondaryMetaLabel, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        secondaryMetaLabel.maximumNumberOfLines = 2
        cardView.addSubview(secondaryMetaLabel)

        configureLabel(authorLabel, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        cardView.addSubview(authorLabel)

        configureLabel(tagLabel, font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
        tagLabel.maximumNumberOfLines = 2
        cardView.addSubview(tagLabel)

        configureBadge(adultBadge, background: NSColor.systemOrange.withAlphaComponent(0.96))
        previewContainer.addSubview(adultBadge)

        configureBadge(previewKindBadge, background: NSColor.black.withAlphaComponent(0.62))
        previewContainer.addSubview(previewKindBadge)

        configureBadge(progressBadge, background: NSColor.black.withAlphaComponent(0.62))
        previewContainer.addSubview(progressBadge)

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

    private func configureBadge(_ label: NSTextField, background: NSColor) {
        label.alignment = .center
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.backgroundColor = background.cgColor
        label.layer?.cornerRadius = 11
        label.lineBreakMode = .byTruncatingTail
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

    private func previewBadgeText(for kind: SteamWorkshopPreviewAssetKind) -> String {
        switch kind {
        case .video: return "视频预览"
        case .animatedImage: return "动态预览"
        case .stillImage: return "静态预览"
        case .unknown: return "预览"
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
            localizedValue(item.genreText),
            item.updatedText
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
    }

    private func applyHoverStyle(animated: Bool) {
        let changes = {
            self.cardView.layer?.borderColor = (
                self.isHovering
                    ? NSColor.controlAccentColor.withAlphaComponent(0.38).cgColor
                    : NSColor.separatorColor.withAlphaComponent(0.25).cgColor
            )
            self.cardView.layer?.shadowOpacity = self.isHovering ? 0.14 : 0
            self.cardView.layer?.transform = self.isHovering
                ? CATransform3DMakeScale(1.01, 1.01, 1)
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
