//
//  AppKitSettingsComponents.swift
//  MyWallpaperX
//

import AppKit

final class SettingsGroupView: NSView {
    private let titleLabel: NSTextField
    private let showsTitle: Bool
    private let backgroundEffectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .underPageBackground
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        view.alphaValue = 0.4
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let contentContainerView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let rowStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .gravityAreas
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var rowCount = 0

    init(title: String?) {
        let normalizedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        titleLabel = NSTextField(labelWithString: normalizedTitle)
        showsTitle = !normalizedTitle.isEmpty
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isHidden = !showsTitle

        addSubview(titleLabel)
        addSubview(backgroundEffectView)
        addSubview(contentContainerView)
        contentContainerView.addSubview(rowStack)

        var constraints: [NSLayoutConstraint] = [
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            rowStack.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ]

        if showsTitle {
            constraints.append(contentsOf: [
                titleLabel.topAnchor.constraint(equalTo: topAnchor),
                titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
                backgroundEffectView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
                contentContainerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6)
            ])
        } else {
            constraints.append(backgroundEffectView.topAnchor.constraint(equalTo: topAnchor))
            constraints.append(contentContainerView.topAnchor.constraint(equalTo: topAnchor))
        }

        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func addRow(_ row: NSView) {
        if rowCount > 0 {
            let separator = makeSeparator()
            rowStack.addArrangedSubview(separator)
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
        }
        rowStack.addArrangedSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
        rowCount += 1
    }

    private func makeSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let separator = AdaptiveSeparatorLineView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }
}

final class AdaptiveSeparatorLineView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        needsLayout = true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
    }
}
