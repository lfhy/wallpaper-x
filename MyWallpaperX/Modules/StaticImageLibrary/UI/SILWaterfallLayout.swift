//
//  SILWaterfallLayout.swift
//  MyWallpaperX — Modules/StaticImageLibrary/UI
//
//  瀑布流布局：每列维护高度累加器，图片按原始比例放入最短列。
//  列数由外部 columnCount 决定，卡片高度由 aspectRatio 计算，
//  限制在 minAspectRatio ~ maxAspectRatio 范围内避免极端比例。
//
import AppKit

final class SILWaterfallLayout: NSCollectionViewLayout {

    // MARK: - 配置

    /// 列数（由 zoomOffset 驱动，外部设置后调用 invalidateLayout）
    var columnCount: Int = 4 { didSet { if oldValue != columnCount { invalidateLayout() } } }

    /// 列间距
    var columnSpacing: CGFloat = 8

    /// 行间距
    var rowSpacing: CGFloat = 10

    /// 内边距
    var sectionInset: NSEdgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

    /// 最小宽高比（防止超高竖图），0.25 = 1:4
    var minAspectRatio: CGFloat = 0.25

    /// 最大宽高比（防止超宽横图），3:1
    var maxAspectRatio: CGFloat = 3.0

    /// 每个 item 的宽高比提供者（indexPath -> aspectRatio）
    var aspectRatioProvider: ((IndexPath) -> CGFloat)?

    // MARK: - 内部状态

    private var cache: [NSCollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var contentWidth: CGFloat {
        guard let cv = collectionView else { return 0 }
        return cv.bounds.width - sectionInset.left - sectionInset.right
    }

    // MARK: - 布局计算

    override func prepare() {
        super.prepare()
        guard let cv = collectionView else { return }
        cache.removeAll(keepingCapacity: true)

        // 还没有 section 时直接返回，避免 numberOfItems(inSection:0) 崩溃
        guard cv.numberOfSections > 0 else {
            contentHeight = 0
            return
        }

        let cols = max(1, columnCount)
        // 先用配置间距估算列宽，再计算动态间距，最后重算列宽
        // 间距 = 卡片宽 × (scale-1)，刚好容纳放大量不遮盖相邻卡片
        let estimatedColWidth = max(60, (contentWidth - columnSpacing * CGFloat(cols - 1)) / CGFloat(cols))
        let hoverScale: CGFloat = 1.05
        let minSpacing = estimatedColWidth * (hoverScale - 1.0)
        let effectiveColSpacing = max(columnSpacing, minSpacing)
        let effectiveRowSpacing = max(rowSpacing, minSpacing)
        let colWidth = max(60, (contentWidth - effectiveColSpacing * CGFloat(cols - 1)) / CGFloat(cols))

        var colHeights = [CGFloat](repeating: sectionInset.top, count: cols)

        let itemCount = cv.numberOfItems(inSection: 0)
        for i in 0 ..< itemCount {
            let ip = IndexPath(item: i, section: 0)

            // 找最短列
            let shortestCol = colHeights.indices.min(by: { colHeights[$0] < colHeights[$1] }) ?? 0
            let x = sectionInset.left + CGFloat(shortestCol) * (colWidth + effectiveColSpacing)
            let y = colHeights[shortestCol]

            // 计算卡片高度
            let rawRatio = aspectRatioProvider?(ip) ?? (16.0 / 9.0)
            let clampedRatio = max(minAspectRatio, min(maxAspectRatio, rawRatio))
            let cardH = colWidth / clampedRatio

            let attrs = NSCollectionViewLayoutAttributes(forItemWith: ip)
            attrs.frame = CGRect(x: x, y: y, width: colWidth, height: cardH)
            cache.append(attrs)

            colHeights[shortestCol] += cardH + effectiveRowSpacing
        }

        contentHeight = (colHeights.max() ?? sectionInset.top) + sectionInset.bottom - rowSpacing
        contentHeight = max(contentHeight, sectionInset.top + sectionInset.bottom)
    }

    override var collectionViewContentSize: NSSize {
        guard let cv = collectionView else { return .zero }
        return NSSize(width: cv.bounds.width, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cache.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        collectionView?.bounds.width != newBounds.width
    }
}
