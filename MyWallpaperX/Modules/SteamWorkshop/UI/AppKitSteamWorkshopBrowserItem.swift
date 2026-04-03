//
//  AppKitSteamWorkshopBrowserItem.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

private final class SteamWorkshopCardButton: NSButton {
    var normalBackgroundColor: NSColor = .controlColor {
        didSet { updateAppearance() }
    }
    var pressedBackgroundColor: NSColor = .controlAccentColor.withAlphaComponent(0.78)
    var disabledBackgroundColor: NSColor = .disabledControlTextColor.withAlphaComponent(0.16)
    var cornerRadius: CGFloat = 10 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    private var isPressing = false {
        didSet { updateAppearance() }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }
        isPressing = true
        super.mouseDown(with: event)
        isPressing = false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        contentTintColor = .white
        font = .systemFont(ofSize: 13, weight: .semibold)
        focusRingType = .none
        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundColor: NSColor
        if !isEnabled {
            backgroundColor = disabledBackgroundColor
        } else if isPressing {
            backgroundColor = pressedBackgroundColor
        } else {
            backgroundColor = normalBackgroundColor
        }
        layer?.backgroundColor = backgroundColor.cgColor
        alphaValue = isEnabled ? 1.0 : 0.72
    }
}

private final class SteamWorkshopCardTextLineView: NSView {
    let textLayer = CATextLayer()
    var text: String = "" {
        didSet {
            textLayer.string = text
            needsLayout = true
        }
    }
    var font: NSFont = .systemFont(ofSize: 14, weight: .regular) {
        didSet {
            updateAppearance()
            needsLayout = true
        }
    }
    var textColor: NSColor = .labelColor {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        textLayer.alignmentMode = .center
        textLayer.isWrapped = false
        textLayer.truncationMode = .none
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "contents": NSNull(),
            "fontSize": NSNull(),
            "foregroundColor": NSNull()
        ]
        layer?.addSublayer(textLayer)
        updateAppearance()
    }

    override func layout() {
        super.layout()
        let textHeight = ceil(font.pointSize + 4)
        textLayer.frame = CGRect(
            x: 0,
            y: floor((bounds.height - textHeight) * 0.5),
            width: bounds.width,
            height: textHeight
        )
    }

    private func updateAppearance() {
        textLayer.font = font
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = textColor.cgColor
    }

}

final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.02
    private static let downloadedButtonGreen = NSColor.systemGreen.blended(withFraction: 0.34, of: .windowBackgroundColor) ?? .systemGreen
    private let cardView = AppearanceAwareContainerView()
    private let previewContainer = NSView()
    private let textContainer = NSView()
    private let buttonsContainer = NSView()
    private let previewImageView = NSImageView()
    private let titleLabel = SteamWorkshopCardTextLineView()
    private let metaLabel = SteamWorkshopCardTextLineView()
    private let secondaryMetaLabel = SteamWorkshopCardTextLineView()
    private let detailButton = SteamWorkshopCardButton(title: "详情", target: nil, action: nil)
    private let actionButton = SteamWorkshopCardButton(title: "下载", target: nil, action: nil)

    private var imageTask: Task<Void, Never>?
    private var currentPreviewURL: URL?
    private var currentTitleText = ""
    private var onOpen: (() -> Void)?
    private var onDownload: (() -> Void)?
    private var onSetAsWallpaper: (() -> Void)?
    private var onCancelDownload: (() -> Void)?
    private var currentIsDownloading = false
    private var currentSecondaryMetaColor: NSColor = .secondaryLabelColor
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private var currentCardScale: CGFloat = 1.0
    private var keyboardFocused = false

    private enum Layout {
        static let cardCornerRadius: CGFloat = 14
        static let referenceCardWidth: CGFloat = 250
        static let referenceCardHeight: CGFloat = 354
        static let outerInset: CGFloat = 0
        static let contentInset: CGFloat = 12
        static let buttonBottomInset: CGFloat = 12
        static let previewInset: CGFloat = 0
        static let previewTopInset: CGFloat = 0
        static let buttonHeight: CGFloat = 28
        static let buttonWidth: CGFloat = 88
        static let buttonGap: CGFloat = 6
        static let interSectionSpacing: CGFloat = 6
        static let textLineGap: CGFloat = 2
        static let textToButtonsGap: CGFloat = 6
        static let titleLineHeight: CGFloat = 18
        static let metaLineHeight: CGFloat = 14
    }

    private struct Metrics {
        let scale: CGFloat
        let contentInset: CGFloat
        let buttonBottomInset: CGFloat
        let buttonWidth: CGFloat
        let buttonHeight: CGFloat
        let buttonGap: CGFloat
        let interSectionSpacing: CGFloat
        let textLineGap: CGFloat
        let textToButtonsGap: CGFloat
        let titleLineHeight: CGFloat
        let metaLineHeight: CGFloat
        let titleFont: NSFont
        let metaFont: NSFont
        let secondaryMetaFont: NSFont
        let buttonFont: NSFont
        let buttonCornerRadius: CGFloat
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
        currentTitleText = ""
        titleLabel.text = ""
        metaLabel.text = ""
        secondaryMetaLabel.text = ""
        previewImageView.image = nil
        onOpen = nil
        onDownload = nil
        onSetAsWallpaper = nil
        onCancelDownload = nil
        currentIsDownloading = false
        currentSecondaryMetaColor = .secondaryLabelColor
        isHovering = false
        currentCardScale = 1.0
        keyboardFocused = false
        cardView.layer?.transform = CATransform3DIdentity
        textContainer.frame = .zero
        buttonsContainer.frame = .zero
        refreshThemeAwareAppearance()
    }

    func configure(
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        downloadProgressText: String?,
        isDownloading: Bool,
        isDownloaded: Bool,
        isKeyboardFocused: Bool,
        onOpen: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        self.currentIsDownloading = isDownloading

        currentTitleText = item.title
        metaLabel.text = item.primaryMetaText
        let baseSecondaryMeta = localizedSecondaryMetaText(for: item)
        secondaryMetaLabel.text = secondaryStatusText(
            baseText: baseSecondaryMeta,
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            downloadProgressText: downloadProgressText
        )
        currentSecondaryMetaColor = secondaryMetaColor(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )

        if isDownloading {
            actionButton.title = "取消下载"
            actionButton.isEnabled = true
            actionButton.normalBackgroundColor = NSColor.controlColor
            actionButton.pressedBackgroundColor = NSColor.controlColor.blended(withFraction: 0.18, of: .black) ?? NSColor.controlColor
        } else if isDownloaded {
            actionButton.title = "设为壁纸"
            actionButton.isEnabled = true
            actionButton.normalBackgroundColor = Self.downloadedButtonGreen
            actionButton.pressedBackgroundColor = Self.downloadedButtonGreen.blended(withFraction: 0.18, of: .black) ?? Self.downloadedButtonGreen
        } else if downloadRecord?.failureMessage != nil {
            actionButton.title = "重试下载"
            actionButton.isEnabled = true
            actionButton.normalBackgroundColor = NSColor.systemRed
            actionButton.pressedBackgroundColor = NSColor.systemRed.blended(withFraction: 0.18, of: .black) ?? NSColor.systemRed
        } else {
            actionButton.title = "下载"
            actionButton.isEnabled = true
            actionButton.normalBackgroundColor = NSColor.controlAccentColor
            actionButton.pressedBackgroundColor = NSColor.controlAccentColor.blended(withFraction: 0.18, of: .black) ?? NSColor.controlAccentColor
        }

        detailButton.setAccessibilityLabel("查看详情：\(item.title)")
        var actionHint = "执行 \(actionButton.title) 操作"
        if actionButton.title.contains("下载中") {
            actionHint = "当前下载正在执行"
        } else if actionButton.title.contains("取消") {
            actionHint = "取消 steamcmd 正在进行的下载"
        } else if actionButton.title.contains("设为壁纸") {
            actionHint = "将下载完成的视频设为桌面壁纸"
        } else if actionButton.title.contains("重试") {
            actionHint = "重新触发该创意工坊项目的下载"
        }
        actionButton.setAccessibilityLabel("\(actionButton.title)：\(item.title)")
        actionButton.setAccessibilityHelp(actionHint)

        loadPreview(from: item.previewImageURL)
        applyHoverStyle(animated: false)
        setKeyboardFocus(isKeyboardFocused)
    }

    func configureMetadataOnly(
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        downloadProgressText: String?,
        isDownloading: Bool,
        isDownloaded: Bool,
        isKeyboardFocused: Bool,
        onOpen: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        currentTitleText = item.title
        metaLabel.text = item.primaryMetaText
        let baseSecondaryMeta = localizedSecondaryMetaText(for: item)
        secondaryMetaLabel.text = secondaryStatusText(
            baseText: baseSecondaryMeta,
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            downloadProgressText: downloadProgressText
        )
        currentSecondaryMetaColor = secondaryMetaColor(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )
        refreshThemeAwareAppearance()
        setKeyboardFocus(isKeyboardFocused)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let bounds = view.bounds
        cardView.frame = bounds.insetBy(dx: Layout.outerInset, dy: Layout.outerInset)
        ensureCardAnchorCenteredIfNeeded()

        let metrics = metrics(for: cardView.bounds.size)
        applyMetrics(metrics)

        let centeredTextInset = max(12, round(metrics.contentInset * 1.2))
        let contentWidth = max(0, cardView.bounds.width - centeredTextInset * 2)
        let buttonWidth = metrics.buttonWidth
        let buttonHeight = metrics.buttonHeight
        let buttonGap = metrics.buttonGap

        let buttonsY = metrics.buttonBottomInset
        let buttonsTotalWidth = buttonWidth * 2 + buttonGap
        let buttonsContainerWidth = max(buttonsTotalWidth, contentWidth)
        let buttonsContainerX = max(0, (cardView.bounds.width - buttonsContainerWidth) * 0.5)
        buttonsContainer.frame = CGRect(x: buttonsContainerX, y: buttonsY, width: buttonsContainerWidth, height: buttonHeight)
        let buttonsStartX = max(0, (buttonsContainerWidth - buttonsTotalWidth) * 0.5)
        detailButton.frame = CGRect(x: buttonsStartX, y: 0, width: buttonWidth, height: buttonHeight)
        actionButton.frame = CGRect(
            x: buttonsStartX + buttonWidth + buttonGap,
            y: 0,
            width: buttonWidth,
            height: buttonHeight
        )

        let previewSide = cardView.bounds.width
        let previewY = max(0, cardView.bounds.height - previewSide)
        let previewOverlap: CGFloat = 1
        previewContainer.frame = CGRect(
            x: Layout.previewInset - previewOverlap,
            y: previewY - previewOverlap,
            width: cardView.bounds.width - Layout.previewInset * 2 + previewOverlap * 2,
            height: previewSide + previewOverlap
        )

        let textBottom = buttonsY + buttonHeight + metrics.textToButtonsGap
        let textTop = max(textBottom, previewY - metrics.interSectionSpacing)
        let textContainerHeight = max(
            metrics.metaLineHeight * 2 + metrics.textLineGap * 2 + metrics.titleLineHeight,
            textTop - textBottom
        )
        textContainer.frame = CGRect(
            x: centeredTextInset,
            y: textBottom,
            width: contentWidth,
            height: textContainerHeight
        )
        secondaryMetaLabel.frame = CGRect(x: 0, y: 0, width: contentWidth, height: metrics.metaLineHeight)
        metaLabel.frame = CGRect(
            x: 0,
            y: secondaryMetaLabel.frame.maxY + metrics.textLineGap,
            width: contentWidth,
            height: metrics.metaLineHeight
        )
        titleLabel.frame = CGRect(
            x: 0,
            y: min(textContainerHeight - metrics.titleLineHeight, metaLabel.frame.maxY + metrics.textLineGap),
            width: contentWidth,
            height: metrics.titleLineHeight
        )
        titleLabel.text = truncatedText(currentTitleText, maxWidth: contentWidth, font: metrics.titleFont)
        updatePreviewImageFrame()

        refreshThemeAwareAppearance()
        refreshTrackingArea()
    }

    private func metrics(for cardSize: CGSize) -> Metrics {
        let widthScale = cardSize.width / Layout.referenceCardWidth
        let heightScale = cardSize.height / Layout.referenceCardHeight
        let scale = max(0.56, min(1.28, min(widthScale, heightScale)))
        return Metrics(
            scale: scale,
            contentInset: round(Layout.contentInset * scale),
            buttonBottomInset: round(Layout.buttonBottomInset * scale),
            buttonWidth: round(Layout.buttonWidth * scale),
            buttonHeight: round(Layout.buttonHeight * scale),
            buttonGap: round(Layout.buttonGap * scale),
            interSectionSpacing: round(Layout.interSectionSpacing * scale),
            textLineGap: round(Layout.textLineGap * scale),
            textToButtonsGap: round(Layout.textToButtonsGap * scale),
            titleLineHeight: round(Layout.titleLineHeight * scale),
            metaLineHeight: round(Layout.metaLineHeight * scale),
            titleFont: .systemFont(ofSize: 13.5 * scale, weight: .semibold),
            metaFont: .monospacedSystemFont(ofSize: 10.5 * scale, weight: .medium),
            secondaryMetaFont: .systemFont(ofSize: 10.5 * scale, weight: .medium),
            buttonFont: .systemFont(ofSize: 12 * scale, weight: .medium),
            buttonCornerRadius: max(9, min(14, 11 * scale))
        )
    }

    private func applyMetrics(_ metrics: Metrics) {
        titleLabel.font = metrics.titleFont
        metaLabel.font = metrics.metaFont
        secondaryMetaLabel.font = metrics.secondaryMetaFont
        detailButton.font = metrics.buttonFont
        actionButton.font = metrics.buttonFont
        detailButton.cornerRadius = metrics.buttonCornerRadius
        actionButton.cornerRadius = metrics.buttonCornerRadius
    }

    private func truncatedText(_ text: String, maxWidth: CGFloat, font: NSFont) -> String {
        guard !text.isEmpty, maxWidth > 0 else { return text }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attributes).width <= maxWidth {
            return text
        }

        let ellipsis = "..."
        let ellipsisWidth = (ellipsis as NSString).size(withAttributes: attributes).width
        guard ellipsisWidth < maxWidth else { return ellipsis }

        var scalars = Array(text)
        while !scalars.isEmpty {
            scalars.removeLast()
            let candidate = String(scalars) + ellipsis
            if (candidate as NSString).size(withAttributes: attributes).width <= maxWidth {
                return candidate
            }
        }
        return ellipsis
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
        cardView.canDrawSubviewsIntoLayer = true
        cardView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.84).cgColor
        cardView.layer?.cornerRadius = Layout.cardCornerRadius
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.16).cgColor
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0
        cardView.layer?.shadowRadius = 12
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
            self?.applyHoverStyle(animated: false)
        }
        view.addSubview(cardView)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = Layout.cardCornerRadius
        previewContainer.layer?.masksToBounds = true
        cardView.addSubview(previewContainer)

        textContainer.wantsLayer = true
        textContainer.layer?.backgroundColor = NSColor.clear.cgColor
        textContainer.layer?.shouldRasterize = true
        textContainer.layer?.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2
        cardView.addSubview(textContainer)

        buttonsContainer.wantsLayer = true
        buttonsContainer.layer?.backgroundColor = NSColor.clear.cgColor
        buttonsContainer.layer?.shouldRasterize = true
        buttonsContainer.layer?.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2
        cardView.addSubview(buttonsContainer)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewContainer.addSubview(previewImageView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        textContainer.addSubview(titleLabel)

        metaLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        metaLabel.textColor = .secondaryLabelColor
        textContainer.addSubview(metaLabel)

        secondaryMetaLabel.font = .systemFont(ofSize: 11)
        secondaryMetaLabel.textColor = .secondaryLabelColor
        textContainer.addSubview(secondaryMetaLabel)

        detailButton.normalBackgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72)
        detailButton.pressedBackgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        detailButton.target = self
        detailButton.action = #selector(handleOpen)
        buttonsContainer.addSubview(detailButton)

        actionButton.normalBackgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.92)
        actionButton.pressedBackgroundColor = NSColor.controlAccentColor.blended(withFraction: 0.18, of: .black) ?? NSColor.controlAccentColor
        actionButton.target = self
        actionButton.action = #selector(handleAction)
        buttonsContainer.addSubview(actionButton)

        refreshThemeAwareAppearance()
    }

    private func refreshThemeAwareAppearance() {
        guard let layer = cardView.layer else { return }
        layer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.84).cgColor
        let borderColor: NSColor
        if keyboardFocused {
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.54)
        } else if isHovering {
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.24)
        } else {
            borderColor = NSColor.separatorColor.withAlphaComponent(0.16)
        }
        layer.borderColor = borderColor.cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = keyboardFocused ? 0.14 : (isHovering ? 0.10 : 0.03)
        layer.shadowRadius = keyboardFocused ? 10 : (isHovering ? 8 : 5)
        layer.shadowOffset = CGSize(width: 0, height: -2)
        previewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.88).cgColor
        titleLabel.textColor = .labelColor
        metaLabel.textColor = .secondaryLabelColor
        secondaryMetaLabel.textColor = currentSecondaryMetaColor
    }

    func setKeyboardFocus(_ focused: Bool) {
        guard keyboardFocused != focused else { return }
        keyboardFocused = focused
        refreshThemeAwareAppearance()
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
        previewImageView.animates = true
        imageTask?.cancel()

        guard let url else {
            return
        }
        let cacheKey = steamWorkshopPreviewCacheKey(for: url)
        if let cached = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey) {
            previewImageView.image = cached
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        updatePreviewImageFrame()
        SteamWorkshopPreviewImageCache.shared.loadImageData(forKey: cacheKey, loader: {
            return try? Data(contentsOf: url)
        }) { [weak self] image in
            guard let self else { return }
            guard self.currentPreviewURL == url else { return }
            self.previewImageView.animates = true
            self.previewImageView.image = image
            self.updatePreviewImageFrame()
        }
    }

    private func updatePreviewImageFrame() {
        let containerBounds = previewContainer.bounds
        guard containerBounds.width > 0, containerBounds.height > 0 else {
            previewImageView.frame = .zero
            return
        }
        guard let image = previewImageView.image, image.size.width > 0, image.size.height > 0 else {
            previewImageView.frame = containerBounds
            return
        }

        let widthScale = containerBounds.width / image.size.width
        let heightScale = containerBounds.height / image.size.height
        let fillScale = max(widthScale, heightScale)
        let fittedWidth = image.size.width * fillScale
        let fittedHeight = image.size.height * fillScale
        previewImageView.frame = CGRect(
            x: floor((containerBounds.width - fittedWidth) * 0.5),
            y: floor((containerBounds.height - fittedHeight) * 0.5),
            width: ceil(fittedWidth),
            height: ceil(fittedHeight)
        )
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

    private func secondaryStatusText(
        baseText: String,
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool,
        downloadProgressText: String?
    ) -> String {
        if isDownloading {
            if let downloadProgressText, !downloadProgressText.isEmpty {
                return downloadProgressText
            }
            return "下载中"
        }
        if downloadRecord?.failureMessage != nil {
            return "下载失败，可重试"
        }
        if isDownloaded {
            return baseText
        }
        return baseText
    }

    private func secondaryMetaColor(
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool
    ) -> NSColor {
        if isDownloading {
            return .controlAccentColor
        }
        if downloadRecord?.failureMessage != nil {
            return .systemRed
        }
        if isDownloaded {
            return NSColor.systemGreen.blended(withFraction: 0.26, of: .labelColor) ?? .systemGreen
        }
        return .secondaryLabelColor
    }

    private func applyHoverStyle(animated: Bool) {
        let duration = isHovering
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let timing = isHovering
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming

        refreshThemeAwareAppearance()
        let targetScale: CGFloat = isHovering ? Self.hoverScale : 1.0

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardView.layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
            CATransaction.commit()
            currentCardScale = targetScale
            return
        }

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

    @objc private func handleOpen() {
        onOpen?()
    }

    @objc private func handleAction() {
        if currentIsDownloading {
            onCancelDownload?()
        } else if actionButton.title == "设为壁纸" {
            onSetAsWallpaper?()
        } else {
            onDownload?()
        }
    }
}
