//
//  SteamWorkshopDownloadsView.swift
//  MyWallpaperX
//

import SwiftUI

struct SteamWorkshopDownloadsView: View {
    var body: some View {
        SteamWorkshopDownloadsContentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SteamWorkshopDownloadsContentView: View {
    @ObservedObject private var service = SteamWorkshopService.shared

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

    var body: some View {
        AppKitSteamWorkshopDownloadsGridView(
            service: service,
            onOpen: { item in
                service.presentItemDetail(item)
            },
            onSetAsWallpaper: { record in
                service.setAsWallpaper(record)
            },
            onReveal: { record in
                service.revealItem(record)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onAppear {
            service.reloadInstalledItems()
        }
        .onDisappear {
            InspectorHostActions.postClose(module: .steamWorkshop)
            service.dismissItemDetail()
        }
        .overlay {
            if shouldShowBanner {
                VStack {
                    SteamWorkshopStatusBanner(
                        title: bannerTitle,
                        message: bannerMessage,
                        progressFraction: service.activeDownloadItemID != nil ? service.activeDownloadProgressFraction : nil,
                        progressText: service.activeDownloadItemID != nil ? service.activeDownloadProgressText : nil,
                        primaryActionTitle: primaryActionTitle,
                        primaryAction: primaryAction,
                        secondaryActionTitle: secondaryActionTitle,
                        secondaryAction: secondaryAction
                    )
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
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
    }

    private var shouldShowBanner: Bool {
        service.authPhase == .awaitingGuardCode
            || service.authSessionState == .authenticating
            || pendingDownloadTitle != nil
            || service.activeDownloadItemID != nil
    }

    private var bannerTitle: String {
        if service.authPhase == .awaitingGuardCode {
            return "等待 Steam Guard 验证"
        }
        if service.authSessionState == .authenticating {
            return "正在验证 Steam 会话"
        }
        if service.activeDownloadItemID != nil {
            return "下载任务进行中"
        }
        return "下载任务待继续"
    }

    private var bannerMessage: String {
        if let pendingDownloadTitle {
            return "\(service.authStatusMessage)\n登录成功后会自动继续下载：\(pendingDownloadTitle)"
        }
        return service.activeDownloadItemID != nil ? service.statusMessage : service.authStatusMessage
    }

    private var primaryActionTitle: String? {
        if service.authPhase == .awaitingGuardCode {
            return "输入 Guard 令牌"
        }
        if pendingDownloadTitle != nil || service.authSessionState == .authenticating {
            return "继续登录"
        }
        return nil
    }

    private var primaryAction: (() -> Void)? {
        guard primaryActionTitle != nil else { return nil }
        return {
            service.presentLoginGate()
        }
    }

    private var secondaryActionTitle: String? {
        if pendingDownloadTitle != nil {
            return "取消待续下载"
        }
        if service.activeDownloadItemID != nil {
            return "取消当前下载"
        }
        return nil
    }

    private var secondaryAction: (() -> Void)? {
        if pendingDownloadTitle != nil {
            return {
                service.clearPendingDownloadRequest()
            }
        }
        if service.activeDownloadItemID != nil {
            return {
                service.cancelActiveDownload()
            }
        }
        return nil
    }
}
