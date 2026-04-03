import SwiftUI
import AppKit

struct InspectorHostPresentation {
    let cardID: String
    let title: String
    let subtitle: String?
    let preferredWidth: CGFloat
    let focusPolicy: InspectorHostFocusPolicy
    let chromeStyle: InspectorHostChromeStyle

    init(
        cardID: String,
        title: String,
        subtitle: String? = nil,
        preferredWidth: CGFloat = InspectorHostRequest.defaultPreferredWidth,
        focusPolicy: InspectorHostFocusPolicy = .preserveCurrentResponder,
        chromeStyle: InspectorHostChromeStyle = .standard
    ) {
        self.cardID = cardID
        self.title = title
        self.subtitle = subtitle
        self.preferredWidth = preferredWidth
        self.focusPolicy = focusPolicy
        self.chromeStyle = chromeStyle
    }
}

struct InspectorHostBridge<Item, Content: View>: NSViewRepresentable {
    let module: ModuleIdentifier
    let selectedItem: Item?
    let makePresentation: (Item) -> InspectorHostPresentation
    let onSelectionCleared: () -> Void
    let content: (Item) -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(
            module: module,
            makePresentation: makePresentation,
            onSelectionCleared: onSelectionCleared,
            content: content
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.syncSelectedItem(selectedItem)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configure(
            makePresentation: makePresentation,
            onSelectionCleared: onSelectionCleared,
            content: content
        )
        context.coordinator.syncSelectedItem(selectedItem)
    }

    final class Coordinator {
        private let module: ModuleIdentifier
        private var makePresentation: (Item) -> InspectorHostPresentation
        private var onSelectionCleared: () -> Void
        private var content: (Item) -> Content
        private var overlayHostingView: NSHostingView<Content>?
        private var observers: [NSObjectProtocol] = []
        private var lastRequestedCardID: String?
        private var visibleCardID: String?
        private var isInspectorVisible = false
        private var isHandlingHostClose = false
        private var pendingSyncWorkItem: DispatchWorkItem?
        private var pendingSelectedCardID: String?
        private var latestSelectedItem: Item?

        init(
            module: ModuleIdentifier,
            makePresentation: @escaping (Item) -> InspectorHostPresentation,
            onSelectionCleared: @escaping () -> Void,
            content: @escaping (Item) -> Content
        ) {
            self.module = module
            self.makePresentation = makePresentation
            self.onSelectionCleared = onSelectionCleared
            self.content = content
            registerObservers()
        }

        deinit {
            pendingSyncWorkItem?.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func configure(
            makePresentation: @escaping (Item) -> InspectorHostPresentation,
            onSelectionCleared: @escaping () -> Void,
            content: @escaping (Item) -> Content
        ) {
            self.makePresentation = makePresentation
            self.onSelectionCleared = onSelectionCleared
            self.content = content
        }

        func syncSelectedItem(_ item: Item?) {
            pendingSyncWorkItem?.cancel()
            latestSelectedItem = item
            pendingSelectedCardID = item.map { makePresentation($0).cardID }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.pendingSelectedCardID == item.map({ self.makePresentation($0).cardID }) else { return }
                self.applySelectedItem(item)
            }
            pendingSyncWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        private func applySelectedItem(_ item: Item?) {
            if isHandlingHostClose {
                return
            }

            guard let item else {
                if let cardID = visibleCardID ?? lastRequestedCardID {
                    postCloseRequest(cardID: cardID)
                } else {
                    removeHostedContent()
                    lastRequestedCardID = nil
                    visibleCardID = nil
                }
                return
            }

            let presentation = makePresentation(item)
            lastRequestedCardID = presentation.cardID
            if isInspectorVisible, visibleCardID == presentation.cardID {
                updateHostedContent(for: item)
                return
            }
            postOpenRequest(for: item)
        }

        private func registerObservers() {
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(
                    forName: .inspectorHostDidPresent,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleInspectorDidPresent(notification)
                }
            )
            observers.append(
                center.addObserver(
                    forName: .inspectorHostDidClose,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleInspectorDidClose(notification)
                }
            )
            observers.append(
                center.addObserver(
                    forName: .inspectorHostCloseRequested,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleInspectorCloseRequested(notification)
                }
            )
            observers.append(
                center.addObserver(
                    forName: .moduleDidBecomeActive,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleModuleActivation(notification)
                }
            )
        }

        private func handleInspectorDidPresent(_ notification: Notification) {
            guard
                let moduleRawValue = notification.userInfo?[InspectorHostUserInfoKey.module] as? String,
                moduleRawValue == module.rawValue,
                let cardID = notification.userInfo?[InspectorHostUserInfoKey.cardID] as? String,
                let item = latestSelectedItem,
                makePresentation(item).cardID == cardID
            else {
                return
            }

            isInspectorVisible = true
            visibleCardID = cardID
            installHostedContent(for: item)
        }

        private func handleInspectorCloseRequested(_ notification: Notification) {
            let dismissRequest = InspectorHostDismissRequest(userInfo: notification.userInfo)
            if let requestedModule = dismissRequest?.module, requestedModule != module {
                return
            }

            if let visibleCardID, dismissRequest?.cardID == nil || dismissRequest?.cardID == visibleCardID {
                isInspectorVisible = false
                self.visibleCardID = nil
            }
        }

        private func handleInspectorDidClose(_ notification: Notification) {
            guard
                let moduleRawValue = notification.userInfo?[InspectorHostUserInfoKey.module] as? String,
                moduleRawValue == module.rawValue
            else {
                return
            }

            isHandlingHostClose = true
            defer { isHandlingHostClose = false }

            clearLocalInspectorState(clearSelection: true)
        }

        private func handleModuleActivation(_ notification: Notification) {
            guard
                let moduleRawValue = notification.userInfo?["module"] as? String,
                moduleRawValue != module.rawValue,
                latestSelectedItem != nil
            else {
                return
            }

            postCloseRequest(cardID: visibleCardID ?? lastRequestedCardID)
            clearLocalInspectorState(clearSelection: true)
        }

        private func postOpenRequest(for item: Item) {
            let presentation = makePresentation(item)
            InspectorHostActions.postOpen(module: module, presentation: presentation)
        }

        private func postCloseRequest(cardID: String?) {
            InspectorHostActions.postClose(module: module, cardID: cardID)
        }

        private func installHostedContent(for item: Item) {
            let hostingView: NSHostingView<Content>
            if let existing = overlayHostingView {
                existing.rootView = content(item)
                hostingView = existing
            } else {
                let created = NSHostingView(rootView: content(item))
                overlayHostingView = created
                hostingView = created
            }

            InspectorHostActions.postMount(
                module: module,
                cardID: makePresentation(item).cardID,
                hostedView: hostingView
            )
        }

        private func updateHostedContent(for item: Item) {
            overlayHostingView?.rootView = content(item)
            installHostedContent(for: item)
        }

        private func removeHostedContent() {
            overlayHostingView?.removeFromSuperview()
            overlayHostingView = nil
        }

        private func clearLocalInspectorState(clearSelection: Bool) {
            isInspectorVisible = false
            visibleCardID = nil
            lastRequestedCardID = nil
            removeHostedContent()
            if clearSelection {
                DispatchQueue.main.async { [onSelectionCleared] in
                    onSelectionCleared()
                }
            }
        }
    }
}

extension View {
    func inspectorHostBridge<Item, HostedContent: View>(
        module: ModuleIdentifier,
        selectedItem: Item?,
        makePresentation: @escaping (Item) -> InspectorHostPresentation,
        onSelectionCleared: @escaping () -> Void,
        @ViewBuilder content: @escaping (Item) -> HostedContent
    ) -> some View {
        background(
            InspectorHostBridge(
                module: module,
                selectedItem: selectedItem,
                makePresentation: makePresentation,
                onSelectionCleared: onSelectionCleared,
                content: content
            )
        )
    }
}
