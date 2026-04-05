import Foundation
import AppKit

private final class SteamWorkshopDownloadCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var combinedOutput = ""

    nonisolated func append(_ text: String) {
        lock.lock()
        combinedOutput += text
        lock.unlock()
    }

    nonisolated func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return combinedOutput
    }
}

extension SteamWorkshopService {
    func downloadWorkshopItem(id: String, pageTitle: String? = nil) {
        let title = pageTitle ?? "Workshop #\(id)"

        guard canRequestDownload(id: id) else {
            statusMessage = "\(title) 已在下载任务中。"
            appendSteamAuthDebugLog("DOWNLOAD BLOCKED: duplicate active/queued request. requestedID=\(id)")
            return
        }

        guard !isDownloadWorkflowBusy else {
            enqueueDownloadRequest(id: id, pageTitle: pageTitle)
            return
        }

        startDownloadRequest(SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle))
    }

    func canRequestDownload(id: String) -> Bool {
        activeDownloadItemID != id
            && !isQueuedDownloadRequest(id: id)
            && pendingDownloadRequest?.id != id
    }

    private var isDownloadWorkflowBusy: Bool {
        activeDownloadItemID != nil
            || activeDownloadTask != nil
            || activeDownloadProcess != nil
            || pendingDownloadRequest != nil
            || !queuedDownloadRequests.isEmpty
            || isAuthenticating
            || isLoginSheetPresented
            || authPhase == .awaitingGuardCode
    }

    func startDownloadRequest(_ request: SteamWorkshopPendingDownloadRequest) {
        beginDownloadWorkflow(id: request.id, pageTitle: request.pageTitle)
    }

    private func beginDownloadWorkflow(id: String, pageTitle: String?) {
        let title = pageTitle ?? "Workshop #\(id)"
        activeDownloadItemID = id
        activeDownloadWasCancelled = false
        statusMessage = "已向 SteamCMD 提交 \(title) 的下载请求。"
        upsertTransientRecord(id: id, title: title, status: .downloading, sizeText: downloadStatusSizeText(for: id))
        statusMessage = "正在确认 Steam 下载环境…"
        appendSteamAuthDebugLog("=== Workshop download requested ===")
        appendSteamAuthDebugLog("Requested item id=\(id), title=\(pageTitle ?? "Workshop #\(id)")")

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                await MainActor.run {
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP: ensureManagedSteamRuntime")
                }
                try await self.ensureManagedSteamRuntime()
                try Task.checkCancellation()
                await MainActor.run {
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP OK: ensureManagedSteamRuntime")
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP: ensureAuthenticatedSessionForDownload")
                }
                try await self.ensureAuthenticatedSessionForDownload(id: id, pageTitle: pageTitle)
                try Task.checkCancellation()
                await MainActor.run {
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP OK: ensureAuthenticatedSessionForDownload")
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP: performWorkshopDownload")
                }
                try await self.performWorkshopDownload(id: id, pageTitle: pageTitle)
            } catch {
                await MainActor.run {
                    self.appendSteamAuthDebugLog("DOWNLOAD FAILED: id=\(id), error=\(self.sanitizeSteamOutput(error.localizedDescription))")
                    self.finishActiveDownloadState()
                    let message = error.localizedDescription
                    if error is SteamWorkshopDownloadControlError || error is CancellationError {
                        self.cleanupStagedDownload(id: id)
                        self.statusMessage = message
                        self.removeTransientRecord(id: id)
                        self.processNextQueuedDownloadIfPossible()
                        return
                    }
                    let nsError = error as NSError
                    if nsError.domain == "SteamWorkshop", nsError.code == 11 {
                        self.cleanupStagedDownload(id: id)
                        self.statusMessage = message
                        self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .queued, sizeText: self.downloadStatusSizeText(for: id))
                        return
                    }
                    self.cleanupStagedDownload(id: id)
                    self.downloadError = message
                    self.statusMessage = message
                    self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed(message))
                    self.processNextQueuedDownloadIfPossible()
                }
            }
        }
        activeDownloadTask = task
    }

    func ensureAuthenticatedSessionForDownload(id: String, pageTitle: String?) async throws {
        if authPhase == .awaitingGuardCode {
            pendingDownloadRequest = SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
            authStatusMessage = "当前正在等待完成 Steam 登录验证。验证通过后会自动继续刚才的下载。"
            isLoginSheetPresented = true
            throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "当前正在等待完成 Steam 登录验证。"
            ])
        }

        if isAuthenticating {
            pendingDownloadRequest = SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
            authStatusMessage = "正在静默验证当前 Steam 会话。若会话失效，将继续要求登录。"
            throw CancellationError()
        }

        guard hasSavedCredentials else {
            pendingDownloadRequest = SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
            authStatusMessage = "下载需要登录 Steam。请先完成登录，成功后会自动继续刚才的下载。"
            presentLoginGateImmediately()
            throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "下载需要登录 Steam。"
            ])
        }

        if !(await validateSavedAuthenticationSessionIfNeeded()) {
            pendingDownloadRequest = SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
            requiresLogin = false
            isAnonymousBrowsing = false
            presentLoginGateImmediately()
            throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "当前 Steam 登录态需要重新验证。"
            ])
        }
    }

    func cancelActiveDownload() {
        Task { @MainActor [weak self] in
            self?.cancelDownloadImmediately(showFeedback: true)
        }
    }

    func cancelDownload(itemID: String) {
        Task { @MainActor [weak self] in
            self?.cancelDownloadImmediately(itemID: itemID, showFeedback: true)
        }
    }

    func reloadInstalledItems() {
        let fileManager = FileManager.default
        let root = libraryRootURL
        let directories = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let metadataFiles = (try? fileManager.contentsOfDirectory(
            at: downloadMetadataIndexDirectoryURL(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        if directories.isEmpty && metadataFiles.isEmpty {
            downloads = downloads.filter {
                if case .queued = $0.status { return true }
                if case .downloading = $0.status { return true }
                if case .failed = $0.status { return true }
                return false
            }
            return
        }

        var records: [SteamWorkshopDownloadRecord] = []
        var seenIDs = Set<String>()
        for metadataFile in metadataFiles where metadataFile.pathExtension == "json" {
            let itemID = metadataFile.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: metadataFile),
                  let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data),
                  let record = buildInstalledRecord(
                    from: snapshot,
                    legacyDirectory: snapshot.legacyFolderURL,
                    fallbackProject: nil,
                    fallbackIdentifier: itemID
                  ) else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }
        for directory in directories where directory.hasDirectoryPath {
            guard let record = buildInstalledRecord(at: directory),
                  seenIDs.contains(record.id) == false else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }

        let transient = downloads.filter { record in
            switch record.status {
            case .queued, .downloading, .failed:
                return !records.contains(where: { $0.id == record.id })
            case .ready:
                return false
            }
        }

        downloads = (records + transient).sorted { $0.updatedAt > $1.updatedAt }
        if let selectedDownloadID,
           downloads.contains(where: { $0.id == selectedDownloadID }) == false {
            self.selectedDownloadID = nil
        }
        selectedDownloadIDs = selectedDownloadIDs.filter { id in
            downloads.contains(where: { $0.id == id })
        }
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func selectDownload(itemID: String?) {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let resolvedItemID = itemID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        let nextSelectedIDs = !isDownloadsMultiSelectMode
            ? (resolvedItemID.map { [$0] } ?? [])
            : selectedDownloadIDs
        applyDownloadSelectionState(
            primaryID: resolvedItemID,
            selectedIDs: nextSelectedIDs,
            forceSingleSelection: !isDownloadsMultiSelectMode
        )
    }

    func replaceSelectedDownloads(with ids: Set<String>, primaryID: String? = nil) {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let sanitized = ids.intersection(visibleIDs)
        let resolvedPrimaryID: String?
        if isDownloadsMultiSelectMode {
            if let primaryID, sanitized.contains(primaryID) {
                resolvedPrimaryID = primaryID
            } else {
                resolvedPrimaryID = firstDisplayedDownloadID(in: sanitized)
            }
        } else {
            resolvedPrimaryID = primaryID ?? firstDisplayedDownloadID(in: sanitized)
        }
        let resolvedSelectedIDs = isDownloadsMultiSelectMode
            ? sanitized
            : (resolvedPrimaryID.map { [$0] } ?? [])
        applyDownloadSelectionState(
            primaryID: resolvedPrimaryID,
            selectedIDs: resolvedSelectedIDs,
            forceSingleSelection: !isDownloadsMultiSelectMode
        )
    }

    func toggleDownloadsMultiSelectMode() {
        if isDownloadsMultiSelectMode {
            exitDownloadsMultiSelectMode()
        } else {
            enterDownloadsMultiSelectMode()
        }
    }

    func enterDownloadsMultiSelectMode() {
        isDownloadsMultiSelectMode = true
        selectedDownloadID = nil
        selectedDownloadIDs.removeAll()
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func exitDownloadsMultiSelectMode() {
        isDownloadsMultiSelectMode = false
        selectedDownloadID = nil
        selectedDownloadIDs.removeAll()
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func deleteSelectedDownload() {
        let targetIDs = Array(effectiveSelectedDownloadIDs)
        guard !targetIDs.isEmpty else { return }
        deleteDownloads(itemIDs: targetIDs)
    }

    func selectAllDownloads() {
        guard canSelectAllDownloads else { return }
        let ids = Set(displayedDownloads.map(\.id))
        replaceSelectedDownloads(with: ids, primaryID: selectedDownloadID ?? displayedDownloads.first?.id)
    }

    func revealSelectedDownload() {
        guard let record = selectedDownloadRecord else { return }
        revealItem(record)
    }

    func presentSelectedDownloadInfo() {
        guard let record = selectedDownloadRecord else { return }
        let item = record.displayItemForToolbar
        if selectedDownloadInspectorItem?.id == item.id {
            dismissDownloadInspector()
        } else {
            presentDownloadInspector(item)
        }
    }

    func presentDownloadInfo(for itemID: String) {
        guard let record = latestDownloadRecord(for: itemID) else { return }
        let item = resolvedDownloadInspectorItem(for: record)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.selectedDownloadInspectorItem?.id == item.id {
                self.dismissDownloadInspector()
            } else {
                self.presentDownloadInspector(item)
            }
        }
    }

    func dismissDownloadInspector() {
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        selectedDownloadInspectorItem = nil
        selectedDownloadDetailItem = nil
        selectedDownloadDetailError = nil
        isRefreshingSelectedDownloadDetailItem = false
    }

    func clearDownloadSelectionAndInspector() {
        selectedDownloadID = nil
        selectedDownloadIDs.removeAll()
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func syncDownloadsInspectorSelectionIfNeeded() {
        guard !isDownloadsMultiSelectMode,
              let record = selectedDownloadRecord else {
            dismissDownloadInspector()
            return
        }

        guard selectedDownloadInspectorItem != nil else {
            return
        }

        let item = resolvedDownloadInspectorItem(for: record)
        if selectedDownloadInspectorItem?.id == item.id {
            selectedDownloadInspectorItem = item
            selectedDownloadDetailItem = item
            return
        }
        presentDownloadInspector(item)
    }

    private func presentDownloadInspector(_ item: SteamWorkshopBrowserItem) {
        prioritizeUserRequestedDetail()
        selectedDownloadInspectorItem = item
        selectedDownloadDetailItem = item
        selectedDownloadDetailError = nil
        currentWorkshopItemID = item.id
        currentPageTitle = item.title
        statusMessage = "已加载 \(item.title)"
        refreshSelectedDownloadInspectorDetailIfNeeded(
            forceRefresh: SteamWorkshopDetailRefreshSupport.needsRefresh(item)
        )
    }

    private func resolvedDownloadInspectorItem(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        if let detailItem = selectedDownloadDetailItem,
           detailItem.id == record.id {
            return detailItem
        }
        return record.displayItemForToolbar
    }

    private func applyDownloadSelectionState(
        primaryID: String?,
        selectedIDs: Set<String>,
        forceSingleSelection: Bool
    ) {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let sanitizedPrimaryID = primaryID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        let normalizedSelectedIDs = forceSingleSelection
            ? (sanitizedPrimaryID.map { [$0] } ?? [])
            : selectedIDs.intersection(visibleIDs)
        let resolvedPrimaryID: String?
        if let sanitizedPrimaryID {
            resolvedPrimaryID = sanitizedPrimaryID
        } else if forceSingleSelection {
            resolvedPrimaryID = nil
        } else {
            resolvedPrimaryID = firstDisplayedDownloadID(in: normalizedSelectedIDs)
        }
        guard selectedDownloadID != resolvedPrimaryID || selectedDownloadIDs != normalizedSelectedIDs else {
            return
        }
        selectedDownloadID = resolvedPrimaryID
        selectedDownloadIDs = normalizedSelectedIDs
        syncDownloadsInspectorSelectionIfNeeded()
    }

    func deleteDownload(itemID: String) {
        deleteDownloads(itemIDs: [itemID])
    }

    private func deleteDownloads(itemIDs: [String]) {
        let uniqueIDs = Array(Set(itemIDs))
        guard !uniqueIDs.isEmpty else { return }
        var deletedTitles: [String] = []
        for itemID in uniqueIDs {
            let title = latestDownloadRecord(for: itemID)?.title
            if deleteDownloadIfPossible(itemID: itemID), let title {
                deletedTitles.append(title)
            }
        }
        reloadInstalledItems()
        if uniqueIDs.count == 1, let title = deletedTitles.first {
            statusMessage = "已移除 \(title)"
        } else if !deletedTitles.isEmpty {
            statusMessage = "已移除 \(deletedTitles.count) 个下载项"
        }
    }

    @discardableResult
    private func deleteDownloadIfPossible(itemID: String) -> Bool {
        guard let record = latestDownloadRecord(for: itemID) else { return false }
        switch record.status {
        case .queued, .downloading:
            NSSound.beep()
            return false
        case .ready, .failed:
            break
        }

        let fileManager = FileManager.default
        if let exportedVideoURL = record.exportedVideoURL,
           fileManager.fileExists(atPath: exportedVideoURL.path) {
            try? fileManager.removeItem(at: exportedVideoURL)
        }
        if let snapshot = loadExistingDownloadMetadataSnapshot(at: record.folderURL),
           let legacyFolderURL = snapshot.legacyFolderURL,
           fileManager.fileExists(atPath: legacyFolderURL.path),
           legacyFolderURL != libraryRootURL {
            try? fileManager.removeItem(at: legacyFolderURL)
        } else if fileManager.fileExists(atPath: record.folderURL.path),
                  record.folderURL != libraryRootURL,
                  record.folderURL.lastPathComponent == itemID {
            try? fileManager.removeItem(at: record.folderURL)
        }
        try? fileManager.removeItem(at: downloadMetadataFileURL(for: itemID))

        downloads.removeAll { $0.id == itemID }
        queuedDownloadRequests.removeAll { $0.id == itemID }
        if pendingDownloadRequest?.id == itemID {
            pendingDownloadRequest = nil
        }
        if selectedDownloadID == itemID {
            selectedDownloadID = nil
        }
        selectedDownloadIDs.remove(itemID)
        if !isDownloadsMultiSelectMode {
            selectedDownloadIDs = selectedDownloadID.map { [$0] } ?? []
        }
        syncDownloadsInspectorSelectionIfNeeded()
        return true
    }

    func performWorkshopDownload(id: String, pageTitle: String?) async throws {
        let title = pageTitle ?? "Workshop #\(id)"
        statusMessage = "正在通过内置 SteamCMD 下载 \(title)"
        appendSteamAuthDebugLog("DOWNLOAD BEGIN: id=\(id), title=\(title)")

        let username = steamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = try await runValidatedWorkshopDownload(
            id: id,
            title: title,
            username: username,
            pageTitle: pageTitle
        )

        let hasSuccessfulOutput = output.localizedCaseInsensitiveContains("Success. Downloaded item")
        let hasStagedContent = stagedDownloadDirectoryContainsContent(id: id)
        let hasBenignBootstrapOutput = outputIndicatesBenignSteamBootstrap(output)

        guard hasSuccessfulOutput || hasStagedContent else {
            if outputIndicatesAuthenticationFailure(output) {
                expireAuthenticationAndPromptRelogin(
                    reason: "Steam 下载认证已失效，请继续输入账号密码并完成 Guard 验证。",
                    pendingDownload: SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
                )
                throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "当前 Steam 登录态已失效，请继续登录。登录成功后会自动继续下载。"
                ])
            }
            if outputIndicatesAccessRestriction(output) {
                throw NSError(domain: "SteamWorkshop", code: 13, userInfo: [
                    NSLocalizedDescriptionKey: "当前项目可能是私有内容、权限不足，或资源暂不可用，SteamCMD 未能完成下载。"
                ])
            }
            if hasBenignBootstrapOutput {
                appendSteamAuthDebugLog("DOWNLOAD OUTPUT IGNORED: benign Steam bootstrap noise observed for id=\(id).")
            }
            throw NSError(domain: "SteamWorkshop", code: 2, userInfo: [
                NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 未返回成功下载结果。" : output
            ])
        }

        if !hasSuccessfulOutput, hasStagedContent {
            appendSteamAuthDebugLog("DOWNLOAD FALLBACK SUCCESS: staged content detected for id=\(id) despite missing success marker.")
        }

        try syncDownloadedItemToLibrary(id: id)
        appendSteamAuthDebugLog("DOWNLOAD SYNC OK: copied staged content into library for id=\(id)")

        finishActiveDownloadState()
        statusMessage = "已完成 Workshop #\(id) 下载"
        reloadInstalledItems()
        appendSteamAuthDebugLog("DOWNLOAD COMPLETE: id=\(id)")
        processNextQueuedDownloadIfPossible()
    }

    func runValidatedWorkshopDownload(
        id: String,
        title: String,
        username: String,
        pageTitle: String?
    ) async throws -> String {
        do {
            return try await runDownloadProcess(
                id: id,
                title: title,
                arguments: [
                    "+force_install_dir", runtimeInstallRootURL.path,
                    "+login", username,
                    "+workshop_download_item", Constants.workshopAppID, id, "validate",
                    "+quit"
                ]
            )
        } catch {
            let processOutput = error.localizedDescription
            guard outputIndicatesAuthenticationFailure(processOutput) || outputRequestsPassword(processOutput.localizedLowercase) else {
                throw error
            }

            authSessionState = .expired
            lastSuccessfulSessionValidationAt = nil
            let sessionRecovered = await validateSavedAuthenticationSessionIfNeeded(force: true)
            guard sessionRecovered else {
                expireAuthenticationAndPromptRelogin(
                    reason: "Steam 下载认证已失效，请继续输入账号密码并完成 Guard 验证。",
                    pendingDownload: SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
                )
                throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "当前 Steam 登录态已失效，请继续登录。登录成功后会自动继续下载。"
                ])
            }

            return try await runDownloadProcess(
                id: id,
                title: title,
                arguments: [
                    "+force_install_dir", runtimeInstallRootURL.path,
                    "+login", username,
                    "+workshop_download_item", Constants.workshopAppID, id, "validate",
                    "+quit"
                ]
            )
        }
    }

    func runDownloadProcess(id: String, title: String, arguments: [String]) async throws -> String {
        let steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
        appendSteamAuthDebugLog("DOWNLOAD PROCESS: root=\(steamRootURL.path)")
        appendSteamAuthDebugLog("DOWNLOAD PROCESS: arguments=./steamcmd.sh \(arguments.joined(separator: " "))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = steamRootURL
        process.arguments = ["./steamcmd.sh"] + arguments
        process.environment = steamProcessEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        activeDownloadWasCancelled = false
        let captureState = SteamWorkshopDownloadCaptureState()

        return try await withCheckedThrowingContinuation { continuation in
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = String(data: data, encoding: .utf8) ?? ""
                captureState.append(chunk)
                Task { @MainActor [weak self] in
                    self?.appendSteamAuthDebugLog("DOWNLOAD STDOUT: \(self?.sanitizeSteamOutput(chunk) ?? "")")
                }
            }

            process.terminationHandler = { [weak self] process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let trailingOutput = String(data: data, encoding: .utf8) ?? ""
                if !trailingOutput.isEmpty {
                    captureState.append(trailingOutput)
                }
                let output = captureState.snapshot()
                Task { @MainActor [weak self] in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    self?.activeDownloadProcess = nil
                    let completedSuccessfully =
                        output.localizedCaseInsensitiveContains("Success. Downloaded item")
                        || self?.stagedDownloadDirectoryContainsContent(id: id) == true
                    if completedSuccessfully {
                        self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS TERMINATED: success, status=\(process.terminationStatus), aggregatedOutput=\(self?.sanitizeSteamOutput(output) ?? "")")
                        continuation.resume(returning: output)
                    } else if self?.activeDownloadWasCancelled == true {
                        self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS TERMINATED: cancelled by user, status=\(process.terminationStatus)")
                        continuation.resume(throwing: SteamWorkshopDownloadControlError.cancelled)
                    } else if process.terminationStatus == 0 {
                        self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS TERMINATED: success, status=0, aggregatedOutput=\(self?.sanitizeSteamOutput(output) ?? "")")
                        continuation.resume(returning: output)
                    } else {
                        self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS TERMINATED: nonzero status=\(process.terminationStatus), output=\(self?.sanitizeSteamOutput(output) ?? "")")
                        continuation.resume(throwing: NSError(domain: "SteamWorkshop", code: Int(process.terminationStatus), userInfo: [
                            NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 执行失败，退出码 \(process.terminationStatus)。" : output
                        ]))
                    }
                }
            }

            do {
                try process.run()
                Task { @MainActor [weak self] in
                    self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS STARTED: pid=\(process.processIdentifier)")
                    self?.startActiveDownloadState(
                        id: id,
                        title: title,
                        process: process
                    )
                }
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                appendSteamAuthDebugLog("DOWNLOAD PROCESS START FAILED: \(sanitizeSteamOutput(error.localizedDescription))")
                continuation.resume(throwing: error)
            }
        }
    }

    func startActiveDownloadState(id: String, title: String, process: Process) {
        activeDownloadItemID = id
        activeDownloadProcess = process
        upsertTransientRecord(id: id, title: title, status: .downloading, sizeText: downloadStatusSizeText(for: id))
    }

    func finishActiveDownloadState() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadProcess = nil
        activeDownloadItemID = nil
        activeDownloadWasCancelled = false
    }

    func cancelDownloadImmediately(itemID: String? = nil, showFeedback: Bool) {
        if let itemID, itemID != activeDownloadItemID {
            if pendingDownloadRequest?.id == itemID {
                pendingDownloadRequest = nil
                removeTransientRecord(id: itemID)
                if showFeedback {
                    statusMessage = "已取消待验证的下载请求。"
                }
                return
            }
            guard removeQueuedDownloadRequest(id: itemID) else { return }
            removeTransientRecord(id: itemID)
            if showFeedback {
                statusMessage = "已将 \(itemID) 移出下载队列。"
            }
            return
        }

        guard activeDownloadProcess != nil || activeDownloadItemID != nil || activeDownloadTask != nil else { return }
        activeDownloadWasCancelled = true
        activeDownloadTask?.cancel()
        activeDownloadProcess?.terminate()
        if showFeedback {
            statusMessage = "正在取消当前下载…"
        }
    }

    func cleanupStagedDownload(id: String) {
        let cleanupTargets = [
            stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true),
            runtimeInstallRootURL
                .appendingPathComponent("steamapps", isDirectory: true)
                .appendingPathComponent("workshop", isDirectory: true)
                .appendingPathComponent("downloads", isDirectory: true)
                .appendingPathComponent(Constants.workshopAppID, isDirectory: true)
                .appendingPathComponent(id, isDirectory: true),
            runtimeInstallRootURL
                .appendingPathComponent("steamapps", isDirectory: true)
                .appendingPathComponent("workshop", isDirectory: true)
                .appendingPathComponent("temp", isDirectory: true)
                .appendingPathComponent(Constants.workshopAppID, isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
        ]

        for targetURL in cleanupTargets where FileManager.default.fileExists(atPath: targetURL.path) {
            appendSteamAuthDebugLog("DOWNLOAD CLEANUP: removing staged directory \(targetURL.path)")
            try? FileManager.default.removeItem(at: targetURL)
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
        steamGuardCode = ""
        requiresLogin = false
        isAnonymousBrowsing = false
        authPhase = .credentials
        authSessionState = .expired
        lastSuccessfulSessionValidationAt = nil
        authError = nil
        authStatusMessage = reason
        self.pendingDownloadRequest = pendingDownload
        if let pendingDownload {
            upsertTransientRecord(
                id: pendingDownload.id,
                title: pendingDownload.pageTitle ?? "Workshop #\(pendingDownload.id)",
                status: .queued,
                sizeText: downloadStatusSizeText(for: pendingDownload.id)
            )
        }
        isLoginSheetPresented = true
    }

    func syncDownloadedItemToLibrary(id: String) throws {
        let fileManager = FileManager.default
        let sourceURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        let targetURL = libraryRootURL.appendingPathComponent(id, isDirectory: true)
        appendSteamAuthDebugLog("DOWNLOAD SYNC: source=\(sourceURL.path)")
        appendSteamAuthDebugLog("DOWNLOAD SYNC: target=\(targetURL.path)")
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            appendSteamAuthDebugLog("DOWNLOAD SYNC FAILED: staged source directory missing for id=\(id)")
            throw NSError(domain: "SteamWorkshop", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "SteamCMD 已完成下载，但没有找到下载结果目录。"
            ])
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            appendSteamAuthDebugLog("DOWNLOAD SYNC: removing existing target directory \(targetURL.path)")
            try? fileManager.removeItem(at: targetURL)
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        } catch {
            appendSteamAuthDebugLog("DOWNLOAD SYNC FAILED: copyItem error=\(sanitizeSteamOutput(error.localizedDescription))")
            throw error
        }
        persistDownloadMetadataIfPossible(for: id, targetURL: targetURL)
    }

    private func persistDownloadMetadataIfPossible(for id: String, targetURL: URL) {
        guard let item = browserItemForDownload(id: id) else { return }
        let existingSnapshot = loadExistingDownloadMetadataSnapshot(at: targetURL)
        let project = try? JSONDecoder().decode(
            SteamWorkshopProject.self,
            from: Data(contentsOf: targetURL.appendingPathComponent("project.json"))
        )
        try? FileManager.default.createDirectory(at: downloadMetadataIndexDirectoryURL(), withIntermediateDirectories: true)
        let sourceVideoURL = resolveVideoURL(in: targetURL, preferredFileName: project?.file)
        let previewRelativePath = resolvePreviewRelativePath(in: targetURL)
        let exportedVideoURL = sourceVideoURL.flatMap {
            exportPrimaryVideoIfPossible(
                for: id,
                title: item.title,
                sourceVideoURL: $0,
                previousExportedVideoURL: existingSnapshot?.exportedVideoURL
            )
        }
        let sourceVideoRelativePath = sourceVideoURL.map { url in
            let basePath = targetURL.standardizedFileURL.path
            let filePath = url.standardizedFileURL.path
            if filePath.hasPrefix(basePath + "/") {
                return String(filePath.dropFirst(basePath.count + 1))
            }
            return url.lastPathComponent
        }
        let snapshot = SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: Date(),
            item: item,
            sourceVideoRelativePath: sourceVideoRelativePath,
            previewRelativePath: previewRelativePath,
            exportedVideoURL: exportedVideoURL,
            legacyFolderURL: targetURL
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: downloadMetadataFileURL(for: id), options: Data.WritingOptions.atomic)
    }

    private func loadExistingDownloadMetadataSnapshot(at directory: URL) -> SteamWorkshopDownloadMetadataSnapshot? {
        let identifier = directory.lastPathComponent
        let indexedURL = downloadMetadataFileURL(for: identifier)
        if let data = try? Data(contentsOf: indexedURL),
           let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) {
            return snapshot
        }
        let legacyURL = Self.legacyDownloadMetadataFileURL(for: directory)
        guard let data = try? Data(contentsOf: legacyURL),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private func resolvePreviewRelativePath(in directory: URL) -> String? {
        let projectURL = directory.appendingPathComponent("project.json")
        let project = try? JSONDecoder().decode(SteamWorkshopProject.self, from: Data(contentsOf: projectURL))
        if let preview = project?.preview {
            let candidate = directory.appendingPathComponent(preview)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return preview
            }
        }
        let candidates = ["preview.jpg", "preview.jpeg", "preview.png", "preview.gif"]
        for candidateName in candidates {
            let candidate = directory.appendingPathComponent(candidateName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidateName
            }
        }
        return nil
    }

    private func exportPrimaryVideoIfPossible(
        for id: String,
        title: String,
        sourceVideoURL: URL,
        previousExportedVideoURL: URL?
    ) -> URL? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: exportedVideosRootURL, withIntermediateDirectories: true)

        let sanitizedBaseName = sanitizedExportFileName(from: title).isEmpty
            ? "Workshop-\(id)"
            : sanitizedExportFileName(from: title)
        let destinationURL = uniqueExportURL(
            baseName: sanitizedBaseName,
            pathExtension: sourceVideoURL.pathExtension,
            preferredExistingURL: previousExportedVideoURL
        )

        let shouldReplaceExisting = previousExportedVideoURL == destinationURL
            || destinationURL == previousExportedVideoURL
        if let previousExportedVideoURL,
           previousExportedVideoURL != destinationURL,
           fileManager.fileExists(atPath: previousExportedVideoURL.path) {
            try? fileManager.removeItem(at: previousExportedVideoURL)
        }

        if fileManager.fileExists(atPath: destinationURL.path), shouldReplaceExisting {
            try? fileManager.removeItem(at: destinationURL)
        }

        if !fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try fileManager.copyItem(at: sourceVideoURL, to: destinationURL)
            } catch {
                appendSteamAuthDebugLog("DOWNLOAD EXPORT FAILED: id=\(id), error=\(sanitizeSteamOutput(error.localizedDescription))")
                return previousExportedVideoURL.flatMap { fileManager.fileExists(atPath: $0.path) ? $0 : nil }
            }
        }
        return destinationURL
    }

    private func uniqueExportURL(
        baseName: String,
        pathExtension: String,
        preferredExistingURL: URL?
    ) -> URL {
        let fileManager = FileManager.default
        if let preferredExistingURL,
           preferredExistingURL.deletingLastPathComponent() == exportedVideosRootURL {
            return preferredExistingURL
        }

        let normalizedExtension = pathExtension.isEmpty ? "mp4" : pathExtension
        var index = 0
        while true {
            let candidateName = index == 0
                ? "\(baseName).\(normalizedExtension)"
                : "\(baseName) (\(index)).\(normalizedExtension)"
            let candidateURL = exportedVideosRootURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private func sanitizedExportFileName(from title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let collapsed = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(120))
    }

    private func stagedDownloadDirectoryContainsContent(id: String) -> Bool {
        let sourceURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              let items = try? FileManager.default.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }
        return !items.isEmpty
    }

    private func enqueueDownloadRequest(id: String, pageTitle: String?) {
        let request = SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle)
        queuedDownloadRequests.append(request)
        upsertTransientRecord(
            id: id,
            title: pageTitle ?? "Workshop #\(id)",
            status: .queued,
            sizeText: downloadStatusSizeText(for: id)
        )
        statusMessage = "已将 \(pageTitle ?? "Workshop #\(id)") 加入下载队列。"
    }

    private func processNextQueuedDownloadIfPossible() {
        guard activeDownloadItemID == nil,
              activeDownloadTask == nil,
              pendingDownloadRequest == nil,
              !isLoginSheetPresented,
              authPhase != .awaitingGuardCode,
              !isAuthenticating,
              !queuedDownloadRequests.isEmpty else { return }

        let next = queuedDownloadRequests.removeFirst()
        startDownloadRequest(next)
    }

    private func removeQueuedDownloadRequest(id: String) -> Bool {
        guard let index = queuedDownloadRequests.firstIndex(where: { $0.id == id }) else { return false }
        queuedDownloadRequests.remove(at: index)
        return true
    }

    private func isQueuedDownloadRequest(id: String) -> Bool {
        queuedDownloadRequests.contains(where: { $0.id == id })
    }

    private func downloadStatusSizeText(for id: String) -> String {
        if let existing = latestDownloadRecord(for: id)?.sizeText, !existing.isEmpty {
            return existing
        }
        if let browserSize = browserItemForDownload(id: id)?.fileSizeText, !browserSize.isEmpty {
            return browserSize
        }
        return "未知大小"
    }

    private func removeTransientRecord(id: String) {
        downloads.removeAll { record in
            record.id == id && record.status != .ready
        }
    }
}
