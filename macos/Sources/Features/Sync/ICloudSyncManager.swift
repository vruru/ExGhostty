import Foundation
import AppKit
import OSLog

/// 将 Ghostty 配置、SSH 配置、端口转发规则、代码片段和 AI 设置与 iCloud Drive 双向同步。
/// iCloud Drive 上的目录固定为 `~/Library/Mobile Documents/com~apple~CloudDocs/ExGhostty`。
final class ICloudSyncManager: ObservableObject {
    static let shared = ICloudSyncManager()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "ICloudSyncManager"
    )

    private let iCloudDirName = "ExGhostty"
    private let syncInterval: TimeInterval = 30.0
    private let timeTolerance: TimeInterval = 1.0
    private let lastChangeDefaultsKey = "icloud-sync-last-change"

    private var timer: Timer?
    private var isSyncing = false
    private(set) var isImporting = false

    /// 每类配置的本地最后修改时间（真实修改时间，关闭同步期间也会记录）。
    private var lastLocalChange: [SyncCategory: Date] = [:]

    /// iCloud Drive 根目录（`com~apple~CloudDocs`）。
    private var iCloudBaseURL: URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }

    /// 同步目录在 iCloud Drive 中的位置。
    private var iCloudDirectoryURL: URL? {
        iCloudBaseURL?.appendingPathComponent(iCloudDirName)
    }

    /// 本地同步缓存目录（位于 Application Support）。
    private var localSyncDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(iCloudDirName)
    }

    enum SyncCategory: String, CaseIterable {
        case config, ssh, portForward, codeSnippet, aiSettings

        var fileName: String {
            switch self {
            case .config: return "config"
            case .ssh: return "ssh.json"
            case .portForward: return "portforward.json"
            case .codeSnippet: return "snippets.json"
            case .aiSettings: return "ai.json"
            }
        }
    }

    private init() {
        loadLastLocalChange()

        Task { @MainActor [weak self] in
            self?.loadEnabledState()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: nil
        )
    }

    // MARK: - 启用状态

    private(set) var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startPolling()
                Task { @MainActor [weak self] in
                    self?.sync()
                }
            } else {
                stopPolling()
            }
        }
    }

    @MainActor private func loadEnabledState() {
        // 默认开启：仅对从未设置过该开关的用户生效。
        let value = UserDefaults.ghostty.object(forKey: "icloud-sync") as? Bool ?? true
        if value != isEnabled {
            isEnabled = value
        }
    }

    @MainActor @objc private func configDidChange(_ notification: Notification) {
        // 只关心全局配置变更，忽略 surface 配置。
        guard notification.object == nil else { return }
        loadEnabledState()
        if isEnabled {
            sync()
        }
    }

    // MARK: - 轮询

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 公开接口

    /// 立即执行一次完整同步。
    @MainActor func sync() {
        guard isEnabled, !isSyncing else { return }
        guard iCloudDriveAvailable() else {
            logger.info("iCloud Drive is not available, skipping sync")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try ensureDirectories()
            for category in SyncCategory.allCases {
                do {
                    try sync(category: category)
                } catch {
                    // 单个类别失败（例如新电脑上 Keychain 密码尚未到达）不应阻止
                    // 其他类别同步；轮询会在 30 秒后再次尝试。
                    logger.error(
                        "iCloud sync failed for \(category.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        } catch {
            logger.error("iCloud sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 本地数据发生变化时调用，触发同步。
    /// 无论同步是否开启，都会记录该类的本地最后修改时间，
    /// 以便之后开启同步时能按真实修改时间比较新旧。
    @MainActor func localDidChange(category: SyncCategory) {
        localDidChange(categories: [category])
    }

    /// 一次记录多个相关类别并只触发一轮同步，避免设置保存过程中某个类别先同步、
    /// 又把同一批尚未标记的本地修改覆盖掉。
    @MainActor func localDidChange(categories: Set<SyncCategory>) {
        let now = Date()
        for category in categories {
            lastLocalChange[category] = now
        }
        persistLastLocalChange()
        guard isEnabled else { return }
        sync()
    }

    // MARK: - 文件路径

    private func localURL(for category: SyncCategory) -> URL? {
        switch category {
        case .config:
            return (NSApp.delegate as? AppDelegate)?.ghostty.configFileURL
        case .ssh, .portForward, .codeSnippet, .aiSettings:
            return localSyncDirectoryURL.appendingPathComponent(category.fileName)
        }
    }

    private func iCloudURL(for category: SyncCategory) -> URL? {
        return iCloudDirectoryURL?.appendingPathComponent(category.fileName)
    }

    // MARK: - 单类别同步

    private func sync(category: SyncCategory) throws {
        guard let localURL = localURL(for: category),
              let iCloudURL = iCloudURL(for: category) else { return }

        let localExists = FileManager.default.fileExists(atPath: localURL.path)
        let iCloudExists = FileManager.default.fileExists(atPath: iCloudURL.path)

        // 非 config 类别首次运行（本地镜像不存在）时的初始化处理。
        if !localExists && category != .config {
            if iCloudExists {
                // 云端已有数据：下载并导入，避免用本地旧数据覆盖云端。
                try downloadAndImport(category: category, iCloudURL: iCloudURL, localURL: localURL)
                markLocalChangeTime(category, modificationDate(of: iCloudURL) ?? Date())
                logger.info("Initialized \(category.rawValue, privacy: .public) from iCloud")
            } else {
                // 云端也没有：用当前本地数据生成镜像并上传。
                try generateLocalMirrorIfNeeded(category: category)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try copyPreservingAttributes(from: localURL, to: iCloudURL)
                    markLocalChangeTime(category, modificationDate(of: localURL) ?? Date())
                    logger.info("Initialized \(category.rawValue, privacy: .public) to iCloud")
                }
            }
            return
        }

        if !localExists && !iCloudExists {
            return
        }

        if !iCloudExists {
            // 本地有、云端无：上传。
            if category != .config {
                try generateLocalMirrorIfNeeded(category: category)
            }
            try copyPreservingAttributes(from: localURL, to: iCloudURL)
            markLocalChangeTime(category, modificationDate(of: localURL) ?? Date())
            logger.info("Uploaded \(category.rawValue, privacy: .public) to iCloud")
            return
        }

        if !localExists {
            // 云端有、本地无：下载并导入。
            try downloadAndImport(category: category, iCloudURL: iCloudURL, localURL: localURL)
            markLocalChangeTime(category, modificationDate(of: iCloudURL) ?? Date())
            logger.info("Downloaded \(category.rawValue, privacy: .public) from iCloud")
            return
        }

        // 双方都有数据：按真实修改时间比较。
        let iCloudMtime = modificationDate(of: iCloudURL) ?? .distantPast
        let localChangeTime: Date
        if category == .config {
            // 配置文件本身的修改时间即真实修改时间。
            localChangeTime = modificationDate(of: localURL) ?? .distantPast
        } else {
            // 使用保存时记录的真实修改时间（同步关闭期间也会记录）；
            // 没有记录时退化为镜像文件时间。
            localChangeTime = lastLocalChange[category] ?? modificationDate(of: localURL) ?? .distantPast
        }

        if iCloudMtime.timeIntervalSince(localChangeTime) > timeTolerance {
            // 云端更新：下载覆盖本地并导入。
            try downloadAndImport(category: category, iCloudURL: iCloudURL, localURL: localURL)
            markLocalChangeTime(category, iCloudMtime)
            logger.info("Imported \(category.rawValue, privacy: .public) from iCloud")
        } else if localChangeTime.timeIntervalSince(iCloudMtime) > timeTolerance {
            // 本地更新：重新生成镜像并上传。
            try generateLocalMirrorIfNeeded(category: category)
            try copyPreservingAttributes(from: localURL, to: iCloudURL)
            markLocalChangeTime(category, modificationDate(of: localURL) ?? Date())
            logger.info("Uploaded \(category.rawValue, privacy: .public) to iCloud")
        }
    }

    // MARK: - 本地镜像生成

    private func generateLocalMirrorIfNeeded(category: SyncCategory) throws {
        switch category {
        case .config:
            // 配置文件本身即为本地镜像。
            break
        case .ssh:
            if let loadError = SSHStore.shared.connectionLoadError {
                throw loadError
            }
            if SSHStore.shared.connections.contains(where: { !$0.password.isEmpty }),
               !PasswordCipher.hasEncryptionPassword {
                throw PasswordCipher.CipherError.encryptionPasswordRequired
            }
            let payload = SSHSyncPayload(
                connections: SSHStore.shared.connections,
                groups: SSHStore.shared.groups
            )
            try writeJSON(payload, to: localSyncDirectoryURL.appendingPathComponent(category.fileName))
        case .portForward:
            let payload = PortForwardStore.shared.rules
            try writeJSON(payload, to: localSyncDirectoryURL.appendingPathComponent(category.fileName))
        case .codeSnippet:
            let payload = CodeSnippetSyncPayload(
                categories: CodeSnippetStore.shared.categories,
                snippets: CodeSnippetStore.shared.snippets
            )
            try writeJSON(payload, to: localSyncDirectoryURL.appendingPathComponent(category.fileName))
        case .aiSettings:
            let defaults = UserDefaults.ghostty
            let apiKey = defaults.string(forKey: "ai-apikey") ?? ""
            if !apiKey.isEmpty, !PasswordCipher.hasEncryptionPassword {
                throw PasswordCipher.CipherError.encryptionPasswordRequired
            }
            let payload = AISettingsSyncPayload(
                endpoint: defaults.string(forKey: "ai-endpoint") ?? "",
                model: defaults.string(forKey: "ai-model") ?? "",
                encryptedAPIKey: try PasswordCipher.encrypt(apiKey)
            )
            try writeJSON(payload, to: localSyncDirectoryURL.appendingPathComponent(category.fileName))
        }
    }

    // MARK: - 导入本地镜像

    private func importFromLocal(category: SyncCategory, sourceURL: URL) throws {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        switch category {
        case .config:
            (NSApp.delegate as? AppDelegate)?.ghostty.reloadConfig()
        case .ssh:
            let data = try Data(contentsOf: sourceURL)
            let payload = try JSONDecoder().decode(SSHSyncPayload.self, from: data)
            try SSHStore.shared.replaceFromSync(
                connections: payload.connections,
                groups: payload.groups
            )
        case .portForward:
            let data = try Data(contentsOf: sourceURL)
            let rules = try JSONDecoder().decode([PortForwardRule].self, from: data)
            PortForwardStore.shared.rules = rules
            PortForwardStore.shared.save()
        case .codeSnippet:
            let data = try Data(contentsOf: sourceURL)
            let payload = try JSONDecoder().decode(CodeSnippetSyncPayload.self, from: data)
            CodeSnippetStore.shared.categories = payload.categories
            CodeSnippetStore.shared.snippets = payload.snippets

            // 保证默认分类始终存在。
            if !CodeSnippetStore.shared.categories.contains(where: { $0.name == "Default" }) {
                CodeSnippetStore.shared.categories.insert(CodeSnippetCategory(name: "Default"), at: 0)
            }

            CodeSnippetStore.shared.save()
        case .aiSettings:
            let data = try Data(contentsOf: sourceURL)
            let payload = try JSONDecoder().decode(AISettingsSyncPayload.self, from: data)
            let apiKey = try PasswordCipher.decrypt(payload.encryptedAPIKey)
            let defaults = UserDefaults.ghostty
            defaults.set(payload.endpoint, forKey: "ai-endpoint")
            defaults.set(payload.model, forKey: "ai-model")
            defaults.set(apiKey, forKey: "ai-apikey")
            NotificationCenter.default.post(name: .aiSettingsDidChange, object: nil)
        }
    }

    /// 对非 config 文件先直接解析并解密云端源文件，成功后才更新本地镜像。
    /// 密码错误或 Keychain 尚未同步时，本地镜像时间不会前移，下一轮仍会重试。
    private func downloadAndImport(category: SyncCategory, iCloudURL: URL, localURL: URL) throws {
        if category == .config {
            try copyPreservingAttributes(from: iCloudURL, to: localURL)
            try importFromLocal(category: category, sourceURL: localURL)
        } else {
            try importFromLocal(category: category, sourceURL: iCloudURL)
            try copyPreservingAttributes(from: iCloudURL, to: localURL)
        }
    }

    /// 新设备手动输入加密密码时，用已有云端 v2 密文实际验证。
    /// 云端尚无 v2 秘密时没有可验证对象，此时允许建立第一份加密数据。
    func validateEncryptionPassword(_ candidate: String) -> Bool {
        for category in [SyncCategory.ssh, .aiSettings] {
            guard let url = iCloudURL(for: category),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                return false
            }
            guard let encrypted = firstPasswordEncryptedValue(in: object) else { continue }
            if !PasswordCipher.validate(candidate, encryptedValue: encrypted) {
                return false
            }
        }
        return true
    }

    private func firstPasswordEncryptedValue(in value: Any) -> String? {
        if let string = value as? String, PasswordCipher.isPasswordEncrypted(string) {
            return string
        }
        if let array = value as? [Any] {
            return array.compactMap(firstPasswordEncryptedValue(in:)).first
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.compactMap(firstPasswordEncryptedValue(in:)).first
        }
        return nil
    }

    // MARK: - 目录与文件工具

    private func iCloudDriveAvailable() -> Bool {
        guard let url = iCloudBaseURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: localSyncDirectoryURL,
            withIntermediateDirectories: true
        )
        if let iCloudDir = iCloudDirectoryURL {
            try FileManager.default.createDirectory(
                at: iCloudDir,
                withIntermediateDirectories: true
            )
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    private func copyPreservingAttributes(from source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func parseBool(_ value: String?) -> Bool? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if value == "true" || value == "yes" || value == "1" { return true }
        if value == "false" || value == "no" || value == "0" { return false }
        return nil
    }

    // MARK: - 本地修改时间跟踪

    private func loadLastLocalChange() {
        guard let dict = UserDefaults.ghostty.dictionary(forKey: lastChangeDefaultsKey) as? [String: Double] else { return }
        for (key, value) in dict {
            if let category = SyncCategory(rawValue: key) {
                lastLocalChange[category] = Date(timeIntervalSince1970: value)
            }
        }
    }

    private func persistLastLocalChange() {
        var dict: [String: Double] = [:]
        for (category, date) in lastLocalChange {
            dict[category.rawValue] = date.timeIntervalSince1970
        }
        UserDefaults.ghostty.set(dict, forKey: lastChangeDefaultsKey)
    }

    private func markLocalChangeTime(_ category: SyncCategory, _ date: Date) {
        lastLocalChange[category] = date
        persistLastLocalChange()
    }
}

// MARK: - 同步负载

private struct SSHSyncPayload: Codable {
    var connections: [SSHConnection]
    var groups: [SSHGroup]
}

private struct CodeSnippetSyncPayload: Codable {
    var categories: [CodeSnippetCategory]
    var snippets: [CodeSnippet]
}

private struct AISettingsSyncPayload: Codable {
    var endpoint: String
    var model: String
    var encryptedAPIKey: String
}
