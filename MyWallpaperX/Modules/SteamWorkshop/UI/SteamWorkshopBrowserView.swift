//
//  SteamWorkshopBrowserView.swift
//  MyWallpaperX
//

import SwiftUI
import AVKit
import AppKit

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
                .presentationBackground(.clear)
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
            SteamWorkshopBrowserLoadingView()
        case .failed(let message):
            SteamWorkshopBrowserErrorView(message: message) {
                service.refresh()
            }
        case .loaded:
            if service.browserItems.isEmpty {
                SteamWorkshopBrowserEmptyView()
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
                        onCancelDownload: {
                            service.cancelActiveDownload()
                        }
                    )

                    if service.isLoadingMoreBrowserItems {
                        SteamWorkshopBrowserLoadMoreView(text: "正在加载更多项目…")
                            .padding(.bottom, 10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

    private var downloadRecord: SteamWorkshopDownloadRecord? {
        service.downloadRecord(for: item.id)
    }

    private var isRefreshingDetail: Bool {
        service.isRefreshingSelectedBrowserItem && service.selectedBrowserItem?.id == item.id
    }

    private var currentDetailError: String? {
        guard service.selectedBrowserItem?.id == item.id else { return nil }
        return service.selectedBrowserItemError
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        service.dismissItemDetail()
                    }

                detailCard(proxy: proxy)
            }
        }
        .frame(minWidth: 1040, idealWidth: 1080, maxWidth: 1160, minHeight: 720, idealHeight: 760, maxHeight: 860)
        .background(Color.clear)
    }

    private func detailCard(proxy: GeometryProxy) -> some View {
        let cardWidth = max(940, min(980, proxy.size.width - 48))
        let cardHeight = max(620, min(680, proxy.size.height - 44))

        return HStack(alignment: .top, spacing: 24) {
            leftColumn
                .frame(width: 286, alignment: .topLeading)

            rightColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 36, x: 0, y: 12)
        .onTapGesture { }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            SteamWorkshopPreviewSurface(
                previewImageURL: item.previewImageURL,
                previewVideoURL: item.previewVideoURL,
                previewAssetKind: item.previewAssetKind
            )
            .frame(width: 286, height: 286)

            HStack(spacing: 8) {
                SteamWorkshopCompactBadge(label: item.previewAssetKind.isAnimated ? "动态预览" : "静态预览", style: .accent)
                SteamWorkshopCompactBadge(label: item.id, style: .neutral)
            }

            if !item.author.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("作者")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(item.author)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            SteamWorkshopFactList(facts: [
                ("发布时间", item.postedText),
                ("更新时间", item.updatedText),
                ("分辨率", item.resolutionText),
                ("文件大小", item.fileSizeText)
            ])

            Spacer(minLength: 0)
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if item.hasAdultContent {
                        SteamWorkshopAdultWarningBanner()
                    }

                    if isRefreshingDetail {
                        SteamWorkshopDetailLoadingBanner()
                    } else if let currentDetailError {
                        SteamWorkshopDetailErrorBanner(message: currentDetailError) {
                            service.retrySelectedBrowserItemDetailRefresh()
                        }
                    }

                    SteamWorkshopMetaGrid(items: [
                        ("类型", item.workshopTypeText),
                        ("年龄分级", item.ageRatingText),
                        ("题材", item.genreText),
                        ("分类", item.categoryText),
                        ("评分", item.scoreText),
                        ("订阅", item.subscriptionsText),
                        ("收藏", item.favoritesText)
                    ])

                    if !item.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SteamWorkshopSectionCard(title: "简介") {
                            Text(item.summary)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                    }

                    if !item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       item.descriptionText != item.summary {
                        SteamWorkshopSectionCard(title: "详情描述") {
                            Text(item.descriptionText)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                    }

                    if !item.tags.isEmpty {
                        SteamWorkshopSectionCard(title: "标签") {
                            FlexibleTagWrap(tags: item.tags)
                        }
                    }

                    if !item.detailFields.isEmpty {
                        SteamWorkshopSectionCard(title: "详细信息") {
                            SteamWorkshopDetailFieldSection(fields: item.detailFields)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 14)
            }

            Divider()

            footerActions
                .padding(.top, 14)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("项目详情")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    service.dismissItemDetail()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            if let postedText = item.postedText, !postedText.isEmpty {
                Text("发布于 \(postedText)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            detailPrimaryActionButton(downloadRecord: downloadRecord)

            if let downloadRecord {
                Button("打开文件夹") {
                    service.revealItem(downloadRecord)
                }
                .buttonStyle(.bordered)
            }

            Button("在 Steam 中打开") {
                service.openWorkshopDetailPage(for: item)
            }
            .buttonStyle(.bordered)

            Button("查看作者作品") {
                service.openAuthorWorksPage(for: item)
            }
            .buttonStyle(.bordered)
            .disabled(item.authorProfileURL == nil)

            Spacer(minLength: 0)

            Button("刷新详情") {
                service.retrySelectedBrowserItemDetailRefresh()
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshingDetail)
        }
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
        } else {
            Button("下载视频") {
                service.downloadWorkshopItem(id: item.id, pageTitle: item.title)
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.activeDownloadItemID != nil)
        }
    }
}

private struct SteamWorkshopCompactBadge: View {
    enum Style {
        case accent
        case neutral
    }

    let label: String
    let style: Style

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(style == .accent ? Color.accentColor : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(style == .accent ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
    }
}

private struct SteamWorkshopFactList: View {
    let facts: [(String, String?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                if let value = fact.1, !value.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Text(fact.0)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .leading)
                        Text(value)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct SteamWorkshopMetaGrid: View {
    let items: [(String, String?)]

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .topLeading),
        GridItem(.flexible(), spacing: 10, alignment: .topLeading),
        GridItem(.flexible(), spacing: 10, alignment: .topLeading)
    ]

    var body: some View {
        let visibleItems = items.compactMap { label, value -> (String, String)? in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }

        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }
}

private struct SteamWorkshopSectionCard<Content: View>: View {
    let title: String
    private let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.88))
        )
    }
}

private struct SteamWorkshopInlineInfoRow: View {
    let items: [(String, String?)]

    var body: some View {
        let visibleItems = items.compactMap { label, value -> (String, String)? in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }

        HStack(alignment: .top, spacing: 18) {
            ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SteamWorkshopPostedInfoView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("发布时间")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
    }
}

private struct SteamWorkshopAdultWarningBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("此项目被 Steam 标记为成人内容")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct SteamWorkshopDetailLoadingBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在补全该项目的详情信息…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct SteamWorkshopDetailErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("详情补全失败")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct SteamWorkshopDetailFieldSection: View {
    let fields: [SteamWorkshopDetailField]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("详细信息")
                .font(.system(size: 13, weight: .semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedLabel(for: field.label))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(field.value)
                            .font(.system(size: 13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
        }
    }

    private func localizedLabel(for label: String) -> String {
        switch label.lowercased() {
        case "type": return "类型"
        case "age rating": return "年龄分级"
        case "genre": return "题材"
        case "resolution": return "分辨率"
        case "category": return "分类"
        case "file size": return "文件大小"
        case "posted": return "发布时间"
        case "updated", "last updated": return "更新时间"
        case "subscriptions": return "订阅"
        case "favorites", "favorite", "favorited": return "收藏"
        case "score": return "评分"
        default: return label
        }
    }
}

private struct FlexibleTagWrap: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(tags.prefix(8)), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

private struct SteamWorkshopPreviewSurface: View {
    let previewImageURL: URL?
    let previewVideoURL: URL?
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

            if let previewVideoURL {
                SteamWorkshopAutoPlayPreview(url: previewVideoURL)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let previewImageURL {
                if previewAssetKind == .animatedImage {
                    SteamWorkshopAnimatedImage(url: previewImageURL)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    AsyncImage(url: previewImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Color.clear
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
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

private struct SteamWorkshopAnimatedImage: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.animates = true
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        nsView.image = nil

        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else {
                return
            }
            await MainActor.run {
                guard context.coordinator.currentURL == url else { return }
                nsView.image = image
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var currentURL: URL?
    }
}

private struct SteamWorkshopAutoPlayPreview: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .disabled(true)
            .onAppear {
                let player = AVPlayer(url: url)
                player.isMuted = true
                player.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
                self.player = player
                player.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}

private struct SteamWorkshopBrowserLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("正在抓取创意工坊视频列表…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct SteamWorkshopBrowserErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("抓取创意工坊信息失败")
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

private struct SteamWorkshopBrowserLoadMoreView: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct SteamWorkshopBrowserEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("当前条件下没有抓取到视频项目")
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
