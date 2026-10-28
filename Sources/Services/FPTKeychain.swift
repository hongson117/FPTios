//
//  FPTKeychain.swift
//  FTVOS (Apple TV / tvOS)
//
//  Quản lý lưu trữ và xóa sạch (Sign Out) phiên đăng nhập trong Keychain phần cứng của Apple TV.
//

import Foundation
import Security

public enum FPTKeychain {
    private static let serviceName = "vn.ftvos.appletv.keychain"
    private static let accountName = "ftvos_direct_auth_v2"
    private static let defaultsBackupKey = "ftvos_appletv_auth_backup_v2"

    public static func save(_ config: FPTBootstrapConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)

        UserDefaults.standard.set(data, forKey: defaultsBackupKey)
    }

    public static func load() -> FPTBootstrapConfig? {
        // Xóa bỏ tàn dư của bản cũ (v1) nếu có
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "vn.fptplay.appletv.keychain"
        ]
        SecItemDelete(legacyQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "fpt_appletv_bootstrap_backup_v1")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let config = try? JSONDecoder().decode(FPTBootstrapConfig.self, from: data),
           config.isProvisioned {
            return config
        }

        if let backupData = UserDefaults.standard.data(forKey: defaultsBackupKey),
           let config = try? JSONDecoder().decode(FPTBootstrapConfig.self, from: backupData),
           config.isProvisioned {
            return config
        }

        return nil
    }

    public static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: defaultsBackupKey)
    }
}
