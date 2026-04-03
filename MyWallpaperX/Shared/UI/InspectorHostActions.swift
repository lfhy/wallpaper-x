import SwiftUI
import AppKit

enum InspectorHostActions {
    static func postOpen(module: ModuleIdentifier, presentation: InspectorHostPresentation) {
        NotificationCenter.default.post(
            name: .inspectorHostOpenRequested,
            object: nil,
            userInfo: [
                InspectorHostUserInfoKey.module: module.rawValue,
                InspectorHostUserInfoKey.cardID: presentation.cardID,
                InspectorHostUserInfoKey.title: presentation.title,
                InspectorHostUserInfoKey.subtitle: presentation.subtitle as Any,
                InspectorHostUserInfoKey.preferredWidth: presentation.preferredWidth,
                InspectorHostUserInfoKey.focusPolicy: presentation.focusPolicy.rawValue,
                InspectorHostUserInfoKey.chromeStyle: presentation.chromeStyle.rawValue
            ].compactMapValues { $0 }
        )
    }

    static func postClose(module: ModuleIdentifier? = nil, cardID: String? = nil) {
        let userInfo = [
            InspectorHostUserInfoKey.module: module?.rawValue,
            InspectorHostUserInfoKey.cardID: cardID
        ].compactMapValues { $0 }

        NotificationCenter.default.post(
            name: .inspectorHostCloseRequested,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }

    static func postMount(module: ModuleIdentifier, cardID: String, hostedView: NSView) {
        NotificationCenter.default.post(
            name: .inspectorHostMountContentRequested,
            object: nil,
            userInfo: [
                InspectorHostUserInfoKey.module: module.rawValue,
                InspectorHostUserInfoKey.cardID: cardID,
                InspectorHostUserInfoKey.hostedView: hostedView
            ]
        )
    }
}

extension InspectorHostPresentation {
    static func standard(
        cardID: String,
        title: String,
        subtitle: String? = nil,
        preferredWidth: CGFloat = InspectorHostRequest.defaultPreferredWidth,
        focusPolicy: InspectorHostFocusPolicy = .preserveCurrentResponder
    ) -> InspectorHostPresentation {
        InspectorHostPresentation(
            cardID: cardID,
            title: title,
            subtitle: subtitle,
            preferredWidth: preferredWidth,
            focusPolicy: focusPolicy,
            chromeStyle: .standard
        )
    }

    static func infoPanel(
        cardID: String,
        title: String,
        subtitle: String? = nil,
        preferredWidth: CGFloat = InspectorHostRequest.defaultPreferredWidth,
        focusPolicy: InspectorHostFocusPolicy = .preserveCurrentResponder
    ) -> InspectorHostPresentation {
        InspectorHostPresentation(
            cardID: cardID,
            title: title,
            subtitle: subtitle,
            preferredWidth: preferredWidth,
            focusPolicy: focusPolicy,
            chromeStyle: .infoPanel
        )
    }
}

private struct InspectorHostAutoCloseModifier: ViewModifier {
    let module: ModuleIdentifier
    let onDisappearAction: (() -> Void)?

    func body(content: Content) -> some View {
        content.onDisappear {
            InspectorHostActions.postClose(module: module)
            onDisappearAction?()
        }
    }
}

extension View {
    func inspectorHostAutoClose(
        module: ModuleIdentifier,
        onDisappear: (() -> Void)? = nil
    ) -> some View {
        modifier(InspectorHostAutoCloseModifier(module: module, onDisappearAction: onDisappear))
    }
}
