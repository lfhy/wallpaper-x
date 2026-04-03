import SwiftUI
import AppKit

struct SteamWorkshopInspectorBridge: NSViewRepresentable {
    @ObservedObject var service: SteamWorkshopService

    func makeNSView(context: Context) -> SteamWorkshopInspectorBridgeAnchorView {
        let view = SteamWorkshopInspectorBridgeAnchorView()
        view.configure(service: service)
        view.scheduleSyncSelectedItem(service.selectedBrowserItem)
        return view
    }

    func updateNSView(_ nsView: SteamWorkshopInspectorBridgeAnchorView, context: Context) {
        nsView.configure(service: service)
        nsView.scheduleSyncSelectedItem(service.selectedBrowserItem)
    }
}

final class SteamWorkshopInspectorBridgeAnchorView: NSView {
    private weak var service: SteamWorkshopService?
    private var overlayHostingView: NSHostingView<SteamWorkshopItemDetailSheet>?
    private var observers: [NSObjectProtocol] = []
    private var lastRequestedCardID: String?
    private var visibleCardID: String?
    private var isInspectorVisible = false
    private var isHandlingHostClose = false
    private var pendingSyncWorkItem: DispatchWorkItem?
    private var pendingSelectedItemID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        registerObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        pendingSyncWorkItem?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func configure(service: SteamWorkshopService) {
        self.service = service
    }

    func scheduleSyncSelectedItem(_ item: SteamWorkshopBrowserItem?) {
        pendingSyncWorkItem?.cancel()
        pendingSelectedItemID = item?.id

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pendingSelectedItemID == item?.id else { return }
            self.syncSelectedItem(item)
        }
        pendingSyncWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func syncSelectedItem(_ item: SteamWorkshopBrowserItem?) {
        guard let service else { return }
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

        lastRequestedCardID = item.id
        if isInspectorVisible, visibleCardID == item.id {
            updateHostedContent(for: item)
            return
        }
        postOpenRequest(for: item, service: service)
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
            moduleRawValue == ModuleIdentifier.steamWorkshop.rawValue,
            let cardID = notification.userInfo?[InspectorHostUserInfoKey.cardID] as? String,
            let item = service?.selectedBrowserItem,
            item.id == cardID
        else {
            return
        }

        isInspectorVisible = true
        visibleCardID = cardID
        installHostedContent(for: item)
    }

    private func handleInspectorCloseRequested(_ notification: Notification) {
        let dismissRequest = InspectorHostDismissRequest(userInfo: notification.userInfo)
        if let module = dismissRequest?.module, module != .steamWorkshop {
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
            moduleRawValue == ModuleIdentifier.steamWorkshop.rawValue
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
            moduleRawValue != ModuleIdentifier.steamWorkshop.rawValue,
            service?.selectedBrowserItem != nil
        else {
            return
        }

        postCloseRequest(cardID: visibleCardID ?? lastRequestedCardID)
        clearLocalInspectorState(clearSelection: true)
    }

    private func postOpenRequest(for item: SteamWorkshopBrowserItem, service: SteamWorkshopService) {
        let subtitle = item.author.isEmpty ? service.currentPageTitle : item.author
        let userInfo: [String: Any] = [
            InspectorHostUserInfoKey.module: ModuleIdentifier.steamWorkshop.rawValue,
            InspectorHostUserInfoKey.cardID: item.id,
            InspectorHostUserInfoKey.title: item.title,
            InspectorHostUserInfoKey.subtitle: subtitle,
            InspectorHostUserInfoKey.preferredWidth: 372,
            InspectorHostUserInfoKey.focusPolicy: InspectorHostFocusPolicy.preserveCurrentResponder.rawValue
        ]
        NotificationCenter.default.post(
            name: .inspectorHostOpenRequested,
            object: nil,
            userInfo: userInfo
        )
    }

    private func postCloseRequest(cardID: String?) {
        var userInfo: [String: Any] = [
            InspectorHostUserInfoKey.module: ModuleIdentifier.steamWorkshop.rawValue
        ]
        if let cardID {
            userInfo[InspectorHostUserInfoKey.cardID] = cardID
        }
        NotificationCenter.default.post(
            name: .inspectorHostCloseRequested,
            object: nil,
            userInfo: userInfo
        )
    }

    private func installHostedContent(for item: SteamWorkshopBrowserItem) {
        let hostingView: NSHostingView<SteamWorkshopItemDetailSheet>
        if let existing = overlayHostingView {
            existing.rootView = SteamWorkshopItemDetailSheet(item: item)
            hostingView = existing
        } else {
            let created = NSHostingView(rootView: SteamWorkshopItemDetailSheet(item: item))
            overlayHostingView = created
            hostingView = created
        }

        NotificationCenter.default.post(
            name: .inspectorHostMountContentRequested,
            object: nil,
            userInfo: [
                InspectorHostUserInfoKey.module: ModuleIdentifier.steamWorkshop.rawValue,
                InspectorHostUserInfoKey.cardID: item.id,
                InspectorHostUserInfoKey.hostedView: hostingView
            ]
        )
    }

    private func updateHostedContent(for item: SteamWorkshopBrowserItem) {
        overlayHostingView?.rootView = SteamWorkshopItemDetailSheet(item: item)
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
            DispatchQueue.main.async { [weak service] in
                service?.dismissItemDetail()
            }
        }
    }
}
