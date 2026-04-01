//
//  SteamWorkshopFocusHost.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit

struct SteamWorkshopFocusHost<Content: View>: NSViewRepresentable {
    let module: ModuleIdentifier
    let content: Content

    func makeNSView(context: Context) -> SteamWorkshopFocusableContainer<Content> {
        SteamWorkshopFocusableContainer(module: module, rootView: content)
    }

    func updateNSView(_ nsView: SteamWorkshopFocusableContainer<Content>, context: Context) {
        // Keep the hosting tree stable to avoid nested publish cycles while SwiftUI is updating.
    }
}

final class SteamWorkshopFocusableContainer<Content: View>: NSView, ModuleFocusable {
    private let module: ModuleIdentifier
    private let hostingView: NSHostingView<Content>
    private var observer: NSObjectProtocol?

    init(module: ModuleIdentifier, rootView: Content) {
        self.module = module
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        observer = NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let rawModule = notification.userInfo?["module"] as? String,
                  rawModule == module.rawValue else { return }
            self.requestFocus()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func update(rootView: Content) {
        hostingView.rootView = rootView
    }

    func requestFocus() {
        window?.makeFirstResponder(self)
    }
}
