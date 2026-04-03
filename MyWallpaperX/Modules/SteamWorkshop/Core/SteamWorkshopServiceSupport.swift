import Foundation
import Security

enum SteamWorkshopDownloadControlError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消下载。"
        }
    }
}

struct SteamWorkshopPendingDownloadRequest {
    let id: String
    let pageTitle: String?
}

struct SteamWorkshopPTYSession {
    let master: FileHandle
    let slave: FileHandle
}

enum SteamWorkshopCredentialStore {
    private static let service = "com.songziqiang.MyWallpaperX.steam"
    private static let account = "steamPassword"

    static func save(password: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            SecItemAdd(create as CFDictionary, nil)
        }
    }

    static func loadPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8),
              !password.isEmpty else {
            return nil
        }
        return password
    }

    static func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

actor SteamWorkshopAuthorNameStore {
    private var namesByKey: [String: String] = [:]
    private var didLoadFromDisk = false

    func name(for keys: [String]) async -> String? {
        await loadFromDiskIfNeeded()
        for key in keys {
            if let value = namesByKey[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func store(name: String, for keys: [String]) async {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != "未知作者", !keys.isEmpty else { return }
        await loadFromDiskIfNeeded()
        var didChange = false
        for key in keys where !key.isEmpty {
            if namesByKey[key] != normalized {
                namesByKey[key] = normalized
                didChange = true
            }
        }
        if didChange {
            persistToDisk()
        }
    }

    func clear() async {
        namesByKey.removeAll()
        didLoadFromDisk = true
        try? FileManager.default.removeItem(at: Self.cacheFileURL)
    }

    private func loadFromDiskIfNeeded() async {
        guard !didLoadFromDisk else { return }
        defer { didLoadFromDisk = true }
        guard let data = try? Data(contentsOf: Self.cacheFileURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any],
              let names = payload["namesByKey"] as? [String: String] else {
            return
        }
        namesByKey = names
    }

    private func persistToDisk() {
        let payload: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "namesByKey": namesByKey
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        let directory = Self.cacheFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: Self.cacheFileURL, options: [.atomic])
    }

    private static var cacheFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
            .appendingPathComponent("AuthorNames.json")
    }
}
