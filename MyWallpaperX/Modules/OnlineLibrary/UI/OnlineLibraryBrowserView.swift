//
//  OnlineLibraryBrowserView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//
//  对外唯一入口：OnlineLibraryEntryView（供 Shell/ContentViewSupport 路由）
//  依赖 Shared：GridLayoutHelper（列数计算）、UIInteractionAnimation（动画常量）
//  OnlineLibrary 浏览页已迁移为 AppKit NSCollectionView（AppKitOLBrowserGridView），
//  并通过 AppKitOLBrowserContainerView 接入 ModuleFocusable。
//

import SwiftUI
import AppKit
import AVKit

// MARK: - 对外入口

/// 在线图库入口，由 Shell 层的 DetailView 路由调用。
public struct OnlineLibraryEntryView: View {
    public init() {}
    public var body: some View {
        OnlineLibraryBrowserView()
            .ignoresSafeArea(.container, edges: .top)
    }
}

// MARK: - 浏览器主体

struct OnlineLibraryBrowserView: View {
    // 单例用 @ObservedObject（@StateObject 生命周期由视图管理，与单例语义矛盾）
    @ObservedObject private var service = OnlineLibraryService.shared

    @State private var apiKeyInput: String = ""
    @State private var showingAPIKeyEdit = false  // 更改 API Key 面板
    @State private var showDownloadToast = false
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var isToastHovering = false

    var body: some View {
        Group {
            if !service.hasValidAPIKey {
                apiKeyPromptView
            } else {
                contentArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            apiKeyInput = service.apiKey
            triggerInitialSearchIfNeeded()
            // 监听工具栏「API Key」按钮通知
            NotificationCenter.default.addObserver(
                forName: .olShowAPIKeySettings, object: nil, queue: .main
            ) { [self] _ in
                apiKeyInput = ""
                showingAPIKeyEdit = true
            }
            // 监听工具栏「清空 API Key」通知
            NotificationCenter.default.addObserver(
                forName: .olClearAPIKey, object: nil, queue: .main
            ) { [self] _ in
                service.clearAPIKeyAndReset()
            }
        }
        // 点击内容区任意位置时放弃搜索框焦点
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .alert("下载失败", isPresented: Binding(
            get: { service.downloadError != nil },
            set: { if !$0 { service.downloadError = nil } }
        )) {
            Button("确定", role: .cancel) { service.downloadError = nil }
        } message: {
            Text(service.downloadError ?? "")
        }
        // OL-04：下载成功 Toast 触发器
        .onChange(of: service.downloadSuccessMessage) { msg in
            guard msg != nil else { return }
            showDownloadToast = true
            isToastHovering = false
            scheduleToastDismiss(after: 4)
        }
        // API Key 更改面板（P3）
        .sheet(isPresented: $showingAPIKeyEdit) {
            apiKeyEditSheet
        }
    }

    // MARK: - 私有方法

    /// OL-15：统一「有 API Key 时触发首次/初始搜索」逻辑，消除 onAppear 与保存按钮的重复代码
    private func triggerInitialSearchIfNeeded() {
        // hasLoadedOnce 保护：切换回来不重复刷新；保存 API Key 后 hasLoadedOnce 为 false，正常触发
        guard service.hasValidAPIKey, !service.hasLoadedOnce, !service.isLoading else { return }
        service.searchWithCurrentContext(order: .popular)
    }

    private func scheduleToastDismiss(after seconds: TimeInterval) {
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, !isToastHovering else { return }
            dismissToastNow(animationDuration: 0.25)
        }
    }

    private func dismissToastNow(animationDuration: TimeInterval) {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        withAnimation(.easeOut(duration: animationDuration)) { showDownloadToast = false }
        service.downloadSuccessMessage = nil
        service.lastDownloadedItemID = nil
    }

    // MARK: - 内容区

    private var contentArea: some View {
        ZStack {
            // 主内容
            if service.isLoading && service.items.isEmpty {
                VStack(spacing: 12) {
                    OLSpinner().frame(width: 20, height: 20)
                    Text("加载中...").foregroundColor(.secondary).font(.system(size: 13))
                }
            } else if let err = service.errorMessage, service.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36)).foregroundColor(.secondary)
                    Text(err).font(.system(size: 13)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                    HStack(spacing: 12) {
                        Button("重试") {
                            service.searchWithCurrentContext()
                        }.buttonStyle(.borderedProminent)
                        // API Key 相关错误时提供直接更改入口
                        if err.contains("API Key") {
                            Button("更改 API Key") {
                                apiKeyInput = ""
                                showingAPIKeyEdit = true
                            }.buttonStyle(.bordered)
                        }
                    }
                }
            } else if service.items.isEmpty {
                if service.hasLoadedOnce {
                    // 已发起过搜索但结果为空
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 36)).foregroundColor(.secondary)
                        Text("没有找到相关视频").foregroundColor(.secondary).font(.system(size: 13))
                        Text("试试其他关键词或分类")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                } else {
                    // 从未加载（有 API Key 但还没触发过搜索，理论上不应出现，兜底展示）
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 36)).foregroundColor(.secondary)
                        Text("探索海量免费视频壁纸").foregroundColor(.secondary).font(.system(size: 13))
                        Button("开始浏览") {
                            service.searchWithCurrentContext(order: .popular)
                        }.buttonStyle(.borderedProminent)
                    }
                }
            } else {
                OLGridContentView(
                    service: service,
                    onDownload: { service.download(item: $0) },
                    onSetAsWallpaper: { service.downloadAndSet(item: $0) }
                )
            }

            // OL-04：非阻断式下载成功 Toast（底部居中，4 秒自动消失）
            if showDownloadToast {
                VStack {
                    Spacer()
                    OLDownloadToast(
                        onSetAsWallpaper: {
                            if let id = service.lastDownloadedItemID {
                                service.setLocalFileAsWallpaper(id: id)
                            }
                            dismissToastNow(animationDuration: 0.2)
                        },
                        onDismiss: {
                            dismissToastNow(animationDuration: 0.2)
                        },
                        onHoverChange: { hovering in
                            isToastHovering = hovering
                            if hovering {
                                toastDismissTask?.cancel()
                                toastDismissTask = nil
                            } else {
                                scheduleToastDismiss(after: 1.5)
                            }
                        }
                    )
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDownloadToast)
                .allowsHitTesting(true)
                .zIndex(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - API Key 引导页

    private var apiKeyPromptView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill").font(.system(size: 44)).foregroundColor(.accentColor)
            Text("需要 API Key").font(.system(size: 16, weight: .semibold))
            Text("请前往 Pixabay 获取免费 API Key，即可开始浏览在线壁纸。")
                .font(.system(size: 13)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Button("前往 Pixabay 获取 API Key") {
                NSWorkspace.shared.open(URL(string: "https://pixabay.com/api/docs/")!)
            }.buttonStyle(.borderedProminent)
            HStack(spacing: 8) {
                // SecureField 避免 API Key 明文显示
                SecureField("粘贴 API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder).frame(width: 260)
                Button("保存") {
                    service.apiKey = apiKeyInput.trimmingCharacters(in: .whitespaces)
                    triggerInitialSearchIfNeeded()
                }
                .buttonStyle(.bordered)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    // MARK: - API Key 更改面板（P3）

    private var apiKeyEditSheet: some View {
        VStack(spacing: 16) {
            Text("更改 API Key").font(.system(size: 15, weight: .semibold))
            Text("当前 Key 已遮蔽显示，输入新 Key 后保存即可生效。")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
            SecureField("输入新 API Key", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder).frame(width: 280)
            HStack(spacing: 12) {
                Button("取消") { showingAPIKeyEdit = false }
                    .buttonStyle(.bordered)
                Button("保存") {
                    let trimmed = apiKeyInput.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        service.apiKey = trimmed
                        service.resetLoadedState()  // 触发重新加载
                        triggerInitialSearchIfNeeded()
                    }
                    showingAPIKeyEdit = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - 网格（独立 struct，AppKit NSCollectionView 底层，彻底解决 hover 放大被裁剪问题）

private struct OLGridContentView: View {
    @ObservedObject var service: OnlineLibraryService
    let onDownload:       (OnlineLibraryVideoItem) -> Void
    let onSetAsWallpaper: (OnlineLibraryVideoItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // P4：有数据时出错显示 banner，不清除现有内容
            if let err = service.errorMessage, !service.items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(err).font(.system(size: 12)).foregroundColor(.primary)
                    Spacer()
                    Button {
                        service.searchWithCurrentContext()
                    } label: {
                        Text("重试").font(.system(size: 12))
                    }.buttonStyle(.bordered)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            AppKitOLBrowserGridView(
                service: service,
                onDownload: onDownload,
                onSetAsWallpaper: onSetAsWallpaper
            )
        }
    }
}

private struct OLThumbnailView: View {
    let url: URL?

    @State private var image:      NSImage? = nil
    @State private var isLoading:  Bool     = false
    @State private var hasFailed:  Bool     = false
    @State private var retryCount: Int      = 0
    private let maxRetries = 3

    var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
            } else if hasFailed {
                Rectangle().fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo").foregroundColor(.secondary)
                            if retryCount < maxRetries {
                                Button("重试") { load() }
                                    .font(.system(size: 10))
                                    .buttonStyle(.plain)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    )
            } else {
                Rectangle().fill(Color(NSColor.controlBackgroundColor))
                    .overlay(OLSpinner().frame(width: 16, height: 16))
            }
        }
        .aspectRatio(16/9, contentMode: .fill)
        .clipped()
        .onAppear { if image == nil { load() } }
    }

    private func load() {
        guard let url, !isLoading else { return }
        // 先查磁盘缓存
        Task {
            if let cached = await OLThumbnailCache.shared.cachedData(for: url),
               let img = NSImage(data: cached) {
                await MainActor.run { image = img }
                return
            }
            await MainActor.run { isLoading = true; hasFailed = false }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let img = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                await OLThumbnailCache.shared.store(data: data, for: url)
                await MainActor.run { image = img; isLoading = false }
            } catch {
                await MainActor.run {
                    isLoading = false
                    retryCount += 1
                    if retryCount < maxRetries {
                        // 自动重试，间隔 1s
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            load()
                        }
                    } else {
                        hasFailed = true
                    }
                }
            }
        }
    }
}

// MARK: - 下载成功 Toast

private struct OLLiquidGlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .withinWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
}

private struct OLDownloadToast: View {
    let onSetAsWallpaper: () -> Void
    let onDismiss: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.green)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("下载完成")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("已保存到 影片/MyWallpaperX/在线图库")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("设为壁纸") { onSetAsWallpaper() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.9))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            OLLiquidGlassBackground(cornerRadius: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .shadow(color: .black.opacity(0.11), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
        )
        .frame(maxWidth: 430)
        .padding(.horizontal, 24)
        .onHover { onHoverChange($0) }
    }
}

// MARK: - Spinner（NSProgressIndicator 包装，避免 SwiftUI ProgressView 约束冲突刷屏）

private struct OLSpinner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSProgressIndicator {
        let v = NSProgressIndicator()
        v.style = .spinning
        v.controlSize = .regular
        v.isIndeterminate = true
        v.startAnimation(nil)
        return v
    }
    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {}
}
