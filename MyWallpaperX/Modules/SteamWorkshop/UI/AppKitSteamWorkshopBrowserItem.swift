//
//  AppKitSteamWorkshopBrowserItem.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

private final class SteamWorkshopOverlayIconButton: NSButton {
    var normalBackgroundColor: NSColor = .clear {
        didSet { updateAppearance() }
    }
    var hoverBackgroundColor: NSColor = NSColor.white.withAlphaComponent(0.12) {
        didSet { updateAppearance() }
    }
    var pressedBackgroundColor: NSColor = NSColor.white.withAlphaComponent(0.18) {
        didSet { updateAppearance() }
    }
    var iconTintColor: NSColor = .labelColor {
        didSet { contentTintColor = iconTintColor }
    }
    var cornerRadius: CGFloat = 12 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var borderColor: NSColor = .clear {
        didSet { layer?.borderColor = borderColor.cgColor }
    }
    var borderWidth: CGFloat = 0 {
        didSet { layer?.borderWidth = borderWidth }
    }

    private var isHovering = false {
        didSet { updateAppearance() }
    }
    private var isPressing = false {
        didSet { updateAppearance() }
    }
    private var trackingAreaRef: NSTrackingArea?

    override var isEnabled: Bool {
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        isPressing = false
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

    private func commonInit() {
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = borderWidth
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = iconTintColor
        updateAppearance()
    }

    private func updateAppearance() {
        let background: NSColor
        if !isEnabled {
            background = .clear
        } else if isPressing {
            background = pressedBackgroundColor
        } else if isHovering {
            background = hoverBackgroundColor
        } else {
            background = normalBackgroundColor
        }
        layer?.backgroundColor = background.cgColor
        contentTintColor = isEnabled ? iconTintColor : .disabledControlTextColor
        alphaValue = isEnabled ? 1 : 0.45
    }
}

private final class SteamWorkshopMarqueeTextView: NSView {
    private let clippingView = NSView()
    private let textField = NSTextField(labelWithString: "")
    private let fadeMaskLayer = CAGradientLayer()
    private var displayText = ""
    private var isActive = false
    private var isPerformingLayout = false
    private let repeatedGap = "     "

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            updateDisplayedText()
        }
    }

    var font: NSFont = .systemFont(ofSize: 13, weight: .semibold) {
        didSet {
            textField.font = font
            updateDisplayedText()
        }
    }

    var textColor: NSColor = .labelColor {
        didSet {
            textField.textColor = textColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func layout() {
        super.layout()
        isPerformingLayout = true
        defer { isPerformingLayout = false }
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            clippingView.frame = .zero
            textField.frame = .zero
            textField.layer?.removeAnimation(forKey: "steam.marquee")
            return
        }
        clippingView.frame = bounds
        updateFadeMask()
        layoutTextField()
        updateAnimation()
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        updateAnimation()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.mask = fadeMaskLayer

        clippingView.wantsLayer = true
        clippingView.layer?.backgroundColor = NSColor.clear.cgColor
        clippingView.layer?.masksToBounds = true
        addSubview(clippingView)

        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.font = font
        textField.textColor = textColor
        textField.wantsLayer = true
        clippingView.addSubview(textField)
    }

    private func updateDisplayedText() {
        displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        textField.stringValue = displayText
        if !isPerformingLayout {
            needsLayout = true
        }
    }

    private func layoutTextField() {
        let height = max(0, bounds.height.isFinite ? bounds.height : 0)
        let textHeight = ceil(font.pointSize + 4)
        let y = floor((height - textHeight) * 0.5)
        let baseWidth = measuredWidth(for: displayText)
        if shouldScroll(baseWidth: baseWidth) {
            textField.stringValue = displayText + repeatedGap + displayText
            let fullWidth = measuredWidth(for: textField.stringValue)
            textField.frame = CGRect(x: 0, y: y.isFinite ? y : 0, width: max(0, fullWidth), height: textHeight)
        } else {
            textField.stringValue = displayText
            textField.frame = CGRect(
                x: 0,
                y: y.isFinite ? y : 0,
                width: max(0, bounds.width.isFinite ? bounds.width : 0, baseWidth),
                height: textHeight
            )
        }
    }

    private func updateFadeMask() {
        fadeMaskLayer.frame = bounds
        fadeMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMaskLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor
        ]
        fadeMaskLayer.locations = [0, 0.09, 0.91, 1]
    }

    private func updateAnimation() {
        textField.layer?.removeAnimation(forKey: "steam.marquee")
        guard !displayText.isEmpty else { return }
        guard bounds.width.isFinite, bounds.height.isFinite else { return }

        let baseWidth = measuredWidth(for: displayText)
        guard shouldScroll(baseWidth: baseWidth), isActive else {
            var frame = textField.frame
            frame.origin.x = 0
            frame.origin.y = frame.origin.y.isFinite ? frame.origin.y : 0
            textField.frame = frame
            return
        }

        let travel = baseWidth + measuredWidth(for: repeatedGap)
        let startX = textField.layer?.position.x ?? (textField.frame.width * 0.5)
        guard travel.isFinite, startX.isFinite, travel > 8 else { return }

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = startX
        animation.toValue = startX - travel
        animation.duration = max(7, Double(travel / 22))
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        textField.layer?.add(animation, forKey: "steam.marquee")
    }

    private func shouldScroll(baseWidth: CGFloat) -> Bool {
        guard baseWidth.isFinite, bounds.width.isFinite else { return false }
        return baseWidth > max(24, bounds.width - 8)
    }

    private func measuredWidth(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        guard measured.isFinite else { return 0 }
        return ceil(measured)
    }
}

private final class SteamWorkshopGlassBarView: NSGlassEffectView {
    private let glossLayer = CAGradientLayer()

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
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.clear.cgColor
        glossLayer.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
            NSColor.clear.cgColor
        ]
        glossLayer.locations = [0.0, 0.12, 0.46]
        glossLayer.startPoint = CGPoint(x: 0.18, y: 0.98)
        glossLayer.endPoint = CGPoint(x: 0.82, y: 0.08)
        layer?.addSublayer(glossLayer)
        updateMaterial()
    }

    override func layout() {
        super.layout()
        glossLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    private func updateMaterial() {
        style = .regular
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tintColor = NSColor(calibratedWhite: 0.10, alpha: 0.82)
        } else {
            tintColor = NSColor(calibratedWhite: 1.0, alpha: 0.72)
        }
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = (isDarkMode
            ? NSColor(calibratedWhite: 0.18, alpha: 0.16)
            : NSColor(calibratedWhite: 1.0, alpha: 0.20)
        ).cgColor
    }
}

final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.03
    private static let pressedScale: CGFloat = 0.98

    private let cardView = AppearanceAwareContainerView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let overlayBar = SteamWorkshopGlassBarView()
    private let detailButton = SteamWorkshopOverlayIconButton()
    private let titleMarqueeView = SteamWorkshopMarqueeTextView()
    private let statusBadgeButton = SteamWorkshopOverlayIconButton()

    private var imageTask: Task<Void, Never>?
    private var currentPreviewURL: URL?
    private var currentTitleText = ""
    private var onOpen: (() -> Void)?
    private var onAuthor: (() -> Void)?
    private var onDownload: (() -> Void)?
    private var onSetAsWallpaper: (() -> Void)?
    private var onCancelDownload: (() -> Void)?
    private var currentActionKind: ActionKind = .download
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private var isPressingCard = false
    private var currentCardScale: CGFloat = 1.0
    private var currentBarVisibility = false

    private enum ActionKind {
        case download
        case cancel
        case setAsWallpaper
        case retry
    }

    private enum Layout {
        static let cardCornerRadius: CGFloat = 14
        static let referenceCardWidth: CGFloat = 250
        static let cardInset: CGFloat = 2
        static let barHorizontalInset: CGFloat = 12
        static let barBottomInset: CGFloat = 11
        static let hoverLift: CGFloat = 2
        static let barHeight: CGFloat = 34
        static let iconButtonSize: CGFloat = 30
        static let statusBadgeSize: CGFloat = 30
        static let barEdgeInset: CGFloat = 6
        static let barSpacing: CGFloat = 5
        static let marqueeSideInset: CGFloat = 4
    }

    private struct Metrics {
        let scale: CGFloat
        let barHorizontalInset: CGFloat
        let barBottomInset: CGFloat
        let barHeight: CGFloat
        let iconButtonSize: CGFloat
        let badgeSize: CGFloat
        let barEdgeInset: CGFloat
        let barSpacing: CGFloat
        let marqueeSideInset: CGFloat
        let titleFont: NSFont
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
        titleMarqueeView.text = ""
        previewImageView.image = nil
        onOpen = nil
        onAuthor = nil
        onDownload = nil
        onSetAsWallpaper = nil
        onCancelDownload = nil
        currentActionKind = .download
        isHovering = false
        isPressingCard = false
        currentCardScale = 1.0
        currentBarVisibility = false
        cardView.layer?.transform = CATransform3DIdentity
        overlayBar.alphaValue = 0
        titleMarqueeView.setActive(false)
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
        onAuthor: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onAuthor = onAuthor
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        applyContent(
            item: item,
            downloadRecord: downloadRecord,
            downloadProgressText: downloadProgressText,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            isKeyboardFocused: isKeyboardFocused
        )
        loadPreview(from: item.previewImageURL)
    }

    func configureMetadataOnly(
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        downloadProgressText: String?,
        isDownloading: Bool,
        isDownloaded: Bool,
        isKeyboardFocused: Bool,
        onOpen: @escaping () -> Void,
        onAuthor: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onAuthor = onAuthor
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        applyContent(
            item: item,
            downloadRecord: downloadRecord,
            downloadProgressText: downloadProgressText,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            isKeyboardFocused: isKeyboardFocused
        )
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let bounds = view.bounds
        guard bounds.width.isFinite, bounds.height.isFinite else { return }
        cardView.frame = bounds.insetBy(dx: Layout.cardInset, dy: Layout.cardInset)
        ensureCardAnchorCenteredIfNeeded()

        let metrics = metrics(for: cardView.bounds.size)
        applyMetrics(metrics)

        previewContainer.frame = cardView.bounds
        updatePreviewImageFrame()

        let barWidth = max(0, cardView.bounds.width - metrics.barHorizontalInset * 2)
        overlayBar.frame = CGRect(
            x: metrics.barHorizontalInset,
            y: metrics.barBottomInset,
            width: barWidth,
            height: metrics.barHeight
        )

        let iconSize = metrics.iconButtonSize
        let barMidY = floor((overlayBar.bounds.height - iconSize) * 0.5)
        detailButton.frame = CGRect(x: metrics.barEdgeInset, y: barMidY, width: iconSize, height: iconSize)
        statusBadgeButton.frame = CGRect(
            x: overlayBar.bounds.width - iconSize - metrics.barEdgeInset,
            y: barMidY,
            width: iconSize,
            height: iconSize
        )

        let marqueeX = detailButton.frame.maxX + metrics.barSpacing
        let marqueeWidth = max(24, statusBadgeButton.frame.minX - metrics.barSpacing - marqueeX)
        titleMarqueeView.frame = CGRect(
            x: marqueeX + metrics.marqueeSideInset,
            y: 0,
            width: max(24, marqueeWidth - metrics.marqueeSideInset * 2),
            height: overlayBar.bounds.height
        )

        applyHoverStyle(animated: false)
        refreshTrackingArea()
        syncHoverStateFromWindow(animated: false)
    }

    func setKeyboardFocus(_ focused: Bool) {
        if focused {
            syncHoverStateFromWindow(animated: false)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        syncHoverState(with: event, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        syncHoverState(with: event, animated: true)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        syncHoverState(with: event, animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = view.convert(event.locationInWindow, from: nil)
        if view.bounds.contains(localPoint) {
            isHovering = true
            applyPressedState(true)
        }
        super.mouseDown(with: event)
        applyPressedState(false)
        syncHoverState(with: event, animated: true)
    }

    private func applyContent(
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        downloadProgressText: String?,
        isDownloading: Bool,
        isDownloaded: Bool,
        isKeyboardFocused: Bool
    ) {
        currentTitleText = item.title
        titleMarqueeView.text = item.title
        detailButton.setAccessibilityLabel("查看详情：\(item.title)")

        currentActionKind = resolvedActionKind(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )
        applyStatusBadgeAppearance(
            actionKind: currentActionKind,
            itemTitle: item.title,
            progressText: downloadProgressText
        )

        titleMarqueeView.setActive(isHovering)
        refreshThemeAwareAppearance()
        if view.window != nil {
            applyHoverStyle(animated: false)
        }
    }

    private func resolvedActionKind(
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool
    ) -> ActionKind {
        if isDownloading {
            return .cancel
        }
        if isDownloaded {
            return .setAsWallpaper
        }
        if downloadRecord?.failureMessage != nil {
            return .retry
        }
        return .download
    }

    private func applyStatusBadgeAppearance(
        actionKind: ActionKind,
        itemTitle: String,
        progressText: String?
    ) {
        let symbolName: String
        let tintColor: NSColor
        let accessibilityLabel: String

        switch actionKind {
        case .download:
            symbolName = "arrow.down"
            tintColor = .white
            accessibilityLabel = "下载：\(itemTitle)"
        case .cancel:
            symbolName = "hourglass"
            tintColor = .white
            accessibilityLabel = progressText?.isEmpty == false
                ? "取消下载：\(itemTitle)，当前进度 \(progressText!)"
                : "取消下载：\(itemTitle)"
        case .setAsWallpaper:
            symbolName = "checkmark"
            tintColor = .white
            accessibilityLabel = "设为壁纸：\(itemTitle)"
        case .retry:
            symbolName = "exclamationmark"
            tintColor = .white
            accessibilityLabel = "重新下载：\(itemTitle)"
        }

        statusBadgeButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )
        statusBadgeButton.iconTintColor = tintColor
        statusBadgeButton.setAccessibilityLabel(accessibilityLabel)
    }

    private func metrics(for cardSize: CGSize) -> Metrics {
        let scale = max(0.68, min(1.18, cardSize.width / Layout.referenceCardWidth))
        return Metrics(
            scale: scale,
            barHorizontalInset: round(Layout.barHorizontalInset * scale),
            barBottomInset: round(Layout.barBottomInset * scale),
            barHeight: round(Layout.barHeight * scale),
            iconButtonSize: round(Layout.iconButtonSize * scale),
            badgeSize: round(Layout.statusBadgeSize * scale),
            barEdgeInset: round(Layout.barEdgeInset * scale),
            barSpacing: round(Layout.barSpacing * scale),
            marqueeSideInset: round(Layout.marqueeSideInset * scale),
            titleFont: .systemFont(ofSize: 12.5 * scale, weight: .medium),
            buttonCornerRadius: max(8, min(12, 11 * scale))
        )
    }

    private func applyMetrics(_ metrics: Metrics) {
        let targetBarRadius = Layout.cardCornerRadius
        if abs((overlayBar.layer?.cornerRadius ?? 0) - targetBarRadius) > 0.001 {
            overlayBar.layer?.cornerRadius = targetBarRadius
        }
        let targetButtonRadius = max(8, min(12, Layout.cardCornerRadius - 1))
        if abs(detailButton.cornerRadius - targetButtonRadius) > 0.001 {
            detailButton.cornerRadius = targetButtonRadius
        }
        let targetBadgeRadius = targetButtonRadius
        if abs(statusBadgeButton.cornerRadius - targetBadgeRadius) > 0.001 {
            statusBadgeButton.cornerRadius = targetBadgeRadius
        }
        if abs(titleMarqueeView.font.pointSize - metrics.titleFont.pointSize) > 0.001 {
            titleMarqueeView.font = metrics.titleFont
        }
        let overlaySymbolConfig = NSImage.SymbolConfiguration(pointSize: max(15, metrics.iconButtonSize * 0.56), weight: .medium)
        detailButton.contentTintColor = detailButton.iconTintColor
        detailButton.image = detailButton.image?.withSymbolConfiguration(overlaySymbolConfig)
        let badgeSymbolConfig = NSImage.SymbolConfiguration(pointSize: max(15, metrics.badgeSize * 0.54), weight: .semibold)
        statusBadgeButton.image = statusBadgeButton.image?.withSymbolConfiguration(badgeSymbolConfig)
    }

    private func refreshTrackingArea() {
        if let trackingAreaRef {
            view.removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    private func buildHierarchy() {
        view.wantsLayer = true

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = Layout.cardCornerRadius
        cardView.layer?.masksToBounds = false
        cardView.layer?.borderWidth = 0.8
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0.03
        cardView.layer?.shadowRadius = 7
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        cardView.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
            self?.applyHoverStyle(animated: false)
        }
        view.addSubview(cardView)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = Layout.cardCornerRadius
        previewContainer.layer?.masksToBounds = true
        cardView.addSubview(previewContainer)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewImageView.animates = true
        previewContainer.addSubview(previewImageView)

        overlayBar.alphaValue = 0
        overlayBar.wantsLayer = true
        cardView.addSubview(overlayBar)

        detailButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "详情")
        detailButton.target = self
        detailButton.action = #selector(handleOpen)
        overlayBar.addSubview(detailButton)

        overlayBar.addSubview(titleMarqueeView)

        statusBadgeButton.target = self
        statusBadgeButton.action = #selector(handleStatusAction)
        overlayBar.addSubview(statusBadgeButton)

        refreshThemeAwareAppearance()
    }

    private func refreshThemeAwareAppearance() {
        guard let layer = cardView.layer else { return }
        let isDarkMode = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fixedForeground = isDarkMode
            ? NSColor(calibratedWhite: 1.0, alpha: 0.98)
            : NSColor(calibratedWhite: 0.08, alpha: 0.92)
        let fixedBorder = isDarkMode
            ? NSColor(calibratedWhite: 0.18, alpha: isHovering ? 0.18 : 0.14)
            : NSColor(calibratedWhite: 1.0, alpha: isHovering ? 0.22 : 0.18)

        layer.backgroundColor = NSColor.clear.cgColor
        let ringColor: NSColor
        if isHovering {
            ringColor = NSColor.white.withAlphaComponent(0.12)
        } else {
            ringColor = NSColor.white.withAlphaComponent(0.028)
        }
        layer.borderColor = ringColor.cgColor
        layer.shadowOpacity = isHovering ? 0.05 : 0.025
        layer.shadowRadius = isHovering ? 7 : 6
        layer.shadowOffset = CGSize(width: 0, height: -1)

        previewContainer.layer?.backgroundColor = NSColor.clear.cgColor

        overlayBar.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        overlayBar.alphaValue = currentBarVisibility ? 0.90 : 0
        overlayBar.layer?.shadowColor = NSColor.black.cgColor
        overlayBar.layer?.borderColor = fixedBorder.cgColor
        overlayBar.layer?.borderWidth = 0.8
        overlayBar.layer?.shadowOpacity = 0.015
        overlayBar.layer?.shadowRadius = 2
        overlayBar.layer?.shadowOffset = .zero

        detailButton.normalBackgroundColor = .clear
        detailButton.hoverBackgroundColor = .clear
        detailButton.pressedBackgroundColor = .clear
        detailButton.iconTintColor = fixedForeground
        detailButton.borderColor = .clear
        detailButton.borderWidth = 0
        detailButton.appearance = overlayBar.appearance

        titleMarqueeView.textColor = fixedForeground
        titleMarqueeView.appearance = overlayBar.appearance

        switch currentActionKind {
        case .download:
            statusBadgeButton.normalBackgroundColor = .clear
        case .cancel:
            statusBadgeButton.normalBackgroundColor = .clear
        case .setAsWallpaper:
            statusBadgeButton.normalBackgroundColor = .clear
        case .retry:
            statusBadgeButton.normalBackgroundColor = .clear
        }
        statusBadgeButton.hoverBackgroundColor = .clear
        statusBadgeButton.pressedBackgroundColor = .clear
        statusBadgeButton.borderColor = .clear
        statusBadgeButton.borderWidth = 0
        statusBadgeButton.iconTintColor = fixedForeground
        statusBadgeButton.appearance = overlayBar.appearance
    }

    private func applyHoverStyle(animated: Bool) {
        let shouldRevealBar = isHovering
        let targetScale: CGFloat
        if shouldRevealBar {
            targetScale = isPressingCard ? Self.pressedScale : Self.hoverScale
        } else {
            targetScale = 1.0
        }

        titleMarqueeView.setActive(shouldRevealBar)
        refreshThemeAwareAppearance()

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardView.layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
            overlayBar.alphaValue = shouldRevealBar ? 1 : 0
            overlayBar.layer?.transform = CATransform3DMakeTranslation(0, shouldRevealBar ? 0 : 4, 0)
            CATransaction.commit()
            currentCardScale = targetScale
            currentBarVisibility = shouldRevealBar
            return
        }

        let duration = shouldRevealBar
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let timing = shouldRevealBar
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            self.cardView.animator().alphaValue = 1
            self.overlayBar.animator().alphaValue = shouldRevealBar ? 1 : 0
        }

        applyCardTransform(targetScale: targetScale, duration: duration, timing: timing)
        applyBarTransform(isVisible: shouldRevealBar, duration: duration, timing: timing)
        currentBarVisibility = shouldRevealBar
    }

    private func applyPressedState(_ pressed: Bool) {
        guard isPressingCard != pressed else { return }
        isPressingCard = pressed
        guard isHovering else { return }
        applyCardTransform(
            targetScale: pressed ? Self.pressedScale : Self.hoverScale,
            duration: pressed ? UIInteractionAnimation.cardPressDownDuration : UIInteractionAnimation.cardPressUpDuration,
            timing: pressed ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        )
    }

    private func applyCardTransform(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = cardView.layer else { return }
        ensureCardAnchorCenteredIfNeeded()
        guard abs(currentCardScale - targetScale) > 0.001 else { return }

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

    private func applyBarTransform(isVisible: Bool, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = overlayBar.layer else { return }
        let targetTransform = CATransform3DMakeTranslation(0, isVisible ? 0 : 4, 0)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer.transform
        animation.toValue = targetTransform
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "steam.card.bar.transform")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        CATransaction.commit()
    }

    private func loadPreview(from url: URL?) {
        guard currentPreviewURL != url else { return }
        currentPreviewURL = url
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
            guard let self, self.currentPreviewURL == url else { return }
            self.previewImageView.image = image
            self.updatePreviewImageFrame()
        }
    }

    private func updatePreviewImageFrame() {
        let containerBounds = previewContainer.bounds
        guard
            containerBounds.width.isFinite,
            containerBounds.height.isFinite,
            containerBounds.width > 0,
            containerBounds.height > 0
        else {
            previewImageView.frame = .zero
            return
        }
        guard
            let image = previewImageView.image,
            image.size.width.isFinite,
            image.size.height.isFinite,
            image.size.width > 0,
            image.size.height > 0
        else {
            previewImageView.frame = containerBounds
            return
        }

        let widthScale = containerBounds.width / image.size.width
        let heightScale = containerBounds.height / image.size.height
        let fillScale = max(widthScale, heightScale)
        let fittedWidth = image.size.width * fillScale
        let fittedHeight = image.size.height * fillScale
        guard fittedWidth.isFinite, fittedHeight.isFinite else {
            previewImageView.frame = containerBounds
            return
        }
        previewImageView.frame = CGRect(
            x: floor((containerBounds.width - fittedWidth) * 0.5),
            y: floor((containerBounds.height - fittedHeight) * 0.5),
            width: ceil(fittedWidth),
            height: ceil(fittedHeight)
        )
    }

    private func ensureCardAnchorCenteredIfNeeded() {
        cardView.ensureLayerAnchorCentered()
    }

    private func syncHoverState(with event: NSEvent, animated: Bool) {
        let localPoint = view.convert(event.locationInWindow, from: nil)
        let hoveringNow = view.bounds.contains(localPoint)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        applyHoverStyle(animated: animated)
    }

    private func syncHoverStateFromWindow(animated: Bool) {
        guard let window = view.window else { return }
        let localPoint = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hoveringNow = view.bounds.contains(localPoint)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        applyHoverStyle(animated: animated)
    }

    @objc private func handleOpen() {
        onOpen?()
    }

    @objc private func handleStatusAction() {
        switch currentActionKind {
        case .download, .retry:
            onDownload?()
        case .cancel:
            onCancelDownload?()
        case .setAsWallpaper:
            onSetAsWallpaper?()
        }
    }
}
