import Foundation
import CommonCrypto
import CryptoKit
import Security

/// SSH 密码和 AI API Key 的 AES 对称加密存储工具。
///
/// `enc:v2:` 使用用户设置的加密密码，经 PBKDF2-SHA256 派生 AES-256-GCM 密钥。
/// 加密密码只保存在 Keychain（可通过 iCloud Keychain 同步），不会写入 iCloud Drive。
/// `enc:v1:` 是旧版随机 AES 密钥格式；读取后会在下一次保存时自动迁移到 v2。
enum PasswordCipher {
    private static let legacyPrefix = "enc:v1:"
    private static let passwordPrefix = "enc:v2:"
    private static let keychainService = "com.mitchellh.ghostty.password-cipher"
    private static let legacyKeyAccount = "ssh-password-aes-key"
    private static let encryptionPasswordAccount = "sync-encryption-password"
    private static let pbkdf2Rounds: UInt32 = 210_000
    private static let saltByteCount = 16

    enum CipherError: LocalizedError {
        case invalidEncryptedValue
        case keyUnavailable
        case encryptionPasswordRequired
        case passwordMismatch
        case keyDerivationFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidEncryptedValue:
                return "The encrypted value is invalid.".localized
            case .keyUnavailable:
                return "The iCloud Keychain encryption key is not available yet.".localized
            case .encryptionPasswordRequired:
                return "Set an iCloud encryption password before syncing passwords or API keys.".localized
            case .passwordMismatch:
                return "The encryption password cannot decrypt the synchronized data.".localized
            case .keyDerivationFailed(let status):
                return "Password key derivation failed (\(status))."
            }
        }
    }

    /// 是否已有可用的用户加密密码。
    static var hasEncryptionPassword: Bool {
        (try? loadEncryptionPassword()) != nil
    }

    /// 保存或更新用户加密密码。该凭据只进入可同步的 Keychain 条目。
    static func setEncryptionPassword(_ password: String) throws {
        guard !password.isEmpty else { throw CipherError.encryptionPasswordRequired }
        try upsertSynchronizableItem(
            account: encryptionPasswordAccount,
            data: Data(password.utf8)
        )
    }

    /// 已配置时仅用于确认当前密码；为避免先覆盖 Keychain、后重加密中途失败导致
    /// 数据永久不可读，此版本不在保存设置时直接执行密码轮换。
    static func matchesEncryptionPassword(_ candidate: String) -> Bool {
        guard let current = try? loadEncryptionPassword() else { return false }
        return current == candidate
    }

    /// 加密明文；空字符串或已经加密的输入原样返回。
    ///
    /// 未设置用户密码时保留 v1 兼容路径，供本机旧数据继续工作；iCloud 同步层会
    /// 阻止包含秘密的 v1 数据上传，直到用户设置加密密码。
    static func encrypt(_ plaintext: String) throws -> String {
        guard !plaintext.isEmpty else { return plaintext }
        guard !plaintext.hasPrefix(legacyPrefix), !plaintext.hasPrefix(passwordPrefix) else {
            return plaintext
        }

        if let password = try loadEncryptionPassword() {
            return try encryptWithPassword(plaintext, password: password)
        }

        let key = try loadOrCreateLegacyKey()
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealed.combined else { throw CipherError.invalidEncryptedValue }
        return legacyPrefix + combined.base64EncodedString()
    }

    /// 解密存储值；没有加密前缀的按历史明文直接返回。
    static func decrypt(_ stored: String) throws -> String {
        if stored.hasPrefix(passwordPrefix) {
            guard let password = try loadEncryptionPassword() else {
                throw CipherError.encryptionPasswordRequired
            }
            return try decryptWithPassword(stored, password: password)
        }

        guard stored.hasPrefix(legacyPrefix) else { return stored }
        let key = try loadExistingLegacyKey()
        let body = String(stored.dropFirst(legacyPrefix.count))
        guard let data = Data(base64Encoded: body) else { throw CipherError.invalidEncryptedValue }
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: key)
        guard let value = String(data: plain, encoding: .utf8) else {
            throw CipherError.invalidEncryptedValue
        }
        return value
    }

    /// 用候选密码验证一段 v2 密文；用于新设备手动输入密码后的校验。
    static func validate(_ candidatePassword: String, encryptedValue: String) -> Bool {
        guard encryptedValue.hasPrefix(passwordPrefix) else { return true }
        return (try? decryptWithPassword(encryptedValue, password: candidatePassword)) != nil
    }

    static func isPasswordEncrypted(_ value: String) -> Bool {
        value.hasPrefix(passwordPrefix)
    }

    // MARK: - Password-based encryption

    private static func encryptWithPassword(_ plaintext: String, password: String) throws -> String {
        var salt = Data(count: saltByteCount)
        let randomStatus = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltByteCount, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(randomStatus))
        }

        let key = try deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealed.combined else { throw CipherError.invalidEncryptedValue }
        return passwordPrefix + salt.base64EncodedString() + ":" + combined.base64EncodedString()
    }

    private static func decryptWithPassword(_ stored: String, password: String) throws -> String {
        let body = String(stored.dropFirst(passwordPrefix.count))
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let salt = Data(base64Encoded: String(parts[0])),
              let combined = Data(base64Encoded: String(parts[1])) else {
            throw CipherError.invalidEncryptedValue
        }

        let key = try deriveKey(password: password, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            let plain = try AES.GCM.open(box, using: key)
            guard let value = String(data: plain, encoding: .utf8) else {
                throw CipherError.invalidEncryptedValue
            }
            return value
        } catch {
            throw CipherError.passwordMismatch
        }
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let derivedByteCount = 32
        var derived = Data(count: derivedByteCount)
        let passwordBytes = Array(password.utf8)
        let status: Int32 = derived.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress,
                        passwordBuffer.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Rounds,
                        derivedBuffer.bindMemory(to: UInt8.self).baseAddress,
                        derivedByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CipherError.keyDerivationFailed(status) }
        return SymmetricKey(data: derived)
    }

    // MARK: - Keychain

    private static func loadEncryptionPassword() throws -> String? {
        if let data = try readKeychainItem(account: encryptionPasswordAccount, synchronizable: true) {
            return String(data: data, encoding: .utf8)
        }
        // 兼容可能由测试版写入的本机条目，并在读取时迁移为同步条目。
        if let localData = try readKeychainItem(account: encryptionPasswordAccount, synchronizable: false) {
            try upsertSynchronizableItem(account: encryptionPasswordAccount, data: localData)
            return String(data: localData, encoding: .utf8)
        }
        return nil
    }

    private static func loadExistingLegacyKey() throws -> SymmetricKey {
        // 升级设备上的本机旧密钥必须优先：已有 v1 数据就是由它加密的。随后把
        // 同一字节迁移到同步条目，避免先命中一份不相干的云端竞态密钥。
        if let legacyData = try readKeychainItem(account: legacyKeyAccount, synchronizable: false) {
            try upsertSynchronizableItem(account: legacyKeyAccount, data: legacyData)
            return SymmetricKey(data: legacyData)
        }
        if let data = try readKeychainItem(account: legacyKeyAccount, synchronizable: true) {
            return SymmetricKey(data: data)
        }
        throw CipherError.keyUnavailable
    }

    private static func loadOrCreateLegacyKey() throws -> SymmetricKey {
        do {
            return try loadExistingLegacyKey()
        } catch CipherError.keyUnavailable {
            // 只有产生新的本地 v1 密文时才创建。解密云端数据时不会抢先创建一个
            // 不同的密钥，因此可等待原密钥从 iCloud Keychain 到达。
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let stored = try addSynchronizableItemIfMissing(account: legacyKeyAccount, data: data)
        return SymmetricKey(data: stored)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readKeychainItem(account: String, synchronizable: Bool) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = synchronizable
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return item as? Data
    }

    private static func addSynchronizableItemIfMissing(account: String, data: Data) throws -> Data {
        var attributes = baseQuery(account: account)
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return data }
        if status == errSecDuplicateItem,
           let existing = try readKeychainItem(account: account, synchronizable: true) {
            return existing
        }
        guard status != errSecDuplicateItem else { throw CipherError.keyUnavailable }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    private static func upsertSynchronizableItem(account: String, data: Data) throws {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = true
        let updates = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }
        _ = try addSynchronizableItemIfMissing(account: account, data: data)
    }
}
