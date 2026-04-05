import Foundation

enum SteamWorkshopPreviewRequestPriority {
    case userInitiated
    case visible
    case prefetch
}

final class SteamWorkshopPreviewRequestCoordinator {
    static let shared = SteamWorkshopPreviewRequestCoordinator()

    private let session: URLSession
    private let scheduler = SteamWorkshopPreviewRequestScheduler()
    private let stateQueue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.steamworkshop.preview.failures")
    private var failureStates: [String: FailureState] = [:]
    private var suspiciousCacheKeys = Set<String>()

    private struct FailureState {
        var attempts: Int
        var retryAfter: Date
        var isPermanent: Bool
    }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func loadDataSynchronously(
        from url: URL,
        priority: SteamWorkshopPreviewRequestPriority
    ) -> Data? {
        guard shouldAttemptLoad(for: url, priority: priority) else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var loadedData: Data?

        Task {
            do {
                let data = try await fetchData(from: url, priority: priority)
                noteSuccess(for: url)
                loadedData = data
            } catch {
                noteFailure(for: url, error: error, priority: priority)
                loadedData = nil
            }
            semaphore.signal()
        }

        semaphore.wait()
        return loadedData
    }

    func prefetchDataSynchronously(from url: URL) -> Data? {
        loadDataSynchronously(from: url, priority: .prefetch)
    }

    func loadData(
        from url: URL,
        priority: SteamWorkshopPreviewRequestPriority,
        ignoringBackoff: Bool = false
    ) async -> Data? {
        if !ignoringBackoff, !shouldAttemptLoad(for: url, priority: priority) {
            return nil
        }
        do {
            let data = try await fetchData(from: url, priority: priority)
            noteSuccess(for: url)
            return data
        } catch {
            noteFailure(for: url, error: error, priority: priority)
            return nil
        }
    }

    func nextRetryDelay(
        for url: URL,
        priority: SteamWorkshopPreviewRequestPriority
    ) -> TimeInterval? {
        stateQueue.sync {
            guard let state = failureStates[url.absoluteString] else { return nil }
            if priority == .userInitiated {
                return 0
            }
            return max(0, state.retryAfter.timeIntervalSinceNow)
        }
    }

    func shouldBypassCachedImage(forKey key: String) -> Bool {
        stateQueue.sync {
            suspiciousCacheKeys.contains(key)
        }
    }

    func markCachedImageSuspicious(forKey key: String) {
        stateQueue.async {
            self.suspiciousCacheKeys.insert(key)
        }
    }

    func clearCachedImageSuspicion(forKey key: String) {
        stateQueue.async {
            self.suspiciousCacheKeys.remove(key)
        }
    }

    private func fetchData(
        from url: URL,
        priority: SteamWorkshopPreviewRequestPriority
    ) async throws -> Data {
        try await scheduler.run(priority: priority) { [session] in
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout(for: priority)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0",
                forHTTPHeaderField: "User-Agent"
            )
            switch priority {
            case .userInitiated:
                request.networkServiceType = .responsiveData
            case .visible:
                request.networkServiceType = .responsiveData
            case .prefetch:
                request.networkServiceType = .background
            }

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    nonisolated private func timeout(for priority: SteamWorkshopPreviewRequestPriority) -> TimeInterval {
        switch priority {
        case .userInitiated:
            return 20
        case .visible:
            return 18
        case .prefetch:
            return 15
        }
    }

    private func shouldAttemptLoad(
        for url: URL,
        priority: SteamWorkshopPreviewRequestPriority
    ) -> Bool {
        stateQueue.sync {
            guard let state = failureStates[url.absoluteString] else { return true }
            if priority == .userInitiated {
                return true
            }
            return Date() >= state.retryAfter
        }
    }

    private func noteSuccess(for url: URL) {
        stateQueue.async {
            self.failureStates.removeValue(forKey: url.absoluteString)
        }
    }

    private func noteFailure(
        for url: URL,
        error: Error,
        priority: SteamWorkshopPreviewRequestPriority
    ) {
        let key = url.absoluteString
        stateQueue.async {
            let now = Date()
            let prior = self.failureStates[key]
            let nextAttempts = (prior?.attempts ?? 0) + 1
            let nsError = error as NSError
            let statusCode = nsError.code
            let isPermanent = statusCode == 404 || statusCode == NSURLErrorFileDoesNotExist
            let delay: TimeInterval
            if isPermanent {
                delay = 60 * 10
            } else {
                switch priority {
                case .userInitiated:
                    delay = min(12, pow(2, Double(min(nextAttempts, 3))))
                case .visible:
                    delay = min(30, pow(2, Double(min(nextAttempts + 1, 4))))
                case .prefetch:
                    delay = min(90, pow(2, Double(min(nextAttempts + 2, 5))))
                }
            }
            self.failureStates[key] = FailureState(
                attempts: nextAttempts,
                retryAfter: now.addingTimeInterval(delay),
                isPermanent: isPermanent
            )
        }
    }
}

actor SteamWorkshopPreviewRequestScheduler {
    private var activeForegroundRequests = 0
    private var activePrefetchRequests = 0
    private var waitingForegroundRequests: [CheckedContinuation<Void, Never>] = []
    private var waitingPrefetchRequests: [CheckedContinuation<Void, Never>] = []

    func run<T>(
        priority: SteamWorkshopPreviewRequestPriority,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire(priority: priority)
        defer { release(priority: priority) }
        return try await operation()
    }

    private func acquire(priority: SteamWorkshopPreviewRequestPriority) async {
        while !canAcquire(priority: priority) {
            await withCheckedContinuation { continuation in
                switch priority {
                case .userInitiated, .visible:
                    waitingForegroundRequests.append(continuation)
                case .prefetch:
                    waitingPrefetchRequests.append(continuation)
                }
            }
        }

        switch priority {
        case .userInitiated, .visible:
            activeForegroundRequests += 1
        case .prefetch:
            activePrefetchRequests += 1
        }
    }

    private func canAcquire(priority: SteamWorkshopPreviewRequestPriority) -> Bool {
        switch priority {
        case .userInitiated, .visible:
            return activeForegroundRequests < 2
        case .prefetch:
            return activeForegroundRequests == 0 && activePrefetchRequests == 0 && waitingForegroundRequests.isEmpty
        }
    }

    private func release(priority: SteamWorkshopPreviewRequestPriority) {
        switch priority {
        case .userInitiated, .visible:
            activeForegroundRequests = max(0, activeForegroundRequests - 1)
        case .prefetch:
            activePrefetchRequests = max(0, activePrefetchRequests - 1)
        }
        resumeNextIfPossible()
    }

    private func resumeNextIfPossible() {
        while activeForegroundRequests < 2, !waitingForegroundRequests.isEmpty {
            let continuation = waitingForegroundRequests.removeFirst()
            continuation.resume()
        }

        if activeForegroundRequests == 0,
           activePrefetchRequests == 0,
           waitingForegroundRequests.isEmpty,
           let continuation = waitingPrefetchRequests.first {
            waitingPrefetchRequests.removeFirst()
            continuation.resume()
        }
    }
}
