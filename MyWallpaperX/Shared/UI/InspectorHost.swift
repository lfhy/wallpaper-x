//
//  InspectorHost.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit
import Combine

let inspectorHostAnimationDuration: Double = 0.24

enum InspectorHostUserInfoKey {
    static let module = "module"
    static let cardID = "cardID"
    static let title = "title"
    static let subtitle = "subtitle"
    static let preferredWidth = "preferredWidth"
    static let focusPolicy = "focusPolicy"
    static let chromeStyle = "chromeStyle"
    static let hostedView = "hostedView"
}

enum InspectorHostFocusPolicy: String {
    /// 打开时不主动抢占 first responder，保持浏览上下文原焦点不变。
    case preserveCurrentResponder
    /// 模块可在 inspectorDidPresent 后自行把焦点切到 inspector 内部控件。
    case moduleManaged
}

enum InspectorHostChromeStyle: String {
    case standard
    case infoPanel
}

struct InspectorCardToken: Hashable, Identifiable {
    let module: ModuleIdentifier
    let cardID: String

    var id: String {
        "\(module.rawValue):\(cardID)"
    }
}

struct InspectorHostRequest: Equatable {
    static let defaultPreferredWidth: CGFloat = 360
    static let minimumPreferredWidth: CGFloat = 300
    static let maximumPreferredWidth: CGFloat = 460

    let token: InspectorCardToken
    let title: String
    let subtitle: String?
    let preferredWidth: CGFloat
    let focusPolicy: InspectorHostFocusPolicy
    let chromeStyle: InspectorHostChromeStyle

    init(
        token: InspectorCardToken,
        title: String,
        subtitle: String? = nil,
        preferredWidth: CGFloat = InspectorHostRequest.defaultPreferredWidth,
        focusPolicy: InspectorHostFocusPolicy = .preserveCurrentResponder,
        chromeStyle: InspectorHostChromeStyle = .standard
    ) {
        self.token = token
        self.title = title
        self.subtitle = subtitle
        self.preferredWidth = min(
            max(preferredWidth, Self.minimumPreferredWidth),
            Self.maximumPreferredWidth
        )
        self.focusPolicy = focusPolicy
        self.chromeStyle = chromeStyle
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let moduleRawValue = userInfo?[InspectorHostUserInfoKey.module] as? String,
            let module = ModuleIdentifier(rawValue: moduleRawValue),
            let cardID = userInfo?[InspectorHostUserInfoKey.cardID] as? String,
            let title = userInfo?[InspectorHostUserInfoKey.title] as? String
        else {
            return nil
        }

        let subtitle = userInfo?[InspectorHostUserInfoKey.subtitle] as? String
        let preferredWidthNumber = userInfo?[InspectorHostUserInfoKey.preferredWidth] as? NSNumber
        let preferredWidth = preferredWidthNumber.map { CGFloat(truncating: $0) } ?? Self.defaultPreferredWidth
        let focusPolicyRawValue = userInfo?[InspectorHostUserInfoKey.focusPolicy] as? String
        let focusPolicy = focusPolicyRawValue.flatMap(InspectorHostFocusPolicy.init(rawValue:))
            ?? .preserveCurrentResponder
        let chromeStyleRawValue = userInfo?[InspectorHostUserInfoKey.chromeStyle] as? String
        let chromeStyle = chromeStyleRawValue.flatMap(InspectorHostChromeStyle.init(rawValue:))
            ?? .standard

        self.init(
            token: InspectorCardToken(module: module, cardID: cardID),
            title: title,
            subtitle: subtitle,
            preferredWidth: preferredWidth,
            focusPolicy: focusPolicy,
            chromeStyle: chromeStyle
        )
    }

    var userInfo: [String: Any] {
        var result: [String: Any] = [
            InspectorHostUserInfoKey.module: token.module.rawValue,
            InspectorHostUserInfoKey.cardID: token.cardID,
            InspectorHostUserInfoKey.title: title,
            InspectorHostUserInfoKey.preferredWidth: preferredWidth,
            InspectorHostUserInfoKey.focusPolicy: focusPolicy.rawValue,
            InspectorHostUserInfoKey.chromeStyle: chromeStyle.rawValue
        ]
        if let subtitle, !subtitle.isEmpty {
            result[InspectorHostUserInfoKey.subtitle] = subtitle
        }
        return result
    }
}

struct InspectorHostDismissRequest {
    let module: ModuleIdentifier?
    let cardID: String?

    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo else {
            self.module = nil
            self.cardID = nil
            return
        }

        let moduleRawValue = userInfo[InspectorHostUserInfoKey.module] as? String
        let parsedModule = moduleRawValue.flatMap(ModuleIdentifier.init(rawValue:))
        let parsedCardID = userInfo[InspectorHostUserInfoKey.cardID] as? String
        guard parsedModule != nil || parsedCardID != nil else { return nil }

        module = parsedModule
        cardID = parsedCardID
    }

    func matches(_ token: InspectorCardToken) -> Bool {
        if let module, module != token.module {
            return false
        }
        if let cardID, cardID != token.cardID {
            return false
        }
        return true
    }
}

struct InspectorHostMountRequest {
    let token: InspectorCardToken
    let hostedView: NSView

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let moduleRawValue = userInfo?[InspectorHostUserInfoKey.module] as? String,
            let module = ModuleIdentifier(rawValue: moduleRawValue),
            let cardID = userInfo?[InspectorHostUserInfoKey.cardID] as? String,
            let hostedView = userInfo?[InspectorHostUserInfoKey.hostedView] as? NSView
        else {
            return nil
        }

        token = InspectorCardToken(module: module, cardID: cardID)
        self.hostedView = hostedView
    }
}

@MainActor
final class InspectorHostStore: ObservableObject {
    @Published private(set) var currentRequest: InspectorHostRequest?
    @Published private(set) var hostedContentView: NSView?

    var isPresented: Bool {
        currentRequest != nil
    }

    func present(_ request: InspectorHostRequest) {
        if currentRequest?.token != request.token {
            hostedContentView = nil
        }
        currentRequest = request
    }

    func mountContent(_ request: InspectorHostMountRequest) {
        guard currentRequest?.token == request.token else { return }
        hostedContentView = request.hostedView
    }

    func unmountContent(for token: InspectorCardToken? = nil) {
        guard token == nil || currentRequest?.token == token else { return }
        hostedContentView = nil
    }

    func dismiss() {
        hostedContentView = nil
        currentRequest = nil
    }

    func finalizeDismiss() {
        hostedContentView = nil
        currentRequest = nil
    }
}

struct InspectorHost: View {
    @ObservedObject var store: InspectorHostStore

    var body: some View {
        Color.clear
            .overlay(alignment: .topTrailing) {
                if let request = store.currentRequest {
                    InspectorCardView(request: request, hostedContentView: store.hostedContentView)
                        .frame(width: request.preferredWidth)
                        .padding(.top, 10)
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                }
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(store.isPresented)
    }
}

private struct InspectorCardView: View {
    let request: InspectorHostRequest
    let hostedContentView: NSView?

    private var isInfoPanel: Bool {
        request.chromeStyle == .infoPanel
    }

    private var headerTitle: String {
        isInfoPanel ? "详情" : request.title
    }

    private var headerSubtitle: String? {
        isInfoPanel ? nil : request.subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if isInfoPanel {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(headerTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headerTitle)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.primary)
                        if let subtitle = headerSubtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button {
                    InspectorHostActions.postClose(
                        module: request.token.module,
                        cardID: request.token.cardID
                    )
                } label: {
                    if isInfoPanel {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
                            }
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭详情")
            }

            if let hostedContentView {
                InspectorHostedContentSlot(hostedContentView: hostedContentView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SystemGlassPanel(cornerRadius: 22, style: .regular))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 25, x: 0, y: 16)
    }
}

private struct SystemGlassPanel: NSViewRepresentable {
    let cornerRadius: CGFloat
    let style: NSGlassEffectView.Style

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.style = style
        nsView.tintColor = InspectorGlassPalette.baseTint(for: nsView)
        nsView.layer?.backgroundColor = InspectorGlassPalette.innerFill(for: nsView).cgColor
    }
}

private enum InspectorGlassPalette {
    static func baseTint(for view: NSView) -> NSColor {
        if view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .windowBackgroundColor.withAlphaComponent(0.18)
        }
        return .controlBackgroundColor.withAlphaComponent(0.15)
    }

    static func innerFill(for view: NSView) -> NSColor {
        if view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .textBackgroundColor.withAlphaComponent(0.06)
        }
        return .windowBackgroundColor.withAlphaComponent(0.05)
    }
}

private struct InspectorHostedContentSlot: NSViewRepresentable {
    let hostedContentView: NSView

    func makeNSView(context: Context) -> InspectorHostedContentContainerView {
        let container = InspectorHostedContentContainerView()
        container.hostedContentView = hostedContentView
        return container
    }

    func updateNSView(_ nsView: InspectorHostedContentContainerView, context: Context) {
        nsView.hostedContentView = hostedContentView
    }
}

private final class InspectorHostedContentContainerView: NSView {
    var hostedContentView: NSView? {
        didSet {
            guard hostedContentView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            guard let hostedContentView else { return }
            hostedContentView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostedContentView)
            NSLayoutConstraint.activate([
                hostedContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostedContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostedContentView.topAnchor.constraint(equalTo: topAnchor),
                hostedContentView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
}
