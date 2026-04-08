//
//  AppKitMainSplitView.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit

private let inspectorHostSlideInTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.12, 0.32, 1.0)
private let inspectorHostSlideOutTiming = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.22, 1.0)

struct AppKitMainSplitView: NSViewControllerRepresentable {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Binding var selectedItem: SelectedItem

    func makeNSViewController(context: Context) -> AppKitMainSplitViewController {
        let controller = AppKitMainSplitViewController()
        controller.update(
            wallpaperManager: wallpaperManager,
            selectedItem: bindingForSelection()
        )
        return controller
    }

    func updateNSViewController(_ nsViewController: AppKitMainSplitViewController, context: Context) {
        nsViewController.update(
            wallpaperManager: wallpaperManager,
            selectedItem: bindingForSelection()
        )
    }

    private func bindingForSelection() -> Binding<SelectedItem> {
        Binding(
            get: { selectedItem },
            set: { selectedItem = $0 }
        )
    }
}

private struct SidebarRootView: View {
    @ObservedObject var wallpaperManager: WallpaperManager
    @Binding var selectedItem: SelectedItem

    var body: some View {
        AppKitSidebarView(selectedItem: $selectedItem)
            .environmentObject(wallpaperManager)
            .ignoresSafeArea(.container, edges: .top)
    }
}

private struct DetailRootView: View {
    @ObservedObject var wallpaperManager: WallpaperManager
    @Binding var selectedItem: SelectedItem

    var body: some View {
        DetailView(selectedItem: $selectedItem)
            .environmentObject(wallpaperManager)
            .ignoresSafeArea(.container, edges: .top)
    }
}

final class AppKitMainSplitViewController: NSSplitViewController {
    private enum LayoutConstants {
        static let defaultSidebarWidth: CGFloat = 220
        static let splitAutosaveName = "MainSplitViewV2"
        static let splitAutosaveFramesKeyPrefix = "NSSplitView Subview Frames "
    }

    private let sidebarController = NSHostingController(
        rootView: SidebarRootView(
            wallpaperManager: .shared,
            selectedItem: .constant(.category(.myWallpapers))
        )
    )
    private let detailHostingController = NSHostingController(
        rootView: DetailRootView(
            wallpaperManager: .shared,
            selectedItem: .constant(.category(.myWallpapers))
        )
    )
    private let inspectorStore = InspectorHostStore()
    private let inspectorController = NSHostingController(
        rootView: InspectorHost(store: InspectorHostStore())
    )
    private lazy var detailContainerController = InspectorDetailContainerViewController(
        contentController: detailHostingController,
        overlayController: inspectorController
    )
    private var hasConfiguredSplitItems = false
    private var sidebarMinWidth: CGFloat = 200
    private var sidebarMaxWidth: CGFloat = 320
    private var currentManagerIdentity: ObjectIdentifier?
    private var currentSelectedItem: SelectedItem?
    private var notificationObservers: [NSObjectProtocol] = []
    private weak var preservedFirstResponder: NSResponder?
    private var inspectorTransitionGeneration = 0
    init() {
        super.init(nibName: nil, bundle: nil)
        inspectorController.rootView = InspectorHost(store: inspectorStore)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func update(wallpaperManager: WallpaperManager, selectedItem: Binding<SelectedItem>) {
        if !hasConfiguredSplitItems {
            configureSplitItems()
        }

        let managerIdentity = ObjectIdentifier(wallpaperManager)
        let selectedValue = selectedItem.wrappedValue
        // 这里只在 manager 实例变化或首次绑定时重绑，避免选中态变化触发整棵侧边栏/详情树重建。
        let shouldRebindRootViews = currentManagerIdentity != managerIdentity || currentSelectedItem != selectedValue
        guard shouldRebindRootViews else { return }

        currentManagerIdentity = managerIdentity
        currentSelectedItem = selectedValue

        sidebarController.rootView = SidebarRootView(
            wallpaperManager: wallpaperManager,
            selectedItem: selectedItem
        )
        detailHostingController.rootView = DetailRootView(
            wallpaperManager: wallpaperManager,
            selectedItem: selectedItem
        )
    }

    private func configureSplitItems() {
        hasConfiguredSplitItems = true
        guard splitViewItems.isEmpty else { return }

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = sidebarMinWidth
        sidebarItem.maximumThickness = sidebarMaxWidth
        sidebarItem.preferredThicknessFraction = 0.22
        sidebarItem.canCollapse = false
        sidebarItem.isCollapsed = false
        sidebarItem.allowsFullHeightLayout = true

        let detailItem = NSSplitViewItem(viewController: detailContainerController)
        detailItem.allowsFullHeightLayout = false

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = LayoutConstants.splitAutosaveName
        configureInspectorHostIfNeeded()
        configureInspectorNotificationObserversIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.splitView.subviews.count >= 2 else { return }
            if self.splitViewItems.count > 0 {
                self.splitViewItems[0].isCollapsed = false
            }
            self.applyInitialSidebarWidthIfNeeded()
        }
    }

    private func applyInitialSidebarWidthIfNeeded() {
        let autosaveFramesKey = LayoutConstants.splitAutosaveFramesKeyPrefix + LayoutConstants.splitAutosaveName
        let hasAutosavedFrames = UserDefaults.standard.object(forKey: autosaveFramesKey) != nil
        guard !hasAutosavedFrames else { return }
        splitView.setPosition(LayoutConstants.defaultSidebarWidth, ofDividerAt: 0)
    }

    private func configureInspectorHostIfNeeded() {
        detailContainerController.installOverlayIfNeeded()
        applyInspectorVisibility(isVisible: false, panelWidth: 0)
    }

    private func configureInspectorNotificationObserversIfNeeded() {
        guard notificationObservers.isEmpty else { return }

        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: .inspectorHostOpenRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleInspectorOpen(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .inspectorHostCloseRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleInspectorClose(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .inspectorHostMountContentRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleInspectorMountContent(notification)
            }
        )
    }

    private func handleInspectorOpen(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo) else { return }
        inspectorTransitionGeneration += 1

        if inspectorStore.currentRequest == nil {
            preservedFirstResponder = view.window?.firstResponder
        }

        inspectorStore.present(request)
        applyInspectorVisibility(isVisible: true, panelWidth: request.preferredWidth)
        NotificationCenter.default.post(
            name: .inspectorHostDidPresent,
            object: nil,
            userInfo: request.userInfo
        )
    }

    private func handleInspectorClose(_ notification: Notification) {
        guard let currentRequest = inspectorStore.currentRequest else { return }

        let dismissRequest = InspectorHostDismissRequest(userInfo: notification.userInfo)
        if let dismissRequest, !dismissRequest.matches(currentRequest.token) {
            return
        }

        inspectorTransitionGeneration += 1
        let transitionGeneration = inspectorTransitionGeneration
        applyInspectorVisibility(isVisible: false, panelWidth: currentRequest.preferredWidth) { [weak self] in
            guard let self else { return }
            guard self.inspectorTransitionGeneration == transitionGeneration else { return }
            self.inspectorStore.finalizeDismiss()
            NotificationCenter.default.post(
                name: .inspectorHostDidClose,
                object: nil,
                userInfo: currentRequest.userInfo
            )
            self.restoreFirstResponder(afterClosing: currentRequest)
        }
    }

    private func handleInspectorMountContent(_ notification: Notification) {
        guard let request = InspectorHostMountRequest(userInfo: notification.userInfo) else { return }
        inspectorStore.mountContent(request)
    }

    private func applyInspectorVisibility(
        isVisible: Bool,
        panelWidth: CGFloat,
        completion: (() -> Void)? = nil
    ) {
        detailContainerController.setOverlayVisible(
            isVisible,
            panelWidth: panelWidth,
            panelOffset: panelWidth + 48,
            completion: completion
        )
    }

    private func restoreFirstResponder(afterClosing request: InspectorHostRequest) {
        defer { preservedFirstResponder = nil }

        guard let window = view.window else { return }
        if let responder = preservedFirstResponder {
            switch responder {
            case let responderView as NSView where responderView.window === window:
                window.makeFirstResponder(responderView)
                return
            case let textView as NSTextView where textView.window === window:
                window.makeFirstResponder(textView)
                return
            default:
                break
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.post(
                name: .moduleDidBecomeActive,
                object: nil,
                userInfo: ["module": request.token.module.rawValue]
            )
        }
    }
}

private final class InspectorDetailContainerViewController: NSViewController {
    private let contentController: NSViewController
    private let overlayController: NSViewController
    private let overlayView = InspectorOverlayPassthroughView()
    private let overlayAnimationHostView = NSView()
    private var didInstallOverlay = false
    private var pendingOverlayHideWorkItem: DispatchWorkItem?
    private var overlayTrailingConstraint: NSLayoutConstraint?
    private var overlayWidthConstraint: NSLayoutConstraint?

    init(contentController: NSViewController, overlayController: NSViewController) {
        self.contentController = contentController
        self.overlayController = overlayController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installContentIfNeeded()
        installOverlayIfNeeded()
        setOverlayVisible(false, panelWidth: 0, panelOffset: 0, animated: false)
    }

    func installOverlayIfNeeded() {
        guard !didInstallOverlay else { return }
        didInstallOverlay = true

        addChild(overlayController)
        let inspectorView = overlayController.view
        inspectorView.translatesAutoresizingMaskIntoConstraints = false
        inspectorView.wantsLayer = true
        inspectorView.layer?.backgroundColor = NSColor.clear.cgColor

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor

        overlayAnimationHostView.translatesAutoresizingMaskIntoConstraints = false
        overlayAnimationHostView.wantsLayer = true
        overlayAnimationHostView.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(overlayView)
        overlayView.addSubview(overlayAnimationHostView)
        overlayAnimationHostView.addSubview(inspectorView)

        let trailingConstraint = overlayAnimationHostView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor)
        let widthConstraint = overlayAnimationHostView.widthAnchor.constraint(equalToConstant: 0)
        overlayTrailingConstraint = trailingConstraint
        overlayWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            widthConstraint,
            overlayAnimationHostView.topAnchor.constraint(equalTo: overlayView.topAnchor),
            overlayAnimationHostView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor),
            trailingConstraint,
            inspectorView.leadingAnchor.constraint(equalTo: overlayAnimationHostView.leadingAnchor),
            inspectorView.trailingAnchor.constraint(equalTo: overlayAnimationHostView.trailingAnchor),
            inspectorView.topAnchor.constraint(equalTo: overlayAnimationHostView.topAnchor),
            inspectorView.bottomAnchor.constraint(equalTo: overlayAnimationHostView.bottomAnchor)
        ])
    }

    func setOverlayVisible(
        _ isVisible: Bool,
        panelWidth: CGFloat,
        panelOffset: CGFloat,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        pendingOverlayHideWorkItem?.cancel()
        pendingOverlayHideWorkItem = nil

        guard let overlayTrailingConstraint, let overlayWidthConstraint else {
            completion?()
            return
        }

        let hostWidth = max(0, panelWidth + 24)

        if isVisible {
            overlayView.isHidden = false
            overlayController.view.isHidden = false
            overlayAnimationHostView.isHidden = false
            overlayView.isActive = true
            overlayWidthConstraint.constant = hostWidth
            overlayTrailingConstraint.constant = panelOffset
            view.needsLayout = true

            let animations = {
                overlayTrailingConstraint.animator().constant = 0
                self.view.needsLayout = true
            }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = inspectorHostAnimationDuration
                    context.timingFunction = inspectorHostSlideInTiming
                    animations()
                } completionHandler: {
                    completion?()
                }
            } else {
                overlayTrailingConstraint.constant = 0
                view.needsLayout = true
                completion?()
            }
            return
        }

        overlayView.isActive = false
        let finishHide = { [weak self] in
            guard let self else { return }
            self.overlayView.isHidden = true
            self.overlayController.view.isHidden = true
            self.overlayAnimationHostView.isHidden = true
            overlayWidthConstraint.constant = 0
            self.pendingOverlayHideWorkItem = nil
            completion?()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = inspectorHostAnimationDuration
                context.timingFunction = inspectorHostSlideOutTiming
                overlayTrailingConstraint.animator().constant = panelOffset
                view.needsLayout = true
            } completionHandler: {
                finishHide()
            }
        } else {
            overlayTrailingConstraint.constant = panelOffset
            view.needsLayout = true
            finishHide()
        }
    }

    private func installContentIfNeeded() {
        guard contentController.parent == nil else { return }
        addChild(contentController)
        let contentView = contentController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

private final class InspectorOverlayPassthroughView: NSView {
    var isActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActive else { return nil }
        let hitView = super.hitTest(point)
        return hitView === self ? self : hitView
    }

    override func mouseDown(with event: NSEvent) {
        guard isActive else {
            super.mouseDown(with: event)
            return
        }

        NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isActive else {
            super.scrollWheel(with: event)
            return
        }

        NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
        nextResponder?.scrollWheel(with: event)
    }
}
