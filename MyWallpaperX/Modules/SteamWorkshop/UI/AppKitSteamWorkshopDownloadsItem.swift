//
//  AppKitSteamWorkshopDownloadsItem.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

final class AppKitSteamWorkshopDownloadsItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.03
    private let cardView = AppearanceAwareContainerView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let secondaryMetaLabel = NSTextField(labelWithString: "")
    private let setAsWallpaperButton = NSButton(title: "设为壁纸", target: nil, action: nil)
    private let revealButton = NSButton(title: "显示文件", target: nil, action: nil)

    private var onSetAsWallpaper: (() -> Void)?
    private var onReveal: (() -> Void)?
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
        previewImageView.image = nil
        onSetAsWallpaper = nil
        onReveal = nil
        isHovering = false
        currentCardScale = 1.0
        cardView.layer?.transform = CATransform3DIdentity
        refreshThemeAwareAppearance()
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
        setAsWallpaperButton.frame = CGRect(x: buttonsStartX, y: buttonsY, width: buttonWidth, height: buttonHeight)
        revealButton.frame = CGRect(
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

    func configure(
        record: SteamWorkshopDownloadRecord,
        onSetAsWallpaper: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) {
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onReveal = onReveal

        titleLabel.stringValue = record.title
        metaLabel.stringValue = record.id
        secondaryMetaLabel.stringValue = [record.sizeText, record.statusText].joined(separator: "  ·  ")

        setAsWallpaperButton.isEnabled = record.videoURL != nil

        if let previewURL = record.previewURL,
           let image = NSImage(contentsOf: previewURL) {
            previewImageView.image = image
            previewImageView.imageScaling = .scaleAxesIndependently
        } else {
            previewImageView.image = nil
            previewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    private func buildHierarchy() {
        view.wantsLayer = true

        cardView.wantsLayer = true
        cardView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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
        previewContainer.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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

        setAsWallpaperButton.bezelStyle = .rounded
        setAsWallpaperButton.target = self
        setAsWallpaperButton.action = #selector(handleSetAsWallpaper)
        cardView.addSubview(setAsWallpaperButton)

        revealButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(handleReveal)
        cardView.addSubview(revealButton)

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
        layer.borderColor = (isHovering
            ? NSColor.controlAccentColor.withAlphaComponent(0.30)
            : NSColor.separatorColor.withAlphaComponent(0.22)).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = isHovering ? 0.14 : 0.04
        layer.shadowRadius = isHovering ? 10 : 6
        layer.shadowOffset = CGSize(width: 0, height: -1)
        previewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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

    @objc private func handleSetAsWallpaper() {
        onSetAsWallpaper?()
    }

    @objc private func handleReveal() {
        onReveal?()
    }
}
