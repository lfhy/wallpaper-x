import AppKit

protocol SteamWorkshopKeyboardDelegate: AnyObject {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool
}

final class SteamWorkshopKeyboardCollectionView: NSCollectionView {
    weak var keyboardDelegate: SteamWorkshopKeyboardDelegate?
    var onBackgroundLeftClick: (() -> Void)?
    var primaryClickHandler: ((IndexPath) -> Bool)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?
    private var lastPrimaryClickIndexPath: IndexPath?

    override func mouseDown(with event: NSEvent) {
        pendingPressReleaseWorkItem?.cancel()
        pendingPressReleaseWorkItem = nil

        if event.type == .leftMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            let indexPath = indexPathForItem(at: point)
            lastPrimaryClickIndexPath = indexPath
            if let indexPath {
                pressedCardIndexPath = indexPath
                pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
                cardPressStateHandler?(indexPath, true)
                if primaryClickHandler?(indexPath) == true {
                    return
                }
            }
        }

        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.type == .leftMouseUp else { return }
        if let pressedCardIndexPath {
            let elapsed = ProcessInfo.processInfo.systemUptime - pressedCardTimestamp
            let remaining = max(0, UIInteractionAnimation.minimumPressVisualDuration - elapsed)
            let releaseWork = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.cardPressStateHandler?(pressedCardIndexPath, false)
                self.pressedCardIndexPath = nil
            }
            pendingPressReleaseWorkItem = releaseWork
            if remaining <= 0 {
                releaseWork.perform()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: releaseWork)
            }
        }
        let point = convert(event.locationInWindow, from: nil)
        if lastPrimaryClickIndexPath == nil, indexPathForItem(at: point) == nil {
            onBackgroundLeftClick?()
        }
        lastPrimaryClickIndexPath = nil
    }

    override func keyDown(with event: NSEvent) {
        if keyboardDelegate?.steamWorkshopCollectionView(self, handleKey: event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
