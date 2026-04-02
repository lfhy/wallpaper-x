//
//  AppKitSteamWorkshopBrowserItem.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.03
    private let cardView = AppearanceAwareContainerView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
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
    private var currentCardScale: CGFloat = 1.0

    private enum Layout {
        static let outerInset: CGFloat = 0
        static let contentInset: CGFloat = 8
        static let previewInset: CGFloat = 1
        static let previewTopInset: CGFloat = 1
        static let buttonHeight: CGFloat = 30
        static let buttonWidth: CGFloat = 92
        static let buttonGap: CGFloat = 8
        static let interSectionSpacing: CGFloat = 8
        static let textLineGap: CGFloat = 3
        static let textToButtonsGap: CGFloat = 8
        static let titleLineHeight: CGFloat = 20
        static let metaLineHeight: CGFloat = 14
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
        currentCardScale = 1.0
        cardView.layer?.transform = CATransform3DIdentity
        refreshThemeAwareAppearance()
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
        ensureCardAnchorCenteredIfNeeded()

        let contentWidth = max(0, cardView.bounds.width - Layout.contentInset * 2)
        let minButtonScale = max(0.72, min(1.0, contentWidth / 240))
        let buttonWidth = Layout.buttonWidth * minButtonScale
        let buttonHeight = Layout.buttonHeight * minButtonScale
        let buttonGap = Layout.buttonGap * minButtonScale

        let buttonsY = Layout.contentInset
        let buttonsTotalWidth = buttonWidth * 2 + buttonGap
        let buttonsStartX = max(Layout.contentInset, (cardView.bounds.width - buttonsTotalWidth) * 0.5)
        detailButton.frame = CGRect(x: buttonsStartX, y: buttonsY, width: buttonWidth, height: buttonHeight)
        actionButton.frame = CGRect(
            x: buttonsStartX + buttonWidth + buttonGap,
            y: buttonsY,
            width: buttonWidth,
            height: buttonHeight
        )

        let textBottom = buttonsY + buttonHeight + Layout.textToButtonsGap
        secondaryMetaLabel.frame = CGRect(x: Layout.contentInset, y: textBottom, width: contentWidth, height: Layout.metaLineHeight)
        metaLabel.frame = CGRect(
            x: Layout.contentInset,
            y: secondaryMetaLabel.frame.maxY + Layout.textLineGap,
            width: contentWidth,
            height: Layout.metaLineHeight
        )
        titleLabel.frame = CGRect(
            x: Layout.contentInset,
            y: metaLabel.frame.maxY + Layout.textLineGap,
            width: contentWidth,
            height: Layout.titleLineHeight
        )

        let previewY = titleLabel.frame.maxY + Layout.interSectionSpacing
        let previewHeight = max(0, cardView.bounds.height - Layout.previewInset - Layout.previewTopInset - previewY)
        previewContainer.frame = CGRect(
            x: Layout.previewInset,
            y: previewY,
            width: cardView.bounds.width - Layout.previewInset * 2,
            height: previewHeight
        )
        previewImageView.frame = previewContainer.bounds

        refreshThemeAwareAppearance()
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
        cardView.layer?.backgroundColor = NSColor.secondarySystemBackground.cgColor
        cardView.layer?.cornerRadius = 12
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0
        cardView.layer?.shadowRadius = 16
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
            self?.applyHoverStyle(animated: false)
        }
        view.addSubview(cardView)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 12
        previewContainer.layer?.masksToBounds = true
        cardView.addSubview(previewContainer)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewContainer.addSubview(previewImageView)

        configureLabel(titleLabel, font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        cardView.addSubview(titleLabel)

        configureLabel(metaLabel, font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        metaLabel.maximumNumberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail
        cardView.addSubview(metaLabel)

        configureLabel(secondaryMetaLabel, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        secondaryMetaLabel.maximumNumberOfLines = 1
        secondaryMetaLabel.lineBreakMode = .byTruncatingTail
        cardView.addSubview(secondaryMetaLabel)

        detailButton.bezelStyle = .rounded
        detailButton.target = self
        detailButton.action = #selector(handleOpen)
        cardView.addSubview(detailButton)

        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(handleAction)
        cardView.addSubview(actionButton)

        refreshThemeAwareAppearance()
    }

    private func refreshThemeAwareAppearance() {
        guard let layer = cardView.layer else { return }
        layer.backgroundColor = NSColor.secondarySystemBackground.cgColor
        let baseBorderColor: NSColor = isDarkAppearance
            ? .white.withAlphaComponent(0.10)
            : .separatorColor.withAlphaComponent(0.28)
        layer.borderColor = (isHovering
            ? NSColor.controlAccentColor.withAlphaComponent(isDarkAppearance ? 0.55 : 0.44)
            : baseBorderColor).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = isDarkAppearance
            ? (isHovering ? 0.18 : 0)
            : (isHovering ? 0.14 : 0.06)
        layer.shadowRadius = isHovering ? 12 : 8
        layer.shadowOffset = CGSize(width: 0, height: -1)
        titleLabel.textColor = .labelColor
        metaLabel.textColor = .secondaryLabelColor
        secondaryMetaLabel.textColor = .secondaryLabelColor
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
        let duration = isHovering
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let timing = isHovering
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming

        let baseBorderColor: NSColor = isDarkAppearance
            ? .white.withAlphaComponent(0.10)
            : .separatorColor.withAlphaComponent(0.32)
        let targetBorderColor = isHovering
            ? NSColor.controlAccentColor.withAlphaComponent(isDarkAppearance ? 0.55 : 0.48).cgColor
            : baseBorderColor.cgColor
        let targetShadowOpacity: Float = isDarkAppearance
            ? (isHovering ? 0.18 : 0)
            : (isHovering ? 0.16 : 0.08)
        let targetScale: CGFloat = isHovering ? Self.hoverScale : 1.0

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardView.layer?.borderColor = targetBorderColor
            cardView.layer?.shadowOpacity = targetShadowOpacity
            cardView.layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
            CATransaction.commit()
            currentCardScale = targetScale
            return
        }

        cardView.layer?.borderColor = targetBorderColor
        cardView.layer?.shadowOpacity = targetShadowOpacity
        applyCardScale(targetScale: targetScale, duration: duration, timing: timing)
    }

    private func applyCardScale(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = cardView.layer else { return }
        ensureCardAnchorCenteredIfNeeded()
        guard abs(currentCardScale - targetScale) > 0.0001 else { return }

        let fromScale = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? currentCardScale
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = fromScale
        animation.toValue = targetScale
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "steam.card.hover.scale")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
        currentCardScale = targetScale
    }

    private func ensureCardAnchorCenteredIfNeeded() {
        cardView.ensureLayerAnchorCentered()
    }

    private var isDarkAppearance: Bool { view.isDarkAppearance }

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
