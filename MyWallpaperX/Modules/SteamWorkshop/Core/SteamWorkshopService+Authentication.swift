import Foundation

extension SteamWorkshopService {
    func authenticateUser() {
        Task { @MainActor [weak self] in
            self?.authenticateUserImmediately()
        }
    }

    func authenticateUserImmediately() {
        guard !steamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authError = "请输入 Steam 用户名。"
            return
        }
        guard !steamPassword.isEmpty else {
            authError = "请输入 Steam 密码。"
            return
        }

        let username = steamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = steamPassword
        cancelActiveLoginSession()
        isAnonymousBrowsing = false
        authPhase = .credentials
        isAuthenticating = true
        authError = nil
        authStatusMessage = "正在启动内置 SteamCMD，并向 Steam 发起登录请求…"

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureManagedSteamRuntime()
                await MainActor.run {
                    self.beginInteractiveSteamLogin(username: username, password: password)
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.authError = error.localizedDescription
                    self.authStatusMessage = "SteamCMD 启动失败，请检查随 App 打包的运行资源。"
                }
            }
        }
    }

    func submitSteamGuardCode() {
        Task { @MainActor [weak self] in
            self?.submitSteamGuardCodeImmediately()
        }
    }

    func submitSteamGuardCodeImmediately() {
        let guardCode = steamGuardCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authPhase == .awaitingGuardCode else {
            authError = "当前没有等待输入的 Steam Guard 验证。"
            return
        }
        guard !guardCode.isEmpty else {
            authError = "请输入 Steam Guard 令牌。"
            return
        }
        guard let inputHandle = loginInputHandle else {
            authError = "登录会话已失效，请重新输入账号和密码。"
            authPhase = .credentials
            isAuthenticating = false
            return
        }

        authError = nil
        isAuthenticating = true
        authStatusMessage = "正在验证 Steam Guard 令牌…"
        inputHandle.write(Data("\(guardCode)\r".utf8))
    }

    func browseAnonymously() {
        Task { @MainActor [weak self] in
            self?.browseAnonymouslyImmediately()
        }
    }

    func browseAnonymouslyImmediately() {
        cancelActiveLoginSession()
        requiresLogin = !hasSavedCredentials
        isAnonymousBrowsing = true
        authPhase = .credentials
        authError = nil
        isAuthenticating = false
        isLoginSheetPresented = false
        authStatusMessage = "当前为匿名浏览模式：可以查看创意工坊视频列表，下载前需要先登录 Steam。"
        fetchBrowserItems()
    }

    func presentLoginGate() {
        Task { @MainActor [weak self] in
            self?.presentLoginGateImmediately()
        }
    }

    func presentLoginGateImmediately() {
        cancelActiveLoginSession()
        authPhase = .credentials
        isAuthenticating = false
        steamGuardCode = ""
        authError = nil
        isLoginSheetPresented = false

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isPreparingRuntime = true
                self.authStatusMessage = "正在准备 SteamCMD 运行环境…"
            }

            do {
                try await self.ensureManagedSteamRuntime()
                await MainActor.run {
                    self.isPreparingRuntime = false
                    self.authStatusMessage = "请输入 Steam 账号密码。若 Steam 要求验证，下一步再填写 Guard 令牌。"
                    self.isLoginSheetPresented = true
                }
            } catch {
                await MainActor.run {
                    self.isPreparingRuntime = false
                    self.authError = error.localizedDescription
                    self.authStatusMessage = "SteamCMD 启动失败，请检查随 App 打包的运行资源。"
                }
            }
        }
    }

    func logout() {
        Task { @MainActor [weak self] in
            self?.logoutImmediately()
        }
    }

    func logoutImmediately() {
        cancelActiveLoginSession()
        cancelDownloadImmediately(showFeedback: false)
        defaults.removeObject(forKey: Constants.defaultsLastUsername)
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        SteamWorkshopCredentialStore.deletePassword()
        pendingDownloadRequest = nil
        steamUsername = ""
        steamPassword = ""
        steamGuardCode = ""
        requiresLogin = true
        isAnonymousBrowsing = true
        authPhase = .credentials
        isLoginSheetPresented = false
        authError = nil
        authStatusMessage = "已退出当前 Steam 登录态。"
    }

    func loadAuthenticationState() {
        let storedUsername = defaults.string(forKey: Constants.defaultsLastUsername) ?? ""
        let storedPassword = SteamWorkshopCredentialStore.loadPassword() ?? ""
        steamUsername = storedUsername
        steamPassword = storedPassword
        requiresLogin = storedUsername.isEmpty || storedPassword.isEmpty
        isAnonymousBrowsing = requiresLogin
        authPhase = requiresLogin ? .credentials : .authenticated
        if requiresLogin {
            authStatusMessage = "当前还没有可复用的 Steam 登录凭据。可以先匿名浏览，需要下载时再登录。"
        } else if let lastAuthenticatedAt = defaults.object(forKey: Constants.defaultsLastAuthenticatedAt) as? Date {
            authStatusMessage = "已检测到上次成功登录的 Steam 凭据。下载时会优先直接复用；如果远端会话已失效，再提示你重新登录。上次成功登录时间：\(lastAuthenticatedAt.formatted(date: .abbreviated, time: .shortened))。"
        } else {
            authStatusMessage = "已检测到可复用的 Steam 凭据。下载时会优先直接复用；如果远端会话失效，再提示你重新登录。"
        }
    }

    func saveAuthenticationState(username: String, password: String) {
        defaults.set(username, forKey: Constants.defaultsLastUsername)
        defaults.set(Date(), forKey: Constants.defaultsLastAuthenticatedAt)
        SteamWorkshopCredentialStore.save(password: password)
        requiresLogin = false
        isAnonymousBrowsing = false
        authPhase = .authenticated
    }

    var hasSavedCredentials: Bool {
        !steamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !steamPassword.isEmpty
    }

    func prepareRuntimeIfNeeded() async {
        await MainActor.run {
            self.isPreparingRuntime = true
            self.statusMessage = "正在检查 SteamCMD 环境…"
        }

        do {
            try await ensureManagedSteamRuntime()
            await MainActor.run {
                self.isPreparingRuntime = false
                if self.browserState == .idle {
                    self.statusMessage = "SteamCMD 环境已就绪，正在加载创意工坊列表…"
                }
            }
        } catch {
            await MainActor.run {
                self.isPreparingRuntime = false
                self.requiresLogin = true
                self.isAnonymousBrowsing = true
                self.authPhase = .credentials
                self.authError = error.localizedDescription
                self.authStatusMessage = "SteamCMD 环境准备失败。"
            }
            return
        }
    }

    func ensureManagedSteamRuntime() async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: libraryRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimeInstallRootURL, withIntermediateDirectories: true)

        guard let bundledSteamRootURL,
              validateSteamRuntime(at: bundledSteamRootURL) else {
            throw NSError(domain: "SteamWorkshop", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "App 包内没有找到可用的 SteamCMD 基线资源。"
            ])
        }

        steamRuntimeUpdateStatus = "当前直接运行 App 内置 SteamCMD 基线版本。后续 SteamCMD 升级将随应用更新一起分发。"
    }

    func runSteamProcess(arguments: [String], stdinText: String? = nil) async throws -> String {
        let steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.currentDirectoryURL = steamRootURL
            process.arguments = ["./steamcmd.sh"] + arguments
            process.environment = steamProcessEnvironment()

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            let inputPipe = Pipe()
            process.standardInput = inputPipe

            process.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(domain: "SteamWorkshop", code: Int(process.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 执行失败，退出码 \(process.terminationStatus)。" : output
                    ]))
                }
            }

            do {
                try process.run()
                if let stdinText, !stdinText.isEmpty {
                    inputPipe.fileHandleForWriting.write(Data(stdinText.utf8))
                    try? inputPipe.fileHandleForWriting.close()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func beginInteractiveSteamLogin(username: String, password: String) {
        resetSteamAuthDebugLog()
        loginSessionID = UUID().uuidString.lowercased()
        appendSteamAuthDebugLog("=== Steam login session started ===")
        appendSteamAuthDebugLog("Session ID: \(loginSessionID)")
        appendSteamAuthDebugLog("Local time: \(Date().formatted(date: .complete, time: .standard))")
        appendSteamAuthDebugLog("Bundle path: \(Bundle.main.bundleURL.path)")
        appendSteamAuthDebugLog("Log file path: \(steamAuthDebugLogURL.path)")
        appendSteamAuthDebugLog("Execution mode: app -> /bin/bash ./steamcmd.sh")
        pendingLoginUsername = username
        pendingLoginPassword = password
        pendingLoginCommand = "login \(username) \(password)\r"
        appendSteamAuthDebugLog("Prepared command: \(redactedLoginCommand(username: username, password: password))")
        steamGuardCode = ""
        loginPasswordSent = false
        loginSucceeded = false
        loginOutputBuffer = ""

        let process = Process()
        let steamRootURL: URL
        do {
            steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
            appendSteamAuthDebugLog("Resolved runtime root: \(steamRootURL.path)")
        } catch {
            appendSteamAuthDebugLog("Failed to resolve runtime root: \(error.localizedDescription)")
            isAuthenticating = false
            authError = error.localizedDescription
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
            return
        }

        let pty: SteamWorkshopPTYSession
        do {
            pty = try makeSteamPTYSession()
            appendSteamAuthDebugLog("Created local PTY session for interactive login.")
        } catch {
            appendSteamAuthDebugLog("Failed to create local PTY: \(error.localizedDescription)")
            isAuthenticating = false
            authError = "无法创建 SteamCMD 交互会话。"
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
            return
        }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = steamRootURL
        process.arguments = ["./steamcmd.sh"]
        process.environment = steamProcessEnvironment()
        process.standardInput = pty.slave
        process.standardOutput = pty.slave
        process.standardError = pty.slave
        appendSteamAuthDebugLog("Launch path: /bin/bash")
        appendSteamAuthDebugLog("Launch arguments: ./steamcmd.sh")

        pty.master.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in
                self?.handleInteractiveLoginOutput(chunk)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.appendSteamAuthDebugLog("Process terminated with status \(process.terminationStatus).")
                try? pty.master.close()
                try? pty.slave.close()
                self?.handleInteractiveLoginTermination(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
            appendSteamAuthDebugLog("Process started successfully.")
            loginProcess = process
            loginInputHandle = pty.master
            loginOutputHandle = pty.master
            authStatusMessage = "SteamCMD 已启动，正在等待控制台就绪…"
            loginBootstrapTimeoutTask?.cancel()
            loginBootstrapTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self,
                          !self.loginPasswordSent,
                          self.authPhase == .credentials else { return }
                    self.appendSteamAuthDebugLog("Bootstrap timeout reached before Steam prompt was observed.")
                    self.finalizeInteractiveLoginFailure(message: "SteamCMD 控制台未进入可登录状态，登录命令没有被执行。")
                }
            }
        } catch {
            try? pty.master.close()
            try? pty.slave.close()
            appendSteamAuthDebugLog("Process start failed: \(error.localizedDescription)")
            isAuthenticating = false
            authError = error.localizedDescription
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
        }
    }

    func handleInteractiveLoginOutput(_ chunk: String) {
        loginOutputBuffer.append(chunk)
        let lowered = loginOutputBuffer.localizedLowercase
        appendSteamAuthDebugLog("STDOUT chunk: \(sanitizeSteamOutput(chunk))")

        if lowered.contains("createboundsocket") {
            appendSteamAuthDebugLog("Observed network socket bind failure while SteamCMD attempted to connect.")
        }

        if lowered.contains("error (no connection)") {
            appendSteamAuthDebugLog("SteamCMD reported ERROR (No Connection) and returned to the Steam prompt.")
        }

        if !loginPasswordSent,
           lowered.contains("steam>") {
            appendSteamAuthDebugLog("Detected Steam prompt. About to send login command.")
            sendPendingLoginCommandIfPossible()
        }

        if authPhase != .awaitingGuardCode, outputRequestsGuardCode(lowered) {
            authPhase = .awaitingGuardCode
            isAuthenticating = false
            authStatusMessage = "Steam 已要求进行 Steam Guard 验证，请输入刚收到的令牌。"
            return
        }

        if outputIndicatesLoginSuccess(lowered) {
            finalizeInteractiveLoginSuccess()
            return
        }

        if loginPasswordSent && authPhase != .awaitingGuardCode && outputIndicatesAuthenticationFailure(chunk) {
            finalizeInteractiveLoginFailure(message: loginOutputBuffer)
        }
    }

    func handleInteractiveLoginTermination(status: Int32) {
        loginOutputHandle?.readabilityHandler = nil
        appendSteamAuthDebugLog("Handling process termination. status=\(status), loginSucceeded=\(loginSucceeded), authPhase=\(authPhase)")

        if loginSucceeded {
            cancelActiveLoginSession(keepStatus: true)
            return
        }

        if authPhase == .awaitingGuardCode {
            finalizeInteractiveLoginFailure(message: "Steam Guard 验证会话已结束，请重新输入账号和密码。")
            return
        }

        if status == 0, outputIndicatesLoginSuccess(loginOutputBuffer.localizedLowercase) {
            finalizeInteractiveLoginSuccess()
            return
        }

        let message = loginOutputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        finalizeInteractiveLoginFailure(message: message.isEmpty ? "Steam 登录失败，请检查账号密码是否正确。" : message)
    }

    func finalizeInteractiveLoginSuccess() {
        guard !loginSucceeded else { return }
        loginBootstrapTimeoutTask?.cancel()
        appendSteamAuthDebugLog("Login marked successful.")
        loginSucceeded = true
        saveAuthenticationState(username: pendingLoginUsername, password: pendingLoginPassword)
        steamGuardCode = ""
        isAuthenticating = false
        isLoginSheetPresented = false
        authError = nil
        authStatusMessage = "Steam 登录已建立。当前会记住你的凭据，后续下载会优先直接复用；如果远端会话失效，再提示重新登录。"
        loginInputHandle?.write(Data("quit\r".utf8))
        fetchBrowserItems()
        let pendingDownload = pendingDownloadRequest
        pendingDownloadRequest = nil
        if let pendingDownload {
            DispatchQueue.main.async {
                SteamWorkshopService.shared.downloadWorkshopItem(
                    id: pendingDownload.id,
                    pageTitle: pendingDownload.pageTitle
                )
            }
        }
    }

    func finalizeInteractiveLoginFailure(message: String) {
        loginBootstrapTimeoutTask?.cancel()
        appendSteamAuthDebugLog("Login marked failed: \(sanitizeSteamOutput(message))")
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        requiresLogin = true
        isAnonymousBrowsing = true
        authPhase = .credentials
        isAuthenticating = false
        authError = message.trimmingCharacters(in: .whitespacesAndNewlines)
        authStatusMessage = "Steam 登录失败，请重新输入账号密码后再试。"
        cancelActiveLoginSession(keepStatus: true)
    }

    func cancelActiveLoginSession(keepStatus: Bool = false) {
        loginBootstrapTimeoutTask?.cancel()
        loginBootstrapTimeoutTask = nil
        appendSteamAuthDebugLog("Cancelling login session. keepStatus=\(keepStatus)")
        loginOutputHandle?.readabilityHandler = nil
        try? loginOutputHandle?.close()
        try? loginInputHandle?.close()
        if let process = loginProcess, process.isRunning {
            process.terminate()
        }
        loginProcess = nil
        loginInputHandle = nil
        loginOutputHandle = nil
        loginOutputBuffer = ""
        loginPasswordSent = false
        loginSucceeded = false
        pendingLoginUsername = ""
        pendingLoginPassword = ""
        pendingLoginCommand = nil
        if !keepStatus, authPhase != .authenticated {
            authPhase = .credentials
        }
    }

    func sendPendingLoginCommandIfPossible() {
        guard !loginPasswordSent,
              let command = pendingLoginCommand,
              let loginInputHandle else { return }
        appendSteamAuthDebugLog("Writing login command to PTY: \(redactedCommand(command))")
        loginInputHandle.write(Data(command.utf8))
        loginPasswordSent = true
        authStatusMessage = "SteamCMD 控制台已就绪，正在向 Steam 发起账号登录请求…"
        loginBootstrapTimeoutTask?.cancel()
        loginBootstrapTimeoutTask = nil
    }

    func resetSteamAuthDebugLog() {}

    func appendSteamAuthDebugLog(_ message: String) {
        _ = message
    }

    func redactedLoginCommand(username: String, password: String) -> String {
        "login \(username) \(String(repeating: "*", count: max(8, password.count)))\\r"
    }

    func redactedCommand(_ command: String) -> String {
        if command.hasPrefix("login ") {
            let parts = command.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 {
                return "login \(parts[1]) \(String(repeating: "*", count: 8))\\r"
            }
        }
        return sanitizeSteamOutput(command)
    }

    func sanitizeSteamOutput(_ text: String) -> String {
        let sanitizedLogin = text.replacingOccurrences(
            of: #"login\s+(\S+)\s+([^\r\n]+)"#,
            with: "login $1 ********",
            options: .regularExpression
        )

        return sanitizedLogin
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func validateSteamRuntime(at rootURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard Constants.requiredBundledItems.allSatisfy({ name in
            fileManager.fileExists(atPath: rootURL.appendingPathComponent(name).path)
        }) else {
            return false
        }

        for executableName in ["steamcmd.sh", "steamcmd"] {
            let executablePath = rootURL.appendingPathComponent(executableName).path
            guard fileManager.isExecutableFile(atPath: executablePath) else {
                return false
            }
        }
        return true
    }

    func makeSteamPTYSession() throws -> SteamWorkshopPTYSession {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
            )
        }

        return SteamWorkshopPTYSession(
            master: FileHandle(fileDescriptor: masterFD, closeOnDealloc: true),
            slave: FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        )
    }

    func resolvedSteamRuntimeExecutionRootURL() throws -> URL {
        if let activeSteamRootURL {
            return activeSteamRootURL
        }
        throw NSError(domain: "SteamWorkshop", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "内置 SteamCMD 运行目录无效，未执行任何旧缓存回退。请确认应用包中的 SteamCMDRuntime.bundle 完整存在。"
        ])
    }

    func steamProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        return environment
    }

    func refreshSteamRuntimeStatus() {
        if let metadataURL = bundledSteamMetadataURL,
           let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(SteamWorkshopBundledRuntimeMetadata.self, from: data) {
            steamRuntimeVersion = metadata.version
            steamRuntimeUpdateStatus = "当前内置基线版本为 \(metadata.version)。运行时直接使用 App 内置 SteamCMD，后续版本更新随应用更新一起分发。"
        } else {
            steamRuntimeVersion = "未知"
            steamRuntimeUpdateStatus = "未读取到 SteamCMD 基线版本信息。"
        }
    }

    func outputRequestsGuardCode(_ output: String) -> Bool {
        output.contains("steam guard")
        || output.contains("two-factor code")
        || output.contains("two factor code")
        || output.contains("access code")
        || output.contains("email code")
    }

    func outputIndicatesLoginSuccess(_ output: String) -> Bool {
        output.contains("logged in ok")
        || output.contains("successfully logged in")
        || output.contains("waiting for user info...ok")
    }
}
