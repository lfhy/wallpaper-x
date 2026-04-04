import AppKit

protocol SteamWorkshopKeyboardDelegate: AnyObject {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool
}

final class SteamWorkshopKeyboardCollectionView: NSCollectionView {
    weak var keyboardDelegate: SteamWorkshopKeyboardDelegate?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        pendingPressReleaseWorkItem?.cancel()
        pendingPressReleaseWorkItem = nil

        if event.type == .leftMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            if let indexPath = indexPathForItem(at: point) {
                pressedCardIndexPath = indexPath
                pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
                cardPressStateHandler?(indexPath, true)
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
    }

    override func keyDown(with event: NSEvent) {
        if keyboardDelegate?.steamWorkshopCollectionView(self, handleKey: event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
