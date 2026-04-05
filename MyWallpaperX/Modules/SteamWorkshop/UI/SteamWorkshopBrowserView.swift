//
//  SteamWorkshopBrowserView.swift
//  MyWallpaperX
//

import SwiftUI
import AVKit
import AppKit
import CoreGraphics

enum SteamWorkshopPreviewImageCache {
    static let shared = ThumbnailCache(
        label: "com.songziqiang.MyWallpaperX.steamworkshop.preview.decode",
        countLimit: 320
    )
}

func steamWorkshopPreviewCacheKey(for url: URL) -> String {
    let host = (url.host ?? "").lowercased()
    let normalizedPath: String = {
        let path = url.path.isEmpty ? "/" : url.path
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }()

    // Steam 预览图常见差异只在 query（如 imw=200 / imw=512），底图 path 相同。
    // 对 steamusercontent 的 ugc 资源统一按 host + path 建缓存键，避免不同尺寸参数重复下载。
    if host.hasSuffix("steamusercontent.com"),
       normalizedPath.contains("/ugc/") {
        return "steam-preview:\(host)\(normalizedPath)"
    }

    return "steam-preview:\(url.absoluteString)"
}

func steamWorkshopPreviewImageLooksSuspicious(_ image: NSImage) -> Bool {
    guard image.size.width > 0, image.size.height > 0 else { return true }
    if image.size.width <= 4 || image.size.height <= 4 {
        return true
    }
    if steamWorkshopPreviewImageIsAnimated(image) {
        return false
    }
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return false
    }

    let sampleWidth = 8
    let sampleHeight = 8
    var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
    guard let context = CGContext(
        data: &pixels,
        width: sampleWidth,
        height: sampleHeight,
        bitsPerComponent: 8,
        bytesPerRow: sampleWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return false
    }

    context.interpolationQuality = .low
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

    var luminances: [CGFloat] = []
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = CGFloat(pixels[index + 3]) / 255.0
        guard alpha > 0.05 else { continue }
        let red = CGFloat(pixels[index]) / 255.0
        let green = CGFloat(pixels[index + 1]) / 255.0
        let blue = CGFloat(pixels[index + 2]) / 255.0
        luminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    }

    guard !luminances.isEmpty else { return true }
    let minLuma = luminances.min() ?? 0
    let maxLuma = luminances.max() ?? 0
    let meanLuma = luminances.reduce(0, +) / CGFloat(luminances.count)
    return meanLuma < 0.03 && (maxLuma - minLuma) < 0.025
}

private func steamWorkshopPreviewImageIsAnimated(_ image: NSImage) -> Bool {
    image.representations.contains { representation in
        guard let bitmap = representation as? NSBitmapImageRep else { return false }
        let frameCount = bitmap.value(forProperty: .frameCount) as? Int ?? 1
        return frameCount > 1
    }
}

public struct SteamWorkshopEntryView: View {
    public init() {}

    public var body: some View {
        SteamWorkshopBrowserContentView()
    }
}

private struct SteamWorkshopBrowserContentView: View {
    @ObservedObject private var service = SteamWorkshopService.shared

    var body: some View {
        content
        .task {
            service.prepareForBrowserEntry()
        }
        .inspectorHostBridge(
            module: .steamWorkshop,
            selectedItem: service.selectedBrowserItem,
            makePresentation: { item in
                let subtitle = item.author.isEmpty ? service.currentPageTitle : item.author
                return .infoPanel(
                    cardID: item.id,
                    title: item.title,
                    subtitle: subtitle,
                    preferredWidth: 356,
                    focusPolicy: .preserveCurrentResponder
                )
            },
            onSelectionCleared: {
                service.dismissItemDetail()
            },
            content: { item in
                SteamWorkshopItemDetailSheet(item: item)
            }
        )
        .inspectorHostAutoClose(module: .steamWorkshop) {
            service.dismissItemDetail()
        }
        .overlay {
            if service.isLoginSheetPresented {
                SteamWorkshopLoginOverlay()
                    .transition(.opacity.animation(.easeOut(duration: 0.16)))
            }
        }
        .alert("下载失败", isPresented: Binding(
            get: { service.downloadError != nil },
            set: { if !$0 { service.downloadError = nil } }
        )) {
            Button("确定", role: .cancel) {
                service.downloadError = nil
            }
        } message: {
            Text(service.downloadError ?? "")
        }
        .alert("Steam 登录失败", isPresented: Binding(
            get: { service.authError != nil },
            set: { if !$0 { service.authError = nil } }
        )) {
            Button("确定", role: .cancel) {
                service.authError = nil
            }
        } message: {
            Text(service.authError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.browserState {
        case .idle, .loading:
            SteamWorkshopBrowserLoadingView(
                text: service.isBrowsingAuthorWorkshop
                    ? "正在抓取 \(service.activeAuthorWorkshopName ?? "作者") 的工坊列表…"
                    : "正在抓取创意工坊视频列表…"
            )
        case .failed(let message):
            SteamWorkshopBrowserErrorView(
                title: service.isBrowsingAuthorWorkshop ? "抓取作者工坊信息失败" : "抓取创意工坊信息失败",
                message: message
            ) {
                service.refresh()
            }
        case .loaded:
            if !service.hasVisibleBrowserItems {
                SteamWorkshopBrowserEmptyView(
                    message: emptyStateMessage
                )
            } else {
                ZStack(alignment: .bottom) {
                    AppKitSteamWorkshopBrowserGridView(
                        service: service,
                        onOpen: { item in
                            service.presentItemDetail(item)
                        },
                        onAuthor: { item in
                            service.showAuthorWorkshop(for: item)
                        },
                        onDownload: { item in
                            service.downloadWorkshopItem(id: item.id, pageTitle: item.title)
                        },
                        onSetAsWallpaper: { record in
                            service.setAsWallpaper(record)
                        },
                        onCancelDownload: { item in
                            service.cancelDownload(itemID: item.id)
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyStateMessage: String {
        let trimmedQuery = service.browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if service.isBrowsingAuthorWorkshop,
           !trimmedQuery.isEmpty,
           !service.browserItems.isEmpty {
            return "当前搜索没有匹配到作者作品"
        }
        return service.isBrowsingAuthorWorkshop
                        ? "\(service.activeAuthorWorkshopName ?? "该作者") 当前没有抓取到视频项目"
                        : "当前条件下没有抓取到视频项目"
    }
}

struct SteamWorkshopLoginOverlay: View {
    @ObservedObject private var service = SteamWorkshopService.shared

    var body: some View {
        ZStack {
            SteamWorkshopLoginSheet()
                .padding(28)
                .offset(x: -95)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(1000)
    }
}

private struct SteamWorkshopLoginSheet: View {
    @ObservedObject private var service = SteamWorkshopService.shared
    @Environment(\.colorScheme) private var colorScheme

    private var pendingDownloadTitle: String? {
        if let pageTitle = service.pendingDownloadRequest?.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pageTitle.isEmpty {
            return pageTitle
        }
        if let pending = service.pendingDownloadRequest {
            return "Workshop #\(pending.id)"
        }
        return nil
    }

    private var isAwaitingGuard: Bool {
        service.authPhase == .awaitingGuardCode
    }

    private var titleText: String {
        isAwaitingGuard ? "继续完成 Steam 验证" : "登录 Steam 以启用创意工坊下载"
    }

    private var subtitleText: String {
        if isAwaitingGuard {
            return "账号密码已经提交成功，继续输入 Steam Guard 令牌即可完成这次登录。"
        }
        return service.authStatusMessage
    }

    private var footnoteText: String {
        isAwaitingGuard
        ? "这里是在续接当前登录流程，不会重新提交账号密码。"
        : "已保存凭据时，下载前会先验证当前会话；只有会话失效时才会要求继续登录或输入 Guard。"
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : Color.black.opacity(0.80)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color.black.opacity(0.58)
    }

    private var chromeStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.20) : .white.opacity(0.52)
    }

    private var panelOverlayColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 58, height: 58)
                    Circle()
                        .stroke(chromeStrokeColor, lineWidth: 0.8)
                        .frame(width: 58, height: 58)
                    Image(systemName: isAwaitingGuard ? "shield.lefthalf.filled.badge.checkmark" : "person.crop.circle.badge.plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(primaryTextColor)
                }

                SteamWorkshopLoginModeBadge(
                    title: isAwaitingGuard ? "Steam Guard 验证" : "Steam 账号登录",
                    systemImage: isAwaitingGuard ? "lock.shield" : "sparkles.rectangle.stack"
                )

                Text(titleText)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .multilineTextAlignment(.center)

                Text(subtitleText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                if let pendingDownloadTitle {
                    SteamWorkshopLoginCallout(
                        icon: "arrow.down.circle.fill",
                        text: "登录成功后会自动继续下载：\(pendingDownloadTitle)"
                    )
                }
            }

            Group {
                if isAwaitingGuard {
                    SteamWorkshopLoginField(
                        title: "Steam Guard 令牌",
                        prompt: "请输入邮件或手机 App 收到的令牌",
                        text: $service.steamGuardCode,
                        systemImage: "lock.shield"
                    )
                } else {
                    VStack(spacing: 12) {
                        SteamWorkshopLoginField(
                            title: "Steam 用户名",
                            prompt: "请输入用户名",
                            text: $service.steamUsername,
                            systemImage: "person"
                        )
                        SteamWorkshopSecureLoginField(
                            title: "Steam 密码",
                            prompt: "请输入密码",
                            text: $service.steamPassword,
                            systemImage: "key"
                        )
                    }
                }
            }
            .frame(maxWidth: 320)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    if isAwaitingGuard {
                        Button(service.isAuthenticating ? "验证中…" : "验证令牌") {
                            service.submitSteamGuardCode()
                        }
                        .buttonStyle(SteamWorkshopLoginActionButtonStyle(kind: .primary))
                        .disabled(service.isAuthenticating)
                    } else {
                        Button(service.isPreparingRuntime ? "准备中…" : (service.isAuthenticating ? "登录中…" : "发送登录请求")) {
                            service.authenticateUser()
                        }
                        .buttonStyle(SteamWorkshopLoginActionButtonStyle(kind: .primary))
                        .disabled(service.isAuthenticating || service.isPreparingRuntime)
                    }

                    Button("关闭") {
                        service.isLoginSheetPresented = false
                    }
                    .buttonStyle(SteamWorkshopLoginActionButtonStyle(kind: .secondary))
                }
            }
            .frame(maxWidth: 320)

            SteamWorkshopLoginFootnote(text: footnoteText)
                .frame(maxWidth: 360)
        }
        .frame(minWidth: 380, minHeight: 500)
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
        .frame(width: 390)
        .background {
            SteamWorkshopInspectorGlassPanel(cornerRadius: 22, style: .regular)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(panelOverlayColor)
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.42 : 0.62),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .padding(1)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.08)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 25, x: 0, y: 16)
        .background(Color.clear)
    }
}

private struct SteamWorkshopLoginModeBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                    )
            )
    }
}

private struct SteamWorkshopLoginCallout: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.88))
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.88))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                )
        )
    }
}

private struct SteamWorkshopLoginField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack {
                if text.isEmpty && !isFocused {
                    Text(prompt)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.36))
                        .allowsHitTesting(false)
                }

                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary.opacity(0.94))
                    .focused($isFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fieldFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
            )
        }
    }

    private var fieldFillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.11) : Color.white.opacity(0.24)
    }
}

private struct SteamWorkshopSecureLoginField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack {
                if text.isEmpty && !isFocused {
                    Text(prompt)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.36))
                        .allowsHitTesting(false)
                }

                SecureField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary.opacity(0.94))
                    .focused($isFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.11) : Color.white.opacity(0.24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
            )
        }
    }
}

private struct SteamWorkshopLoginFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
    }
}

private enum SteamWorkshopLoginActionKind {
    case primary
    case secondary
}

private struct SteamWorkshopLoginActionButtonStyle: ButtonStyle {
    let kind: SteamWorkshopLoginActionKind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foregroundColor.opacity(isEnabled ? 1 : 0.55))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(background(configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor.opacity(isEnabled ? 1 : 0.45), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.72)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return Color(nsColor: .labelColor)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return Color(nsColor: .systemBlue).opacity(0.42)
        case .secondary:
            return Color.white.opacity(0.16)
        }
    }

    @ViewBuilder
    private func background(_ isPressed: Bool) -> some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: isPressed ? .systemBlue.withSystemEffect(.pressed) : .systemBlue))
        case .secondary:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark
                    ? Color.black.opacity(isPressed ? 0.15 : 0.11)
                    : Color.white.opacity(isPressed ? 0.28 : 0.36))
        }
    }
}

private struct SteamWorkshopInspectorGlassPanel: NSViewRepresentable {
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
        nsView.tintColor = SteamWorkshopInspectorGlassPalette.baseTint(for: nsView)
        nsView.layer?.backgroundColor = SteamWorkshopInspectorGlassPalette.innerFill(for: nsView).cgColor
    }
}

private enum SteamWorkshopInspectorGlassPalette {
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

private struct SteamWorkshopBrowserLoadingView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct SteamWorkshopBrowserErrorView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct SteamWorkshopBrowserEmptyView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}


private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            self.generateContent(in: proxy)
        }
        .frame(minHeight: 40)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            content
                .padding(.trailing, spacing)
                .padding(.bottom, spacing)
                .alignmentGuide(.leading) { dimension in
                    if abs(width - dimension.width) > geometry.size.width {
                        width = 0
                        height -= dimension.height + spacing
                    }
                    let result = width
                    if dimension.width != 0 {
                        width -= dimension.width + spacing
                    }
                    return result
                }
                .alignmentGuide(.top) { dimension in
                    let result = height
                    if dimension.width == 0 {
                        height = 0
                    }
                    return result
                }
        }
    }
}
