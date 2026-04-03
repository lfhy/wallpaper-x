//
//  SteamWorkshopBrowserView.swift
//  MyWallpaperX
//

import SwiftUI
import AVKit
import AppKit

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
        .sheet(isPresented: $service.isLoginSheetPresented) {
            SteamWorkshopLoginSheet()
        }
        .sheet(item: Binding(
            get: { service.selectedBrowserItem },
            set: { if $0 == nil { service.dismissItemDetail() } }
        )) { item in
            SteamWorkshopItemDetailSheet(item: item)
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
                        onDownload: { item in
                            service.downloadWorkshopItem(id: item.id, pageTitle: item.title)
                        },
                        onSetAsWallpaper: { record in
                            service.setAsWallpaper(record)
                        },
                        onCancelDownload: {
                            service.cancelActiveDownload()
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

private struct SteamWorkshopLoginSheet: View {
    @ObservedObject private var service = SteamWorkshopService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("登录 Steam 以启用创意工坊下载")
                    .font(.system(size: 18, weight: .semibold))
                Text(service.authStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Steam 用户名")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("请输入用户名", text: $service.steamUsername)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Steam 密码")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    SecureField("请输入密码", text: $service.steamPassword)
                        .textFieldStyle(.roundedBorder)
                }

                if service.authPhase == .awaitingGuardCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Steam Guard 令牌")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("请输入邮件或手机 App 收到的令牌", text: $service.steamGuardCode)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .frame(maxWidth: 420)

            HStack(spacing: 12) {
                if service.authPhase == .awaitingGuardCode {
                    Button(service.isAuthenticating ? "验证中…" : "验证令牌并进入页面") {
                        service.submitSteamGuardCode()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.isAuthenticating)
                } else {
                    Button(service.isPreparingRuntime ? "准备中…" : (service.isAuthenticating ? "登录中…" : "发送登录请求")) {
                        service.authenticateUser()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.isAuthenticating || service.isPreparingRuntime)

                    Button("匿名浏览") {
                        service.browseAnonymously()
                    }
                    .buttonStyle(.bordered)
                    .disabled(service.isAuthenticating || service.isPreparingRuntime)
                }

                Button("关闭") {
                    service.isLoginSheetPresented = false
                }
                .buttonStyle(.bordered)
            }

            Text(service.authPhase == .awaitingGuardCode
                 ? "说明：第一步账号密码已提交，当前正在等待 Steam Guard 验证。令牌通过后才会进入浏览页。"
                 : "说明：软件会先检查 App 内置的 SteamCMD 运行环境。匿名模式只浏览不下载；登录模式会按 `login 用户名 密码` 发起请求，若 Steam 要求，再继续输入 Guard。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 460)
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SteamWorkshopItemDetailSheet: View {
    let item: SteamWorkshopBrowserItem
    @ObservedObject private var service = SteamWorkshopService.shared

    private var currentItem: SteamWorkshopBrowserItem {
        if let selected = service.selectedBrowserItem, selected.id == item.id {
            return selected
        }
        return item
    }

    private var downloadRecord: SteamWorkshopDownloadRecord? {
        service.downloadRecord(for: item.id)
    }

    private var latestDownloadRecord: SteamWorkshopDownloadRecord? {
        service.latestDownloadRecord(for: item.id)
    }

    private var latestDownloadFailure: String? {
        latestDownloadRecord?.failureMessage
    }

    private var isRefreshingDetail: Bool {
        service.isRefreshingSelectedBrowserItem && service.selectedBrowserItem?.id == item.id
    }

    private var currentDetailError: String? {
        guard service.selectedBrowserItem?.id == item.id else { return nil }
        return service.selectedBrowserItemError
    }

    private var detailDescription: String? {
        let summary = currentItem.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = currentItem.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty, description != summary {
            return description
        }
        if !summary.isEmpty {
            return summary
        }
        return nil
    }

    private var detailDescriptionLine: String {
        let trimmed = detailDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "暂无更多描述" : trimmed
    }

    private var topFacts: [(String, String?)] {
        [
            ("类型", currentItem.workshopTypeText),
            ("年龄分级", currentItem.ageRatingText),
            ("题材", currentItem.genreText)
        ]
    }

    private var bottomFacts: [(String, String?)] {
        [
            ("分辨率", currentItem.resolutionText),
            ("文件大小", currentItem.fileSizeText),
            ("分类", currentItem.categoryText)
        ]
    }

    private var secondaryFactText: String? {
        let values = [
            currentItem.scoreText,
            currentItem.subscriptionsText.map { "订阅 \($0)" },
            currentItem.favoritesText.map { "收藏 \($0)" },
            currentItem.lifetimeSubscriptionsText.map { "总订阅 \($0)" },
            currentItem.lifetimeFavoritesText.map { "总收藏 \($0)" }
        ]
        .compactMap { $0 }

        guard !values.isEmpty else { return nil }
        return values.joined(separator: "  ·  ")
    }

    private var statusFactText: String? {
        [
            currentItem.visibilityText.map { "可见性 \($0)" },
            currentItem.moderationText.map { "状态 \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
        .nilIfEmpty
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    leftColumn
                        .frame(width: 220, alignment: .topLeading)

                    rightColumn
                        .frame(width: 480, alignment: .topLeading)
                }

                HStack(alignment: .bottom, spacing: 20) {
                    leftFooter
                        .frame(width: 220, alignment: .leading)

                    rightFooter
                        .frame(width: 480, alignment: .leading)
                }
            }
            .frame(width: 720, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 760, height: 365, alignment: .center)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            SteamWorkshopPreviewSurface(
                itemID: currentItem.id,
                previewImageURL: currentItem.previewImageURL,
                previewAssetKind: currentItem.previewAssetKind
            )
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !currentItem.author.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("作者")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(currentItem.author)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            SteamWorkshopInfoRow(items: topFacts)

            SteamWorkshopInfoRow(items: bottomFacts)
                .overlay(alignment: .topLeading) {
                    if isRefreshingDetail {
                        SteamWorkshopInlineNotice(
                            icon: "arrow.triangle.2.circlepath",
                            text: "正在补全该项目的详情信息…"
                        )
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                        .offset(x: 150, y: 62)
                    }
                }

            if let postedText = currentItem.postedText, !postedText.isEmpty {
                SteamWorkshopSingleFactCard(label: "发布时间", value: postedText)
            }

            if let statusFactText {
                Text(statusFactText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let secondaryFactText {
                Text(secondaryFactText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    private var leftFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("描述")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(detailDescriptionLine)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rightFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let currentDetailError {
                SteamWorkshopInlineErrorNotice(message: currentDetailError) {
                    service.retrySelectedBrowserItemDetailRefresh()
                }
            }

            if let latestDownloadFailure,
               !service.isDownloading(itemID: item.id),
               downloadRecord == nil {
                SteamWorkshopInlineErrorNotice(message: "上次下载失败：\(latestDownloadFailure)") {
                    service.downloadWorkshopItem(id: item.id, pageTitle: item.title)
                }
            }

            footerActions
                .overlay(alignment: .top) {
                    if currentItem.hasAdultContent {
                        SteamWorkshopInlineNotice(
                            icon: "exclamationmark.triangle.fill",
                            text: "此项目被 Steam 标记为成人内容"
                        )
                        .frame(width: 492, alignment: .center)
                        .offset(y: -34)
                    }
                }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(currentItem.title)
                .font(.system(size: 19, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 456, alignment: .leading)
            Text("项目详情")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 2) {
            detailPrimaryActionButton(downloadRecord: downloadRecord)
                .frame(width: 92)

            Button("网页浏览") {
                service.openWorkshopDetailPage(for: currentItem)
            }
            .buttonStyle(.bordered)
            .frame(width: 88)

            Button("作者工坊") {
                service.showAuthorWorkshop(for: currentItem)
            }
            .buttonStyle(.bordered)
            .disabled(currentItem.authorProfileURL == nil && currentItem.authorWorkshopURL == nil)
            .frame(width: 88)

            Button("刷新详情") {
                service.retrySelectedBrowserItemDetailRefresh()
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshingDetail)
            .frame(width: 88)

            Button("关闭窗口") {
                service.dismissItemDetail()
            }
            .buttonStyle(.bordered)
            .frame(width: 88)
        }
        .frame(width: 456, alignment: .leading)
        .controlSize(.large)
    }

    @ViewBuilder
    private func detailPrimaryActionButton(downloadRecord: SteamWorkshopDownloadRecord?) -> some View {
        if service.isDownloading(itemID: item.id) {
            Button("取消下载") {
                service.cancelActiveDownload()
            }
            .buttonStyle(.borderedProminent)
        } else if let downloadRecord {
            Button("设为壁纸") {
                service.setAsWallpaper(downloadRecord)
            }
            .buttonStyle(.borderedProminent)
        } else if latestDownloadFailure != nil {
            Button("重新下载") {
                service.downloadWorkshopItem(id: item.id, pageTitle: currentItem.title)
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.activeDownloadItemID != nil)
        } else {
            Button("下载视频") {
                service.downloadWorkshopItem(id: item.id, pageTitle: currentItem.title)
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.activeDownloadItemID != nil)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct SteamWorkshopFactList: View {
    let facts: [(String, String?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                if let value = fact.1, !value.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text(fact.0)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Text(value)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SteamWorkshopInfoRow: View {
    let items: [(String, String?)]

    var body: some View {
        let visibleItems = items.compactMap { label, value -> (String, String)? in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }

        HStack(alignment: .top, spacing: 28) {
            ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 146, alignment: .leading)
            }
        }
        .frame(width: 478, alignment: .leading)
    }
}

private struct SteamWorkshopSingleFactCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 146, alignment: .leading)
    }
}

private struct SteamWorkshopInlineNotice: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct SteamWorkshopInlineErrorNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("详情补全失败")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SteamWorkshopPreviewSurface: View {
    let itemID: String
    let previewImageURL: URL?
    let previewAssetKind: SteamWorkshopPreviewAssetKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.11, green: 0.17, blue: 0.29), Color(red: 0.09, green: 0.31, blue: 0.44)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let previewImageURL {
                SteamWorkshopCachedPreviewImage(
                    itemID: itemID,
                    url: previewImageURL
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.36)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .clipped()
    }
}

private struct SteamWorkshopCachedPreviewImage: NSViewRepresentable {
    let itemID: String
    let url: URL

    func makeNSView(context: Context) -> SteamWorkshopPreviewImageContainerView {
        SteamWorkshopPreviewImageContainerView()
    }

    func updateNSView(_ nsView: SteamWorkshopPreviewImageContainerView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url

        let cacheKey = steamWorkshopPreviewCacheKey(for: url)
        if let cached = SteamWorkshopPreviewImageCache.shared.cachedOrDiskImage(forKey: cacheKey) {
            nsView.setImage(cached)
            return
        }

        SteamWorkshopPreviewImageCache.shared.loadImageData(forKey: cacheKey, loader: {
            return try? Data(contentsOf: url)
        }) { image in
            guard context.coordinator.currentURL == url else { return }
            nsView.setImage(image)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var currentURL: URL?
    }
}

private final class SteamWorkshopPreviewImageContainerView: NSView {
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }

    override func layout() {
        super.layout()
        updateImageFrame()
    }

    func setImage(_ image: NSImage?) {
        imageView.image = image
        updateImageFrame()
    }

    private func updateImageFrame() {
        let containerBounds = bounds
        guard containerBounds.width > 0, containerBounds.height > 0 else {
            imageView.frame = .zero
            return
        }
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            imageView.frame = containerBounds
            return
        }

        let widthScale = containerBounds.width / image.size.width
        let heightScale = containerBounds.height / image.size.height
        let scale: CGFloat
        if image.size.width < containerBounds.width || image.size.height < containerBounds.height {
            scale = max(widthScale, heightScale)
        } else {
            scale = min(widthScale, heightScale)
        }
        let fittedWidth = image.size.width * scale
        let fittedHeight = image.size.height * scale
        imageView.frame = CGRect(
            x: floor((containerBounds.width - fittedWidth) * 0.5),
            y: floor((containerBounds.height - fittedHeight) * 0.5),
            width: ceil(fittedWidth),
            height: ceil(fittedHeight)
        )
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
