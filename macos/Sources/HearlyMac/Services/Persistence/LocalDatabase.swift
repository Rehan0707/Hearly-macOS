import Foundation
import CryptoKit
import Security
import SQLite3

enum HearlyFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum SecureStore {
    static func read(_ account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "live.hearely.mac", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw HearlyFailure.message("Keychain access failed (\(status)).") }
        return value as? Data
    }
    static func write(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "live.hearely.mac", kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw HearlyFailure.message("Could not save to Keychain.") }
        } else if status != errSecSuccess { throw HearlyFailure.message("Could not update Keychain.") }
    }
    static func remove(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "live.hearely.mac", kSecAttrAccount as String: account] as CFDictionary)
    }
}

/// Voiceprints and transcripts are encrypted before they enter the SQLite database.
final class LocalDatabase {
    private var db: OpaquePointer?
    private let key: SymmetricKey
    convenience init() throws {
        let key: SymmetricKey
        if let data = try SecureStore.read("database-key") {
            guard data.count == 32 else { throw HearlyFailure.message("The Hearly database key is invalid. Your stored data has not been changed.") }
            key = SymmetricKey(data: data)
        }
        else {
            key = SymmetricKey(size: .bits256)
            try SecureStore.write(key.withUnsafeBytes { Data($0) }, account: "database-key")
        }
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Hearly", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try self.init(file: folder.appendingPathComponent("hearly.sqlite"), key: key)
    }

    /// Allows isolated temporary databases in tests without touching the user's Keychain.
    init(file: URL, key: SymmetricKey) throws {
        guard file.isFileURL, key.bitCount == 256 else { throw HearlyFailure.message("Invalid local database configuration.") }
        self.key = key
        var connection: OpaquePointer?
        guard sqlite3_open_v2(file.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(connection)
            throw HearlyFailure.message("Cannot open the Hearly database.")
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            guard sqlite3_busy_timeout(connection, 3000) == SQLITE_OK,
                  sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS private_records (id TEXT PRIMARY KEY, payload BLOB NOT NULL)", nil, nil, nil) == SQLITE_OK else {
                throw HearlyFailure.message("Cannot prepare the Hearly database.")
            }
            db = connection
        } catch {
            sqlite3_close(connection)
            throw error
        }
    }
    deinit { sqlite3_close(db) }
    func save<T: Encodable>(_ value: T, id: String) throws {
        guard let payload = try AES.GCM.seal(JSONEncoder().encode(value), using: key).combined else {
            throw HearlyFailure.message("Cannot encrypt the Hearly record.")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO private_records VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK else { throw HearlyFailure.message("Database write failed.") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, id, -1, transient) == SQLITE_OK,
              payload.withUnsafeBytes({ sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }) == SQLITE_OK else {
            throw HearlyFailure.message("Database write failed.")
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HearlyFailure.message("Database write failed.") }
    }
    func load<T: Decodable>(_ type: T.Type, id: String) throws -> T? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM private_records WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { throw HearlyFailure.message("Database read failed.") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw HearlyFailure.message("Database read failed.") }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw HearlyFailure.message("Database read failed.") }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        return try JSONDecoder().decode(type, from: AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key))
    }
    func remove(id: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM private_records WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { throw HearlyFailure.message("Database delete failed.") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw HearlyFailure.message("Database delete failed.") }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HearlyFailure.message("Database delete failed.") }
    }
}
