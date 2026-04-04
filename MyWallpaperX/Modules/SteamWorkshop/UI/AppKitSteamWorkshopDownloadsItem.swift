//
//  AppKitSteamWorkshopDownloadsItem.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

private final class SteamWorkshopDownloadsCardButton: NSButton {
    var normalBackgroundColor: NSColor = .controlColor {
        didSet { updateAppearance() }
    }
    var pressedBackgroundColor: NSColor = .controlAccentColor.withAlphaComponent(0.78)
    var disabledBackgroundColor: NSColor = .disabledControlTextColor.withAlphaComponent(0.16)
    var cornerRadius: CGFloat = 12 {
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
        font = .systemFont(ofSize: 13, weight: .medium)
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

private final class SteamWorkshopDownloadsCardTextLineView: NSView {
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

final class AppKitSteamWorkshopDownloadsItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.03
    private let cardView = AppearanceAwareContainerView()
    private let previewContainer = NSView()
    private let textContainer = NSView()
    private let buttonsContainer = NSView()
    private let previewImageView = NSImageView()
    private let titleLabel = SteamWorkshopMarqueeTextView()
    private let metaLabel = SteamWorkshopDownloadsCardTextLineView()
    private let secondaryMetaLabel = SteamWorkshopDownloadsCardTextLineView()
    private let progressIndicator = NSProgressIndicator()
    private let setAsWallpaperButton = SteamWorkshopDownloadsCardButton(title: "设为壁纸", target: nil, action: nil)
    private let revealButton = SteamWorkshopDownloadsCardButton(title: "显示文件", target: nil, action: nil)

    private var imageTask: Task<Void, Never>?
    private var currentPreviewURL: URL?
    private var onSetAsWallpaper: (() -> Void)?
    private var onReveal: (() -> Void)?
    private var onRetry: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var currentRecord: SteamWorkshopDownloadRecord?
    private var keyboardFocused = false
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private var currentCardScale: CGFloat = 1.0
    private var currentTitleText = ""

    private enum Layout {
        static let cardCornerRadius: CGFloat = 12
        static let referenceCardWidth: CGFloat = 250
        static let referenceCardHeight: CGFloat = 354
        static let outerInset: CGFloat = 0
        static let contentInset: CGFloat = 10
        static let buttonBottomInset: CGFloat = 14
        static let previewInset: CGFloat = 0
        static let previewTopInset: CGFloat = 0
        static let buttonHeight: CGFloat = 30
        static let buttonWidth: CGFloat = 100
        static let buttonGap: CGFloat = 8
        static let interSectionSpacing: CGFloat = 8
        static let textLineGap: CGFloat = 3
        static let progressGap: CGFloat = 6
        static let progressHeight: CGFloat = 6
        static let textToButtonsGap: CGFloat = 8
        static let titleLineHeight: CGFloat = 20
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
        let progressGap: CGFloat
        let progressHeight: CGFloat
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
        previewImageView.image = nil
        currentTitleText = ""
        titleLabel.text = ""
        metaLabel.text = ""
        secondaryMetaLabel.text = ""
        progressIndicator.isHidden = true
        progressIndicator.doubleValue = 0
        onSetAsWallpaper = nil
        onReveal = nil
        onRetry = nil
        onCancel = nil
        isHovering = false
        currentCardScale = 1.0
        keyboardFocused = false
        cardView.layer?.transform = CATransform3DIdentity
        textContainer.frame = .zero
        buttonsContainer.frame = .zero
        refreshThemeAwareAppearance()
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
        setAsWallpaperButton.frame = CGRect(x: buttonsStartX, y: 0, width: buttonWidth, height: buttonHeight)
        revealButton.frame = CGRect(
            x: buttonsStartX + buttonWidth + buttonGap,
            y: 0,
            width: buttonWidth,
            height: buttonHeight
        )

        let showsProgress = !progressIndicator.isHidden
        let progressBlockHeight = showsProgress ? (metrics.progressGap + metrics.progressHeight) : 0
        let textBottom = buttonsY + buttonHeight + metrics.textToButtonsGap
        let textContainerHeight = metrics.titleLineHeight + metrics.metaLineHeight * 2 + metrics.textLineGap * 2 + progressBlockHeight
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
            y: metaLabel.frame.maxY + metrics.textLineGap,
            width: contentWidth,
            height: metrics.titleLineHeight
        )
        titleLabel.text = currentTitleText
        titleLabel.setActive(true)
        progressIndicator.frame = CGRect(
            x: 0,
            y: titleLabel.frame.maxY + metrics.progressGap,
            width: contentWidth,
            height: metrics.progressHeight
        )

        let previewY = textContainer.frame.maxY + metrics.interSectionSpacing
        let previewHeight = max(0, cardView.bounds.height - Layout.previewInset - Layout.previewTopInset - previewY)
        let previewOverlap: CGFloat = 1
        previewContainer.frame = CGRect(
            x: Layout.previewInset - previewOverlap,
            y: previewY - previewOverlap,
            width: cardView.bounds.width - Layout.previewInset * 2 + previewOverlap * 2,
            height: previewHeight + previewOverlap
        )
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
            progressGap: round(Layout.progressGap * scale),
            progressHeight: max(4, round(Layout.progressHeight * scale)),
            textToButtonsGap: round(Layout.textToButtonsGap * scale),
            titleLineHeight: round(Layout.titleLineHeight * scale),
            metaLineHeight: round(Layout.metaLineHeight * scale),
            titleFont: .systemFont(ofSize: 14 * scale, weight: .semibold),
            metaFont: .monospacedSystemFont(ofSize: 11 * scale, weight: .medium),
            secondaryMetaFont: .systemFont(ofSize: 11 * scale, weight: .medium),
            buttonFont: .systemFont(ofSize: 13 * scale, weight: .medium),
            buttonCornerRadius: max(8, min(14, 10 * scale))
        )
    }

    private func applyMetrics(_ metrics: Metrics) {
        titleLabel.font = metrics.titleFont
        metaLabel.font = metrics.metaFont
        secondaryMetaLabel.font = metrics.secondaryMetaFont
        setAsWallpaperButton.font = metrics.buttonFont
        revealButton.font = metrics.buttonFont
        setAsWallpaperButton.cornerRadius = metrics.buttonCornerRadius
        revealButton.cornerRadius = metrics.buttonCornerRadius
    }

    func configure(
        record: SteamWorkshopDownloadRecord,
        downloadProgressFraction: Double?,
        isKeyboardFocused: Bool,
        onSetAsWallpaper: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onReveal = onReveal
        self.onRetry = onRetry
        self.onCancel = onCancel
        self.currentRecord = record

        currentTitleText = record.title
        metaLabel.text = record.id
        secondaryMetaLabel.text = [record.sizeText, record.statusText].joined(separator: "  ·  ")
        if case .downloading = record.status, let downloadProgressFraction {
            progressIndicator.isHidden = false
            progressIndicator.doubleValue = min(max(downloadProgressFraction, 0), 1) * 100
        } else {
            progressIndicator.isHidden = true
            progressIndicator.doubleValue = 0
        }

        switch record.status {
        case .ready:
            setAsWallpaperButton.title = record.isPlayable ? "设为壁纸" : "已下载"
            setAsWallpaperButton.isEnabled = record.isPlayable
            setAsWallpaperButton.setAccessibilityLabel(
                record.isPlayable
                ? "设为壁纸：\(record.title)"
                : "缺少可播放视频：\(record.title)"
            )
        case .failed:
            setAsWallpaperButton.title = "重新下载"
            setAsWallpaperButton.isEnabled = true
            setAsWallpaperButton.setAccessibilityLabel("重新下载：\(record.title)")
        case .downloading:
            setAsWallpaperButton.title = "取消下载"
            setAsWallpaperButton.isEnabled = true
            setAsWallpaperButton.setAccessibilityLabel("取消下载：\(record.title)")
        }

        let folderExists = FileManager.default.fileExists(atPath: record.folderURL.path)
        revealButton.isEnabled = folderExists
        revealButton.setAccessibilityLabel("显示文件：\(record.title)")
        loadPreview(from: record.previewURL)
        setKeyboardFocus(isKeyboardFocused)
    }

    private func buildHierarchy() {
        view.wantsLayer = true

        cardView.wantsLayer = true
        cardView.canDrawSubviewsIntoLayer = true
        cardView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cardView.layer?.cornerRadius = Layout.cardCornerRadius
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
        previewContainer.layer?.cornerRadius = Layout.cardCornerRadius
        previewContainer.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cardView.addSubview(previewContainer)

        textContainer.wantsLayer = true
        textContainer.layer?.backgroundColor = NSColor.clear.cgColor
        cardView.addSubview(textContainer)

        buttonsContainer.wantsLayer = true
        buttonsContainer.layer?.backgroundColor = NSColor.clear.cgColor
        cardView.addSubview(buttonsContainer)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewContainer.addSubview(previewImageView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.setActive(true)
        textContainer.addSubview(titleLabel)

        metaLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        metaLabel.textColor = .secondaryLabelColor
        textContainer.addSubview(metaLabel)

        secondaryMetaLabel.font = .systemFont(ofSize: 11, weight: .medium)
        secondaryMetaLabel.textColor = .secondaryLabelColor
        textContainer.addSubview(secondaryMetaLabel)

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.doubleValue = 0
        progressIndicator.controlSize = .small
        progressIndicator.style = .bar
        progressIndicator.isHidden = true
        textContainer.addSubview(progressIndicator)

        setAsWallpaperButton.normalBackgroundColor = NSColor.systemGreen.blended(withFraction: 0.26, of: .black) ?? .systemGreen
        setAsWallpaperButton.pressedBackgroundColor = setAsWallpaperButton.normalBackgroundColor.blended(withFraction: 0.18, of: .black) ?? setAsWallpaperButton.normalBackgroundColor
        setAsWallpaperButton.cornerRadius = 10
        setAsWallpaperButton.target = self
        setAsWallpaperButton.action = #selector(handleSetAsWallpaper)
        buttonsContainer.addSubview(setAsWallpaperButton)

        revealButton.normalBackgroundColor = NSColor.controlColor
        revealButton.pressedBackgroundColor = NSColor.controlColor.blended(withFraction: 0.18, of: .black) ?? NSColor.controlColor
        revealButton.cornerRadius = 10
        revealButton.target = self
        revealButton.action = #selector(handleReveal)
        buttonsContainer.addSubview(revealButton)

        refreshThemeAwareAppearance()
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
        layer.add(animation, forKey: "steam.download.card.hover.scale")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
        currentCardScale = targetScale
    }

    private func ensureCardAnchorCenteredIfNeeded() {
        cardView.ensureLayerAnchorCentered()
    }

    private func refreshThemeAwareAppearance() {
        guard let layer = cardView.layer else { return }
        layer.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let borderColor: NSColor
        if keyboardFocused {
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.60)
        } else if isHovering {
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.30)
        } else {
            borderColor = NSColor.separatorColor.withAlphaComponent(0.22)
        }
        layer.borderColor = borderColor.cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = keyboardFocused ? 0.18 : (isHovering ? 0.14 : 0.04)
        layer.shadowRadius = keyboardFocused ? 12 : (isHovering ? 10 : 6)
        layer.shadowOffset = CGSize(width: 0, height: -1)
        previewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        titleLabel.textColor = .labelColor
        metaLabel.textColor = .secondaryLabelColor
        secondaryMetaLabel.textColor = .secondaryLabelColor
    }

    func setKeyboardFocus(_ focused: Bool) {
        guard keyboardFocused != focused else { return }
        keyboardFocused = focused
        refreshThemeAwareAppearance()
    }

    func performPrimaryKeyboardAction() {
        handleSetAsWallpaper()
    }

    private func loadPreview(from url: URL?) {
        guard currentPreviewURL != url else { return }
        currentPreviewURL = url
        previewImageView.animates = true
        imageTask?.cancel()

        guard let url else {
            previewImageView.image = nil
            updatePreviewImageFrame()
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
            try? Data(contentsOf: url)
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

    @objc private func handleSetAsWallpaper() {
        guard let record = currentRecord else { return }
        switch record.status {
        case .ready:
            if record.isPlayable {
                onSetAsWallpaper?()
            }
        case .failed:
            onRetry?()
        case .downloading:
            onCancel?()
        }
    }

    @objc private func handleReveal() {
        onReveal?()
    }
}
