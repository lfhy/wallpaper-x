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
