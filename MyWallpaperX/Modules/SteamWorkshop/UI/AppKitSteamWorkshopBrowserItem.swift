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

final class SteamWorkshopMarqueeTextView: NSView {
    private let clippingView = NSView()
    private let containerLayer = CALayer()
    private let leadingTextLayer = CATextLayer()
    private let trailingTextLayer = CATextLayer()
    private let fadeMaskLayer = CAGradientLayer()
    private var displayText = ""
    private var marqueeSegmentWidth: CGFloat = 0
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
            updateTextLayerAppearance()
            updateDisplayedText()
        }
    }

    var textColor: NSColor = .labelColor {
        didSet {
            updateTextLayerAppearance()
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
            containerLayer.frame = .zero
            containerLayer.removeAnimation(forKey: "steam.marquee")
            return
        }
        clippingView.frame = bounds
        updateFadeMask()
        layoutTextLayers()
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func setActive(_ active: Bool) {
        if isActive == active {
            if active {
                updateAnimation()
            }
            return
        }
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

        clippingView.layer?.addSublayer(containerLayer)
        [leadingTextLayer, trailingTextLayer].forEach { layer in
            layer.alignmentMode = .left
            layer.isWrapped = false
            layer.truncationMode = .none
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            containerLayer.addSublayer(layer)
        }
        updateTextLayerAppearance()
    }

    private func updateDisplayedText() {
        displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        marqueeSegmentWidth = 0
        leadingTextLayer.string = displayText
        trailingTextLayer.string = displayText
        if !isPerformingLayout {
            needsLayout = true
        }
    }

    private func updateTextLayerAppearance() {
        let cgColor = textColor.cgColor
        let fontRef = font as CTFont
        [leadingTextLayer, trailingTextLayer].forEach { layer in
            layer.font = fontRef
            layer.fontSize = font.pointSize
            layer.foregroundColor = cgColor
        }
    }

    private func layoutTextLayers() {
        let height = max(0, bounds.height.isFinite ? bounds.height : 0)
        let textHeight = ceil(font.pointSize + 4)
        let y = floor((height - textHeight) * 0.5)
        let baseWidth = measuredWidth(for: displayText)
        if shouldScroll(baseWidth: baseWidth) {
            marqueeSegmentWidth = baseWidth + measuredWidth(for: repeatedGap)
            containerLayer.frame = CGRect(
                x: 0,
                y: y.isFinite ? y : 0,
                width: max(0, marqueeSegmentWidth + baseWidth),
                height: textHeight
            )
            leadingTextLayer.isHidden = false
            trailingTextLayer.isHidden = false
            leadingTextLayer.frame = CGRect(x: 0, y: 0, width: max(0, baseWidth), height: textHeight)
            trailingTextLayer.frame = CGRect(x: marqueeSegmentWidth, y: 0, width: max(0, baseWidth), height: textHeight)
        } else {
            marqueeSegmentWidth = 0
            let centeredX = floor((bounds.width - baseWidth) * 0.5)
            containerLayer.frame = CGRect(
                x: centeredX.isFinite ? centeredX : 0,
                y: y.isFinite ? y : 0,
                width: max(0, baseWidth),
                height: textHeight
            )
            leadingTextLayer.isHidden = false
            trailingTextLayer.isHidden = true
            leadingTextLayer.frame = CGRect(x: 0, y: 0, width: max(0, baseWidth), height: textHeight)
            trailingTextLayer.frame = .zero
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
        containerLayer.removeAnimation(forKey: "steam.marquee")
        guard !displayText.isEmpty else { return }
        guard bounds.width.isFinite, bounds.height.isFinite else { return }

        let baseWidth = measuredWidth(for: displayText)
        guard shouldScroll(baseWidth: baseWidth), isActive else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            containerLayer.transform = CATransform3DIdentity
            CATransaction.commit()
            return
        }

        let travel = marqueeSegmentWidth > 0 ? marqueeSegmentWidth : (baseWidth + measuredWidth(for: repeatedGap))
        guard travel.isFinite, travel > 8 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.transform = CATransform3DIdentity
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -travel
        animation.duration = max(7, Double(travel / 22))
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        containerLayer.add(animation, forKey: "steam.marquee")
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
    enum AccentStyle {
        case neutral
        case downloading
        case queued
        case ready
    }

    private let glossLayer = CAGradientLayer()
    private let accentLayer = CAGradientLayer()
    private let scanLayer = CAGradientLayer()
    private var accentStyle: AccentStyle = .neutral
    private var showsScanAnimation = false

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
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.clear.cgColor
        accentLayer.startPoint = CGPoint(x: 0, y: 0.5)
        accentLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(accentLayer)
        glossLayer.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
            NSColor.clear.cgColor
        ]
        glossLayer.locations = [0.0, 0.12, 0.46]
        glossLayer.startPoint = CGPoint(x: 0.18, y: 0.98)
        glossLayer.endPoint = CGPoint(x: 0.82, y: 0.08)
        layer?.addSublayer(glossLayer)
        scanLayer.startPoint = CGPoint(x: 0, y: 0.5)
        scanLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(scanLayer)
        updateMaterial()
    }

    override func layout() {
        super.layout()
        accentLayer.frame = bounds
        glossLayer.frame = bounds
        scanLayer.frame = CGRect(x: -bounds.width * 0.62, y: 0, width: bounds.width * 0.62, height: bounds.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    private func updateMaterial() {
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accentBaseColor: NSColor = {
            switch accentStyle {
            case .neutral:
                return isDarkMode ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.10)
            case .downloading:
                return NSColor.systemGreen
            case .queued:
                return NSColor.systemBlue
            case .ready:
                return isDarkMode ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.10)
            }
        }()
        let usesSolidStatusFill = accentStyle == .downloading || accentStyle == .queued

        style = usesSolidStatusFill ? .regular : .regular
        tintColor = {
            if usesSolidStatusFill {
                return accentBaseColor.withAlphaComponent(0.80)
            }
            return isDarkMode
                ? NSColor(calibratedWhite: 0.10, alpha: accentStyle == .neutral ? 0.82 : 0.66)
                : NSColor(calibratedWhite: 1.0, alpha: accentStyle == .neutral ? 0.72 : 0.58)
        }()

        layer?.backgroundColor = (usesSolidStatusFill
            ? accentBaseColor.withAlphaComponent(0.80)
            : NSColor.clear
        ).cgColor
        layer?.borderColor = (usesSolidStatusFill
            ? NSColor.white.withAlphaComponent(isDarkMode ? 0.18 : 0.14)
            : accentBaseColor.withAlphaComponent(isDarkMode ? 0.34 : 0.22)
        ).cgColor

        accentLayer.colors = usesSolidStatusFill
            ? [
                accentBaseColor.withAlphaComponent(0.84).cgColor,
                accentBaseColor.withAlphaComponent(0.80).cgColor,
                accentBaseColor.withAlphaComponent(0.84).cgColor
            ]
            : [
                accentBaseColor.withAlphaComponent(isDarkMode ? 0.34 : 0.22).cgColor,
                accentBaseColor.withAlphaComponent(isDarkMode ? 0.18 : 0.10).cgColor,
                NSColor.clear.cgColor
            ]
        accentLayer.locations = usesSolidStatusFill ? [0, 0.5, 1] : [0, 0.55, 1]

        glossLayer.isHidden = usesSolidStatusFill
        scanLayer.colors = usesSolidStatusFill
            ? [
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(isDarkMode ? 0.08 : 0.10).cgColor,
                NSColor.white.withAlphaComponent(isDarkMode ? 0.34 : 0.30).cgColor,
                NSColor.white.withAlphaComponent(isDarkMode ? 0.08 : 0.10).cgColor,
                NSColor.clear.cgColor
            ]
            : [
                NSColor.clear.cgColor,
                accentBaseColor.withAlphaComponent(isDarkMode ? 0.20 : 0.16).cgColor,
                NSColor.white.withAlphaComponent(isDarkMode ? 0.18 : 0.16).cgColor,
                accentBaseColor.withAlphaComponent(isDarkMode ? 0.16 : 0.12).cgColor,
                NSColor.clear.cgColor
            ]
        scanLayer.locations = [0, 0.22, 0.5, 0.78, 1]
        updateScanAnimation()
    }

    func applyAccentStyle(_ style: AccentStyle, animated: Bool) {
        accentStyle = style
        updateMaterial()
    }

    func setScanAnimationEnabled(_ enabled: Bool) {
        showsScanAnimation = enabled
        updateScanAnimation()
    }

    private func updateScanAnimation() {
        scanLayer.removeAnimation(forKey: "steam.bar.scan")
        scanLayer.isHidden = !showsScanAnimation
        guard showsScanAnimation, bounds.width > 0 else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -bounds.width * 1.18
        animation.toValue = bounds.width * 2.18
        animation.duration = 1.75
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        scanLayer.add(animation, forKey: "steam.bar.scan")
    }
}

final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.03
    private static let pressedScale: CGFloat = 0.98

    private let cardView = AppearanceAwareContainerView()
    private let hoverOutlineView = NSView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let previewPlaceholderView = SteamWorkshopPreviewPlaceholderView()
    private let multiSelectBadgeView = NSView()
    private let multiSelectBadgeIcon = NSImageView()
    private let overlayBarShadowView = NSView()
    private let overlayBar = SteamWorkshopGlassBarView()
    private let detailButton = SteamWorkshopOverlayIconButton()
    private let titleMarqueeView = SteamWorkshopMarqueeTextView()
    private let statusBadgeButton = SteamWorkshopOverlayIconButton()
    private let statusSpinner = NSProgressIndicator()

    private var imageTask: Task<Void, Never>?
    private var previewRetryTask: Task<Void, Never>?
    private var currentPreviewURL: URL?
    private var currentDownloadVideoURL: URL?
    private var currentTitleText = ""
    private var onOpen: (() -> Void)?
    private var onAuthor: (() -> Void)?
    private var onDownload: (() -> Void)?
    private var onSetAsWallpaper: (() -> Void)?
    private var onCancelDownload: (() -> Void)?
    private var currentActionKind: ActionKind = .download
    private var prefersCircularPlayBadge = false
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private var isPressingCard = false
    private var currentCardScale: CGFloat = 1.0
    private var currentBarVisibility = false
    private var isHoverOutlineVisible = false
    private var isSelectionHighlighted = false
    private var isMultiSelectMode = false
    private var currentDisplayContext: DisplayContext = .browser
    private var currentBarState: BarState = .idle
    private var shouldPersistBarVisibility = false
    private var currentDebugID = ""

    private enum ActionKind {
        case download
        case cancel
        case setAsWallpaper
        case retry
    }

    enum DisplayContext {
        case browser
        case downloads
    }

    private enum BarState {
        case idle
        case downloading
        case queued
        case ready
        case failed
    }

    private enum Layout {
        static let cardCornerRadius: CGFloat = 14
        static let referenceCardWidth: CGFloat = 250
        static let cardInset: CGFloat = 2
        static let barHorizontalInset: CGFloat = 8
        static let barBottomInset: CGFloat = 11
        static let hoverLift: CGFloat = 2
        static let barHeight: CGFloat = 34
        static let iconButtonSize: CGFloat = 30
        static let statusBadgeSize: CGFloat = 30
        static let barEdgeInset: CGFloat = 8
        static let barSpacing: CGFloat = 8
        static let marqueeSideInset: CGFloat = 2
        static let minBarCornerInset: CGFloat = 4
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
        currentDownloadVideoURL = nil
        currentTitleText = ""
        titleMarqueeView.text = ""
        previewImageView.image = nil
        onOpen = nil
        onAuthor = nil
        onDownload = nil
        onSetAsWallpaper = nil
        onCancelDownload = nil
        currentActionKind = .download
        prefersCircularPlayBadge = false
        isHovering = false
        isPressingCard = false
        currentCardScale = 1.0
        currentBarVisibility = false
        isHoverOutlineVisible = false
        isSelectionHighlighted = false
        isMultiSelectMode = false
        currentDisplayContext = .browser
        currentBarState = .idle
        shouldPersistBarVisibility = false
        currentDebugID = ""
        cardView.layer?.transform = CATransform3DIdentity
        overlayBar.alphaValue = 0
        hoverOutlineView.alphaValue = 0
        titleMarqueeView.setActive(false)
        overlayBar.setScanAnimationEnabled(false)
        overlayBar.applyAccentStyle(.neutral, animated: false)
        statusBadgeButton.layer?.removeAnimation(forKey: "steam.status.spin")
        statusSpinner.stopAnimation(nil)
        statusSpinner.isHidden = true
        previewRetryTask?.cancel()
        refreshThemeAwareAppearance()
    }

    func configure(
        displayContext: DisplayContext = .browser,
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool,
        isMultiSelectMode: Bool = false,
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
        currentDisplayContext = displayContext
        currentDownloadVideoURL = downloadRecord?.videoURL
        currentDebugID = item.id
        prefersCircularPlayBadge = false
        applyContent(
            item: item,
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            isMultiSelectMode: isMultiSelectMode,
            isKeyboardFocused: isKeyboardFocused
        )
        loadPreview(from: item.previewImageURL, fallbackVideoURL: currentDownloadVideoURL)
    }

    func configureMetadataOnly(
        displayContext: DisplayContext = .browser,
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool,
        isMultiSelectMode: Bool = false,
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
        currentDisplayContext = displayContext
        currentDownloadVideoURL = downloadRecord?.videoURL
        currentDebugID = item.id
        prefersCircularPlayBadge = false
        applyContent(
            item: item,
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            isMultiSelectMode: isMultiSelectMode,
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
        hoverOutlineView.frame = cardView.bounds
        updatePreviewImageFrame()

        let barWidth = max(0, cardView.bounds.width - metrics.barHorizontalInset * 2)
        let barFrame = CGRect(
            x: metrics.barHorizontalInset,
            y: metrics.barBottomInset,
            width: barWidth,
            height: metrics.barHeight
        )
        overlayBarShadowView.frame = barFrame
        overlayBar.frame = barFrame

        let iconSize = metrics.iconButtonSize
        let barMidY = floor((overlayBar.bounds.height - iconSize) * 0.5)
        let statusBadgeX = overlayBar.bounds.width - iconSize - metrics.barEdgeInset
        statusBadgeButton.frame = CGRect(
            x: statusBadgeX,
            y: barMidY,
            width: iconSize,
            height: iconSize
        )
        statusSpinner.frame = statusBadgeButton.frame.insetBy(
            dx: max(4, iconSize * 0.2),
            dy: max(4, iconSize * 0.2)
        )
        let detailButtonX = metrics.barEdgeInset
        detailButton.frame = CGRect(
            x: detailButtonX,
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
        statusBadgeButton.ensureLayerAnchorCentered()

        let badgeSize = max(22, min(28, cardView.bounds.width * 0.12))
        let badgeOrigin: CGPoint
        if currentDisplayContext == .downloads && isMultiSelectMode {
            badgeOrigin = CGPoint(
                x: floor((cardView.bounds.width - badgeSize) * 0.5),
                y: floor((cardView.bounds.height - badgeSize) * 0.5)
            )
        } else {
            badgeOrigin = CGPoint(x: 10, y: cardView.bounds.height - badgeSize - 10)
        }
        multiSelectBadgeView.frame = CGRect(origin: badgeOrigin, size: CGSize(width: badgeSize, height: badgeSize))
        multiSelectBadgeIcon.frame = multiSelectBadgeView.bounds.insetBy(dx: 5, dy: 5)

        applyHoverStyle(animated: false)
        refreshTrackingArea()
        syncHoverStateFromWindow(animated: false)
    }

    func setKeyboardFocus(_ focused: Bool) {
        isSelectionHighlighted = focused
        refreshThemeAwareAppearance()
        if view.window != nil {
            applyHoverStyle(animated: false)
        }
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
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }

    private func applyContent(
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool,
        isMultiSelectMode: Bool,
        isKeyboardFocused: Bool
    ) {
        let barState = resolvedBarState(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )
        currentBarState = barState
        shouldPersistBarVisibility = shouldPersistBar(for: barState)
        isSelectionHighlighted = isKeyboardFocused
        self.isMultiSelectMode = isMultiSelectMode
        let displayTitle = resolvedDisplayTitle(item: item, downloadRecord: downloadRecord, barState: barState)
        currentTitleText = item.title
        titleMarqueeView.text = displayTitle
        detailButton.setAccessibilityLabel("详细信息：\(item.title)")

        currentActionKind = resolvedActionKind(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )
        applyStatusBadgeAppearance(
            actionKind: currentActionKind,
            itemTitle: item.title
        )

        titleMarqueeView.setActive(barState == .idle || barState == .ready || barState == .failed)
        refreshThemeAwareAppearance()
        if view.window != nil {
            applyHoverStyle(animated: false)
        }
    }

    private func resolvedBarState(
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool
    ) -> BarState {
        if isDownloading || downloadRecord?.status == .downloading {
            return .downloading
        }
        if downloadRecord?.status == .queued {
            return .queued
        }
        if isDownloaded {
            return .ready
        }
        if downloadRecord?.failureMessage != nil {
            return .failed
        }
        return .idle
    }

    private func resolvedDisplayTitle(
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        barState: BarState
    ) -> String {
        let trimmedRecordSize = downloadRecord?.sizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeText = (trimmedRecordSize?.isEmpty == false ? trimmedRecordSize : nil)
            ?? item.fileSizeText
            ?? "未知大小"

        switch barState {
        case .downloading:
            return "下载中  ·  \(sizeText)"
        case .queued:
            return "等待下载  ·  \(sizeText)"
        case .idle, .ready, .failed:
            return item.title
        }
    }

    private func shouldPersistBar(for state: BarState) -> Bool {
        if currentDisplayContext == .downloads && isMultiSelectMode {
            return false
        }
        switch state {
        case .downloading, .queued:
            return true
        case .ready:
            return currentDisplayContext == .browser
        case .idle, .failed:
            return false
        }
    }

    private func resolvedActionKind(
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool
    ) -> ActionKind {
        if isDownloading || downloadRecord?.status == .queued {
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
        itemTitle: String
    ) {
        let symbolName: String
        let tintColor: NSColor
        let accessibilityLabel: String

        switch actionKind {
        case .download:
            symbolName = "square.and.arrow.down"
            tintColor = .white
            accessibilityLabel = "下载：\(itemTitle)"
        case .cancel:
            symbolName = currentBarState == .downloading ? "arrow.clockwise" : "xmark"
            tintColor = .white
            accessibilityLabel = currentBarState == .downloading
                ? "下载中：\(itemTitle)"
                : "取消下载：\(itemTitle)"
        case .setAsWallpaper:
            symbolName = "play.fill"
            tintColor = .white
            accessibilityLabel = "播放：\(itemTitle)"
        case .retry:
            symbolName = "square.and.arrow.down"
            tintColor = .white
            accessibilityLabel = "重新下载：\(itemTitle)"
        }

        statusBadgeButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )
        statusBadgeButton.iconTintColor = tintColor
        statusBadgeButton.setAccessibilityLabel(accessibilityLabel)
        updateStatusBadgeLoadingIndicator()
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
        let targetBarRadius = max(
            8,
            min(Layout.cardCornerRadius, floor((metrics.barHeight - Layout.minBarCornerInset) * 0.5))
        )
        if abs((overlayBar.layer?.cornerRadius ?? 0) - targetBarRadius) > 0.001 {
            overlayBar.layer?.cornerRadius = targetBarRadius
        }
        overlayBarShadowView.layer?.cornerRadius = targetBarRadius
        overlayBarShadowView.layer?.shadowPath = CGPath(
            roundedRect: overlayBarShadowView.bounds,
            cornerWidth: targetBarRadius,
            cornerHeight: targetBarRadius,
            transform: nil
        )
        let targetButtonRadius = max(8, min(12, Layout.cardCornerRadius - 1))
        if abs(detailButton.cornerRadius - targetButtonRadius) > 0.001 {
            detailButton.cornerRadius = targetButtonRadius
        }
        let targetBadgeRadius = prefersCircularPlayBadge
            ? floor(metrics.badgeSize * 0.5)
            : targetButtonRadius
        if abs(statusBadgeButton.cornerRadius - targetBadgeRadius) > 0.001 {
            statusBadgeButton.cornerRadius = targetBadgeRadius
        }
        if abs(titleMarqueeView.font.pointSize - metrics.titleFont.pointSize) > 0.001 {
            titleMarqueeView.font = metrics.titleFont
        }
        let overlaySymbolConfig = NSImage.SymbolConfiguration(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium)
        detailButton.contentTintColor = detailButton.iconTintColor
        detailButton.image = detailButton.image?.withSymbolConfiguration(overlaySymbolConfig)
        statusBadgeButton.image = statusBadgeButton.image?.withSymbolConfiguration(overlaySymbolConfig)
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

        hoverOutlineView.wantsLayer = true
        hoverOutlineView.layer?.cornerRadius = Layout.cardCornerRadius
        hoverOutlineView.layer?.borderWidth = 1
        hoverOutlineView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutlineView.layer?.masksToBounds = true
        hoverOutlineView.alphaValue = 0
        cardView.addSubview(hoverOutlineView)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewImageView.animates = true
        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(previewPlaceholderView)

        multiSelectBadgeView.wantsLayer = true
        multiSelectBadgeView.layer?.cornerRadius = 12
        multiSelectBadgeView.layer?.masksToBounds = true
        multiSelectBadgeView.isHidden = true
        cardView.addSubview(multiSelectBadgeView)

        multiSelectBadgeIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectBadgeIcon.contentTintColor = .white
        multiSelectBadgeIcon.imageScaling = .scaleProportionallyDown
        multiSelectBadgeIcon.isHidden = true
        multiSelectBadgeView.addSubview(multiSelectBadgeIcon)

        overlayBarShadowView.wantsLayer = true
        overlayBarShadowView.layer?.backgroundColor = NSColor.clear.cgColor
        overlayBarShadowView.layer?.shadowColor = NSColor.black.cgColor
        overlayBarShadowView.layer?.shadowOpacity = 0.16
        overlayBarShadowView.layer?.shadowRadius = 20
        overlayBarShadowView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        cardView.addSubview(overlayBarShadowView)

        overlayBar.alphaValue = 0
        overlayBar.wantsLayer = true
        cardView.addSubview(overlayBar)

        detailButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "详细信息")
        detailButton.target = self
        detailButton.action = #selector(handleOpen)
        overlayBar.addSubview(detailButton)

        overlayBar.addSubview(titleMarqueeView)

        statusBadgeButton.target = self
        statusBadgeButton.action = #selector(handleStatusAction)
        overlayBar.addSubview(statusBadgeButton)

        statusSpinner.style = .spinning
        statusSpinner.controlSize = .small
        statusSpinner.isDisplayedWhenStopped = false
        statusSpinner.isHidden = true
        overlayBar.addSubview(statusSpinner)

        refreshThemeAwareAppearance()
    }

    private func refreshThemeAwareAppearance() {
        guard let layer = cardView.layer else { return }
        let isDarkMode = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fixedForeground = isDarkMode
            ? NSColor(calibratedWhite: 1.0, alpha: 0.98)
            : NSColor(calibratedWhite: 0.08, alpha: 0.92)
        let hoverOutlineColor = NSColor.white.withAlphaComponent(isDarkMode ? 0.56 : 0.72)
        let selectedOutlineColor = NSColor.controlAccentColor.withAlphaComponent(isDarkMode ? 0.92 : 0.84)

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
        hoverOutlineView.layer?.borderColor = (isSelectionHighlighted ? selectedOutlineColor : hoverOutlineColor).cgColor
        hoverOutlineView.layer?.borderWidth = isSelectionHighlighted ? 1.6 : 1

        previewContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.14).cgColor

        let showsSelectionBadge = currentDisplayContext == .downloads && isMultiSelectMode
        multiSelectBadgeView.isHidden = !showsSelectionBadge
        if showsSelectionBadge {
            multiSelectBadgeView.layer?.backgroundColor = isSelectionHighlighted
                ? NSColor.controlAccentColor.cgColor
                : NSColor.black.withAlphaComponent(0.42).cgColor
            multiSelectBadgeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
            multiSelectBadgeView.layer?.borderWidth = isSelectionHighlighted ? 0 : 1
            multiSelectBadgeIcon.isHidden = !isSelectionHighlighted
        } else {
            multiSelectBadgeIcon.isHidden = true
        }

        overlayBar.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        overlayBar.alphaValue = currentBarVisibility ? (isHovering ? 0.92 : 0.84) : 0
        overlayBar.layer?.borderWidth = 0.8
        overlayBar.layer?.shadowOpacity = 0
        overlayBarShadowView.layer?.shadowOpacity = currentBarVisibility ? 0.11 : 0.08
        overlayBarShadowView.layer?.shadowRadius = 18
        overlayBarShadowView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        overlayBar.applyAccentStyle(barAccentStyle(for: currentBarState), animated: false)
        overlayBar.setScanAnimationEnabled(currentBarState == .downloading || currentBarState == .queued)

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
        updateStatusBadgeLoadingIndicator()
    }

    private func updateStatusBadgeLoadingIndicator() {
        let shouldSpin = currentActionKind == .cancel && currentBarState == .downloading
        if shouldSpin {
            statusBadgeButton.image = nil
            statusSpinner.isHidden = false
            statusSpinner.startAnimation(nil)
        } else {
            statusSpinner.stopAnimation(nil)
            statusSpinner.isHidden = true
        }
    }

    private func applyHoverStyle(animated: Bool) {
        let suppressDownloadsBar = currentDisplayContext == .downloads && isMultiSelectMode
        let shouldRevealBar = !suppressDownloadsBar && (isHovering || shouldPersistBarVisibility)
        let shouldShowOutline = isHovering || isSelectionHighlighted
        let targetScale: CGFloat
        if isHovering {
            targetScale = isPressingCard ? Self.pressedScale : Self.hoverScale
        } else {
            targetScale = 1.0
        }

        refreshThemeAwareAppearance()
        let cardDuration = isHovering
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let cardTiming = isHovering
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming
        let barDuration = shouldRevealBar
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let barTiming = shouldRevealBar
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardView.layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
            overlayBar.alphaValue = shouldRevealBar ? (isHovering ? 0.92 : 0.84) : 0
            overlayBar.layer?.transform = CATransform3DMakeTranslation(0, shouldRevealBar ? 0 : 4, 0)
            CATransaction.commit()
            hoverOutlineView.alphaValue = shouldShowOutline ? 1 : 0
            currentCardScale = targetScale
            currentBarVisibility = shouldRevealBar
            isHoverOutlineVisible = shouldShowOutline
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = barDuration
            context.timingFunction = barTiming
            self.cardView.animator().alphaValue = 1
            self.overlayBar.animator().alphaValue = shouldRevealBar ? (self.isHovering ? 0.92 : 0.84) : 0
            self.hoverOutlineView.animator().alphaValue = shouldShowOutline ? 1 : 0
        }

        applyCardTransform(targetScale: targetScale, duration: cardDuration, timing: cardTiming)
        applyBarTransform(isVisible: shouldRevealBar, duration: barDuration, timing: barTiming)
        currentBarVisibility = shouldRevealBar
        isHoverOutlineVisible = shouldShowOutline
    }

    private func barAccentStyle(for state: BarState) -> SteamWorkshopGlassBarView.AccentStyle {
        switch state {
        case .downloading:
            return .downloading
        case .queued:
            return .queued
        case .ready:
            return currentDisplayContext == .downloads ? .ready : .neutral
        case .idle, .failed:
            return .neutral
        }
    }

    func applyPressedState(_ pressed: Bool) {
        guard isPressingCard != pressed else { return }
        isPressingCard = pressed
        guard isHovering else { return }
        guard !(currentDisplayContext == .downloads && isMultiSelectMode) else { return }
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

    private func loadPreview(from url: URL?, fallbackVideoURL: URL?) {
        let requestURL = url ?? fallbackVideoURL
        guard currentPreviewURL != requestURL || previewImageView.image == nil else { return }
        currentPreviewURL = requestURL
        imageTask?.cancel()
        previewRetryTask?.cancel()

        if let url, url.isFileURL {
            loadLocalPreview(from: url, fallbackVideoURL: fallbackVideoURL)
            return
        }

        guard let url else {
            if let fallbackVideoURL {
                loadGeneratedDownloadPreview(from: fallbackVideoURL)
                return
            }
            previewImageView.image = nil
            previewPlaceholderView.setState(.unavailable)
            updatePreviewImageFrame()
            return
        }

        let cacheKey = steamWorkshopPreviewCacheKey(for: url)
        if !SteamWorkshopPreviewRequestCoordinator.shared.shouldBypassCachedImage(forKey: cacheKey),
           let cached = SteamWorkshopPreviewImageCache.shared.cachedOrDiskImage(forKey: cacheKey),
           !steamWorkshopPreviewImageLooksSuspicious(cached) {
            previewImageView.image = cached
            previewPlaceholderView.setState(.hidden)
            SteamWorkshopPreviewRequestCoordinator.shared.clearCachedImageSuspicion(forKey: cacheKey)
            updatePreviewImageFrame()
            return
        }
        if let cached = SteamWorkshopPreviewImageCache.shared.cachedOrDiskImage(forKey: cacheKey),
           steamWorkshopPreviewImageLooksSuspicious(cached) {
            SteamWorkshopPreviewRequestCoordinator.shared.markCachedImageSuspicious(forKey: cacheKey)
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.loading)
        updatePreviewImageFrame()
        loadPreviewImage(url: url, cacheKey: cacheKey)
    }

    private func loadLocalPreview(from localURL: URL, fallbackVideoURL: URL?) {
        if FileManager.default.fileExists(atPath: localURL.path),
           let image = NSImage(contentsOf: localURL),
           !steamWorkshopPreviewImageLooksSuspicious(image) {
            previewImageView.image = image
            previewPlaceholderView.setState(.hidden)
            updatePreviewImageFrame()
            return
        }

        if let fallbackVideoURL {
            loadGeneratedDownloadPreview(from: fallbackVideoURL)
            return
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.unavailable)
        updatePreviewImageFrame()
    }

    private func loadGeneratedDownloadPreview(from videoURL: URL) {
        if let cached = SteamWorkshopDownloadThumbnailPipeline.shared.cachedThumbnail(for: videoURL) {
            previewImageView.image = cached
            previewPlaceholderView.setState(.hidden)
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.loading)
        updatePreviewImageFrame()

        SteamWorkshopDownloadThumbnailPipeline.shared.generateThumbnail(for: videoURL) { [weak self] image in
            guard let self, self.currentPreviewURL == videoURL else { return }
            if let image {
                self.previewImageView.image = image
                self.previewPlaceholderView.setState(.hidden)
            } else {
                self.previewImageView.image = nil
                self.previewPlaceholderView.setState(.unavailable)
            }
            self.updatePreviewImageFrame()
        }
    }

    private func loadPreviewImage(url: URL, cacheKey: String) {
        if SteamWorkshopPreviewRequestCoordinator.shared.shouldBypassCachedImage(forKey: cacheKey) {
            imageTask = Task { [weak self] in
                guard let self else { return }
                let data = await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
                    from: url,
                    priority: .visible,
                    ignoringBackoff: true
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.currentPreviewURL == url else { return }
                    self.applyResolvedPreviewImage(data.flatMap(NSImage.init(data:)), url: url, cacheKey: cacheKey)
                }
            }
            return
        }

        SteamWorkshopPreviewImageCache.shared.loadImageData(forKey: cacheKey, loader: {
            SteamWorkshopPreviewRequestCoordinator.shared.loadDataSynchronously(
                from: url,
                priority: .visible
            )
        }) { [weak self] image in
            guard let self, self.currentPreviewURL == url else { return }
            self.applyResolvedPreviewImage(image, url: url, cacheKey: cacheKey)
        }
    }

    private func applyResolvedPreviewImage(_ image: NSImage?, url: URL, cacheKey: String) {
        if let image, !steamWorkshopPreviewImageLooksSuspicious(image) {
            previewImageView.image = image
            previewPlaceholderView.setState(.hidden)
            SteamWorkshopPreviewRequestCoordinator.shared.clearCachedImageSuspicion(forKey: cacheKey)
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        SteamWorkshopPreviewRequestCoordinator.shared.markCachedImageSuspicious(forKey: cacheKey)
        schedulePreviewRetry(url: url, cacheKey: cacheKey)
        updatePreviewImageFrame()
    }

    private func schedulePreviewRetry(url: URL, cacheKey: String) {
        previewRetryTask?.cancel()
        let retryDelay = SteamWorkshopPreviewRequestCoordinator.shared.nextRetryDelay(for: url, priority: .visible) ?? 2.5
        guard retryDelay < 20 else {
            previewPlaceholderView.setState(.unavailable)
            return
        }
        previewPlaceholderView.setState(.retrying)
        previewRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, retryDelay + 0.25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentPreviewURL == url else { return }
                self.previewPlaceholderView.setState(.loading)
                self.loadPreviewImage(url: url, cacheKey: cacheKey)
            }
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
            previewPlaceholderView.frame = .zero
            return
        }
        previewPlaceholderView.frame = containerBounds
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

    func setPrefersCircularPlayBadge(_ prefersCircularPlayBadge: Bool) {
        guard self.prefersCircularPlayBadge != prefersCircularPlayBadge else { return }
        self.prefersCircularPlayBadge = prefersCircularPlayBadge
        applyStatusBadgeAppearance(
            actionKind: currentActionKind,
            itemTitle: currentTitleText
        )
        if view.window != nil {
            refreshThemeAwareAppearance()
            view.needsLayout = true
        }
    }
}
