import SwiftUI
import AppKit

struct SteamWorkshopItemDetailSheet: View {
    let item: SteamWorkshopBrowserItem
    @ObservedObject private var service = SteamWorkshopService.shared

    private var currentItem: SteamWorkshopBrowserItem {
        if let selected = service.selectedDownloadDetailItem, selected.id == item.id {
            return selected
        }
        if let selected = service.selectedBrowserItem, selected.id == item.id {
            return selected
        }
        return item
    }

    private var downloadRecord: SteamWorkshopDownloadRecord? {
        service.playableDownloadRecord(for: item.id)
    }

    private var latestDownloadRecord: SteamWorkshopDownloadRecord? {
        service.latestDownloadRecord(for: item.id)
    }

    private var latestDownloadFailure: String? {
        latestDownloadRecord?.failureMessage
    }

    private var isRefreshingDetail: Bool {
        if service.selectedDownloadInspectorItem?.id == item.id {
            return service.isRefreshingSelectedDownloadDetailItem
        }
        return service.isRefreshingSelectedBrowserItem && service.selectedBrowserItem?.id == item.id
    }

    private var currentDetailError: String? {
        if service.selectedDownloadInspectorItem?.id == item.id {
            return service.selectedDownloadDetailError
        }
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

    private var secondaryFactText: String? {
        let values = [
            currentItem.scoreText,
            currentItem.subscriptionsText.map { "订阅 \($0)" },
            currentItem.favoritesText.map { "收藏 \($0)" }
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

    private var heroBadges: [String] {
        [
            currentItem.workshopTypeText,
            currentItem.ageRatingText,
            currentItem.genreText
        ]
        .compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private var statFacts: [(String, String)] {
        [
            ("分辨率", currentItem.resolutionText),
            ("文件大小", currentItem.fileSizeText),
            ("发布时间", currentItem.postedText),
            ("分类", currentItem.categoryText)
        ]
        .compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    private let topScrollFadeHeight: CGFloat = 12
    private let bottomScrollFadeHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    previewSection
                    metaSection
                    contentSection
                    noticeSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
                .padding(.top, 10)
            }
            .mask {
                SteamWorkshopScrollFadeMask(
                    topFadeHeight: topScrollFadeHeight,
                    bottomFadeHeight: bottomScrollFadeHeight
                )
            }

            footerActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !heroBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(heroBadges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.12))
                                )
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let statusFactText {
                Text(statusFactText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SteamWorkshopPreviewSurface(
                itemID: currentItem.id,
                previewImageURL: currentItem.previewImageURL,
                previewAssetKind: currentItem.previewAssetKind
            )
            .frame(maxWidth: .infinity)
            .frame(height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.45)
            }

            Text(currentItem.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !currentItem.author.isEmpty {
                Text(currentItem.author)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let secondaryFactText {
                Text(secondaryFactText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !statFacts.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.035))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(Array(statFacts.enumerated()), id: \.offset) { _, fact in
                        SteamWorkshopSingleFactCard(label: fact.0, value: fact.1)
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 6) {
                Text("描述")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(detailDescriptionLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
    }

    private var noticeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if isRefreshingDetail {
                SteamWorkshopInlineNotice(
                    icon: "arrow.triangle.2.circlepath",
                    text: "正在补全该项目的详情信息…"
                )
            }

            if currentItem.hasAdultContent {
                SteamWorkshopInlineNotice(
                    icon: "exclamationmark.triangle.fill",
                    text: "此项目被 Steam 标记为成人内容"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerActions: some View {
        HStack(spacing: 6) {
            detailPrimaryActionButton(downloadRecord: downloadRecord)
                .frame(maxWidth: .infinity)

            Button {
                service.openAuthorWorksPage(for: currentItem)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("作者工坊")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(SteamWorkshopFooterButtonStyle(kind: .secondary))
            .disabled(currentItem.authorProfileURL == nil && currentItem.authorWorkshopURL == nil)

            Button {
                service.openWorkshopDetailPage(for: currentItem)
            } label: {
                Image(systemName: "safari")
                    .frame(width: 18, height: 18)
                    .frame(width: 46, height: 38)
            }
            .buttonStyle(SteamWorkshopFooterButtonStyle(kind: .secondary))
            .help("网页浏览")
            .accessibilityLabel("网页浏览")

            Button {
                service.retrySelectedBrowserItemDetailRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
                    .frame(width: 46, height: 38)
            }
            .buttonStyle(SteamWorkshopFooterButtonStyle(kind: .secondary))
            .help("刷新详情")
            .accessibilityLabel("刷新详情")
            .disabled(isRefreshingDetail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func detailPrimaryActionButton(downloadRecord: SteamWorkshopDownloadRecord?) -> some View {
        if service.isDownloading(itemID: item.id) || service.isQueuedForDownload(itemID: item.id) {
            Button {
                service.cancelDownload(itemID: item.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(service.isQueuedForDownload(itemID: item.id) ? "取消队列" : "取消下载")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(SteamWorkshopFooterButtonStyle(kind: .danger))
        } else if let downloadRecord {
            Button {
                service.setAsWallpaper(downloadRecord)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("设为壁纸")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(SteamWorkshopFooterButtonStyle(kind: .primary))
        } else if latestDownloadFailure != nil {
            Button {
                service.downloadWorkshopItem(id: item.id, pageTitle: currentItem.title)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("重新下载")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(SteamWorkshopFooterButtonStyle(kind: .primary))
            .disabled(service.activeDownloadItemID != nil)
        } else {
            Button {
                service.downloadWorkshopItem(id: item.id, pageTitle: currentItem.title)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("下载视频")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(SteamWorkshopFooterButtonStyle(kind: .primary))
            .disabled(service.activeDownloadItemID != nil)
        }
    }

    private func requestInspectorClose() {
        InspectorHostActions.postClose()
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

private struct SteamWorkshopScrollFadeMask: View {
    let topFadeHeight: CGFloat
    let bottomFadeHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, topFadeHeight + bottomFadeHeight + 1)
            let topFadeRatio = min(max(topFadeHeight / height, 0.01), 0.18)
            let bottomFadeRatio = min(max(bottomFadeHeight / height, 0.01), 0.24)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: topFadeRatio),
                    .init(color: .black, location: 1 - bottomFadeRatio),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

private struct SteamWorkshopInfoRow: View {
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SteamWorkshopMetricPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.018))
            )
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
                .fixedSize(horizontal: false, vertical: true)
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

private enum SteamWorkshopFooterButtonKind {
    case primary
    case secondary
    case danger
}

private struct SteamWorkshopFooterButtonStyle: ButtonStyle {
    var kind: SteamWorkshopFooterButtonKind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .background(backgroundFill(isPressed: configuration.isPressed))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor.opacity(isEnabled ? 1 : 0.55), lineWidth: 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return Color(nsColor: .labelColor)
        case .danger:
            return .white
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return Color(nsColor: .systemBlue).opacity(0.42)
        case .secondary:
            return Color.white.opacity(0.16)
        case .danger:
            return Color.red.opacity(0.24)
        }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool) -> some View {
        let opacity = isPressed ? 0.9 : 1.0
        let pressed = isPressed ? 1.0 : 0.0

        switch kind {
        case .primary:
            Color(nsColor: isPressed ? .systemBlue.withSystemEffect(.pressed) : .systemBlue)
        case .secondary:
            Color.black.opacity(0.14 * opacity)
        case .danger:
            Color.red.opacity(0.68 - (0.12 * pressed))
        }
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
                        colors: [Color.white.opacity(0.22), Color(red: 0.84, green: 0.91, blue: 1.0).opacity(0.20)],
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
                colors: [.clear, .white.opacity(0.02)],
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
