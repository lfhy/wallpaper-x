import Foundation

enum SteamWorkshopDetailRequestPriority {
    case userInitiated
    case background
}

actor SteamWorkshopDetailRequestScheduler {
    static let shared = SteamWorkshopDetailRequestScheduler()

    private var activeUserRequests = 0
    private var activeBackgroundRequests = 0
    private var waitingUserRequests: [CheckedContinuation<Void, Never>] = []
    private var waitingBackgroundRequests: [CheckedContinuation<Void, Never>] = []

    func run<T>(
        priority: SteamWorkshopDetailRequestPriority,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire(priority: priority)
        defer { release(priority: priority) }
        return try await operation()
    }

    private func acquire(priority: SteamWorkshopDetailRequestPriority) async {
        while !canAcquire(priority: priority) {
            await withCheckedContinuation { continuation in
                switch priority {
                case .userInitiated:
                    waitingUserRequests.append(continuation)
                case .background:
                    waitingBackgroundRequests.append(continuation)
                }
            }
        }

        switch priority {
        case .userInitiated:
            activeUserRequests += 1
        case .background:
            activeBackgroundRequests += 1
        }
    }

    private func canAcquire(priority: SteamWorkshopDetailRequestPriority) -> Bool {
        switch priority {
        case .userInitiated:
            return activeUserRequests == 0
        case .background:
            return activeBackgroundRequests == 0 && activeUserRequests == 0 && waitingUserRequests.isEmpty
        }
    }

    private func release(priority: SteamWorkshopDetailRequestPriority) {
        switch priority {
        case .userInitiated:
            activeUserRequests = max(0, activeUserRequests - 1)
        case .background:
            activeBackgroundRequests = max(0, activeBackgroundRequests - 1)
        }
        resumeNextIfPossible()
    }

    private func resumeNextIfPossible() {
        if activeUserRequests == 0, let continuation = waitingUserRequests.first {
            waitingUserRequests.removeFirst()
            continuation.resume()
            return
        }

        if activeUserRequests == 0,
           activeBackgroundRequests == 0,
           let continuation = waitingBackgroundRequests.first {
            waitingBackgroundRequests.removeFirst()
            continuation.resume()
        }
    }
}
