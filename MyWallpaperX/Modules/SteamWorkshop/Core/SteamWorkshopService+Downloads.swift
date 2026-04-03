import Foundation

extension SteamWorkshopService {
    func downloadWorkshopItem(id: String, pageTitle: String? = nil) {
        guard activeDownloadItemID == nil else {
            statusMessage = "已有下载任务在执行，请稍候。"
            return
        }

        guard !requiresLogin && hasSavedCredentials else {
            pendingDownloadRequest = SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
            authStatusMessage = "下载需要登录 Steam。请先完成登录，成功后会自动继续刚才的下载。"
            presentLoginGate()
            return
        }

        statusMessage = "正在确认 Steam 下载环境…"

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureManagedSteamRuntime()
                try await self.performWorkshopDownload(id: id, pageTitle: pageTitle)
            } catch {
                await MainActor.run {
                    self.finishActiveDownloadState()
                    let message = error.localizedDescription
                    if error is SteamWorkshopDownloadControlError {
                        self.cleanupStagedDownload(id: id)
                        self.statusMessage = message
                        self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed(message), sizeText: "已取消")
                        return
                    }
                    let nsError = error as NSError
                    if nsError.domain == "SteamWorkshop", nsError.code == 11 {
                        self.cleanupStagedDownload(id: id)
                        self.statusMessage = message
                        self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed("登录已过期"), sizeText: "等待重新登录")
                        return
                    }
                    self.cleanupStagedDownload(id: id)
                    self.downloadError = message
                    self.statusMessage = message
                    self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed(message))
                }
            }
        }
    }

    func cancelActiveDownload() {
        Task { @MainActor [weak self] in
            self?.cancelDownloadImmediately(showFeedback: true)
        }
    }

    func reloadInstalledItems() {
        let fileManager = FileManager.default
        let root = libraryRootURL
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            downloads = downloads.filter {
                if case .downloading = $0.status { return true }
                if case .failed = $0.status { return true }
                return false
            }
            return
        }

        var records: [SteamWorkshopDownloadRecord] = []
        for directory in directories where directory.hasDirectoryPath {
            guard let record = buildInstalledRecord(at: directory) else { continue }
            records.append(record)
        }

        let transient = downloads.filter { record in
            switch record.status {
            case .downloading, .failed:
                return !records.contains(where: { $0.id == record.id })
            case .ready:
                return false
            }
        }

        downloads = (records + transient).sorted { $0.updatedAt > $1.updatedAt }
    }

    func performWorkshopDownload(id: String, pageTitle: String?) async throws {
        let title = pageTitle ?? "Workshop #\(id)"
        let expectedBytes = expectedDownloadBytes(for: id)
        statusMessage = "正在通过内置 SteamCMD 下载 \(title)"

        let output: String
        do {
            output = try await runDownloadProcess(
                id: id,
                title: title,
                expectedBytes: expectedBytes,
                arguments: [
                    "+force_install_dir", runtimeInstallRootURL.path,
                    "+login", steamUsername, steamPassword,
                    "+workshop_download_item", Constants.workshopAppID, id, "validate",
                    "+quit"
                ]
            )
        } catch {
            let processOutput = error.localizedDescription
            if outputIndicatesAuthenticationFailure(processOutput) {
                expireAuthenticationAndPromptRelogin(
                    reason: "Steam 下载认证已失效，请重新输入账号密码并完成 Guard 验证。",
                    pendingDownload: SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
                )
                throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "当前 Steam 登录态已失效，请重新登录。登录成功后会自动继续下载。"
                ])
            }
            throw error
        }

        guard output.localizedCaseInsensitiveContains("Success. Downloaded item") else {
            if outputIndicatesAuthenticationFailure(output) {
                expireAuthenticationAndPromptRelogin(
                    reason: "Steam 下载认证已失效，请重新输入账号密码并完成 Guard 验证。",
                    pendingDownload: SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
                )
                throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "当前 Steam 登录态已失效，请重新登录。登录成功后会自动继续下载。"
                ])
            }
            throw NSError(domain: "SteamWorkshop", code: 2, userInfo: [
                NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 未返回成功下载结果。" : output
            ])
        }

        try syncDownloadedItemToLibrary(id: id)

        finishActiveDownloadState()
        statusMessage = "已完成 Workshop #\(id) 下载"
        reloadInstalledItems()
    }

    func runDownloadProcess(id: String, title: String, expectedBytes: Int64?, arguments: [String]) async throws -> String {
        let steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = steamRootURL
        process.arguments = ["./steamcmd.sh"] + arguments
        process.environment = steamProcessEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        activeDownloadWasCancelled = false

        return try await withCheckedThrowingContinuation { continuation in
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = String(data: data, encoding: .utf8) ?? ""
                Task { @MainActor [weak self] in
                    self?.appendSteamAuthDebugLog("DOWNLOAD STDOUT: \(self?.sanitizeSteamOutput(chunk) ?? "")")
                }
            }

            process.terminationHandler = { [weak self] process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                Task { @MainActor [weak self] in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    self?.stopDownloadMonitor()
                    self?.activeDownloadProcess = nil
                    self?.activeDownloadPipe = nil
                    if self?.activeDownloadWasCancelled == true {
                        continuation.resume(throwing: SteamWorkshopDownloadControlError.cancelled)
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: NSError(domain: "SteamWorkshop", code: Int(process.terminationStatus), userInfo: [
                            NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 执行失败，退出码 \(process.terminationStatus)。" : output
                        ]))
                    }
                }
            }

            do {
                try process.run()
                Task { @MainActor [weak self] in
                    self?.startActiveDownloadState(
                        id: id,
                        title: title,
                        expectedBytes: expectedBytes,
                        process: process,
                        pipe: outputPipe
                    )
                }
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func startActiveDownloadState(id: String, title: String, expectedBytes: Int64?, process: Process, pipe: Pipe) {
        activeDownloadItemID = id
        activeDownloadProcess = process
        activeDownloadPipe = pipe
        activeDownloadExpectedBytes = expectedBytes
        activeDownloadProgressFraction = 0
        activeDownloadProgressText = expectedBytes.map { "0 MB / \(Self.fileSizeText(forBytes: $0))" } ?? "0 MB"
        upsertTransientRecord(id: id, title: title, status: .downloading, sizeText: activeDownloadProgressText ?? "0 MB")
        startDownloadMonitor(for: id)
    }

    func finishActiveDownloadState() {
        stopDownloadMonitor()
        activeDownloadProcess = nil
        activeDownloadPipe = nil
        activeDownloadExpectedBytes = nil
        activeDownloadItemID = nil
        activeDownloadProgressFraction = nil
        activeDownloadProgressText = nil
        activeDownloadWasCancelled = false
    }

    func cancelDownloadImmediately(showFeedback: Bool) {
        guard activeDownloadProcess != nil || activeDownloadItemID != nil else { return }
        activeDownloadWasCancelled = true
        activeDownloadProcess?.terminate()
        stopDownloadMonitor()
        if showFeedback {
            statusMessage = "正在取消当前下载…"
        }
    }

    func startDownloadMonitor(for id: String) {
        stopDownloadMonitor()
        activeDownloadMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.refreshDownloadProgress(for: id)
                }
            }
        }
    }

    func stopDownloadMonitor() {
        activeDownloadMonitorTask?.cancel()
        activeDownloadMonitorTask = nil
    }

    func refreshDownloadProgress(for id: String) {
        guard activeDownloadItemID == id else { return }
        let downloadedBytes = directorySize(at: stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true))
        let downloadedText = Self.fileSizeText(forBytes: downloadedBytes)
        if let expectedBytes = activeDownloadExpectedBytes, expectedBytes > 0 {
            let fraction = min(max(Double(downloadedBytes) / Double(expectedBytes), 0), 1)
            activeDownloadProgressFraction = fraction
            activeDownloadProgressText = "\(downloadedText) / \(Self.fileSizeText(forBytes: expectedBytes))"
        } else {
            activeDownloadProgressFraction = nil
            activeDownloadProgressText = downloadedText
        }

        if let title = browserItems.first(where: { $0.id == id })?.title
            ?? selectedBrowserItem?.title
            ?? downloads.first(where: { $0.id == id })?.title {
            upsertTransientRecord(id: id, title: title, status: .downloading, sizeText: activeDownloadProgressText ?? downloadedText)
        }
    }

    func directorySize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    func cleanupStagedDownload(id: String) {
        let stagedURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: stagedURL.path) {
            try? FileManager.default.removeItem(at: stagedURL)
        }
    }

    func expectedDownloadBytes(for id: String) -> Int64? {
        if let item = browserItems.first(where: { $0.id == id }) {
            return Self.parseByteCount(from: item.fileSizeText)
        }
        if selectedBrowserItem?.id == id {
            return Self.parseByteCount(from: selectedBrowserItem?.fileSizeText)
        }
        return nil
    }

    func expireAuthenticationAndPromptRelogin(reason: String, pendingDownload: SteamWorkshopPendingDownloadRequest?) {
        cancelActiveLoginSession()
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        SteamWorkshopCredentialStore.deletePassword()
        steamPassword = ""
        steamGuardCode = ""
        requiresLogin = true
        isAnonymousBrowsing = true
        authPhase = .credentials
        authError = nil
        authStatusMessage = reason
        self.pendingDownloadRequest = pendingDownload
        isLoginSheetPresented = true
    }

    func syncDownloadedItemToLibrary(id: String) throws {
        let fileManager = FileManager.default
        let sourceURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        let targetURL = libraryRootURL.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "SteamWorkshop", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "SteamCMD 已完成下载，但没有找到下载结果目录。"
            ])
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)
    }
}
