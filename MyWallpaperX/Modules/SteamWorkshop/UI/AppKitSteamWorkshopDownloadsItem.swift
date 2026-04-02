//
//  AppKitSteamWorkshopDownloadsItem.swift
//  MyWallpaperX
//

import AppKit

final class AppKitSteamWorkshopDownloadsItem: NSCollectionViewItem {
    private let cardView = NSView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let secondaryMetaLabel = NSTextField(labelWithString: "")
    private let setAsWallpaperButton = NSButton(title: "设为壁纸", target: nil, action: nil)
    private let revealButton = NSButton(title: "显示文件", target: nil, action: nil)

    private var onSetAsWallpaper: (() -> Void)?
    private var onReveal: (() -> Void)?

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
        previewImageView.image = nil
        onSetAsWallpaper = nil
        onReveal = nil
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
        setAsWallpaperButton.frame = CGRect(x: Layout.contentInset, y: buttonsY, width: Layout.buttonWidth, height: Layout.buttonHeight)
        revealButton.frame = CGRect(x: cardView.bounds.width - Layout.contentInset - Layout.buttonWidth, y: buttonsY, width: Layout.buttonWidth, height: Layout.buttonHeight)
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
        cardView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        cardView.layer?.cornerRadius = 16
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 14
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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

        setAsWallpaperButton.bezelStyle = .rounded
        setAsWallpaperButton.target = self
        setAsWallpaperButton.action = #selector(handleSetAsWallpaper)
        cardView.addSubview(setAsWallpaperButton)

        revealButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(handleReveal)
        cardView.addSubview(revealButton)
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
