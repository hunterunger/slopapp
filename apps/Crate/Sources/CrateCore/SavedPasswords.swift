import Foundation
import Security

/// Where remembered archive passwords live. Opt-in (Settings ▸ Remember passwords).
public protocol PasswordStore: Sendable {
    func load() -> [String]
    func save(_ passwords: [String]) throws
}

/// One Keychain item (generic password) holding the list, newest first. Nothing is written
/// anywhere else. `CRATE_PASSWORDS_FILE=/tmp/…json` swaps in a plain file for tests and
/// blind tests, so they never touch the login keychain (never use it for real passwords).
public struct KeychainPasswordStore: PasswordStore {
    public static let service = "app.slopapp.crate.passwords"
    public static let account = "saved-archive-passwords"

    public init() {}

    /// The store the app uses, honouring the test override.
    public static func standard() -> any PasswordStore {
        if let file = ProcessInfo.processInfo.environment["CRATE_PASSWORDS_FILE"], !file.isEmpty {
            return FilePasswordStore(url: URL(fileURLWithPath: file))
        }
        return KeychainPasswordStore()
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    public func load() -> [String] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    public func save(_ passwords: [String]) throws {
        let query = baseQuery()
        if passwords.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = try JSONEncoder().encode(passwords)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Crate saved archive passwords"
        add[kSecAttrDescription as String] = "Passwords for archives, remembered by Crate"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// For tests and blind tests only.
public final class FilePasswordStore: PasswordStore, @unchecked Sendable {
    let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
    }
    public func save(_ passwords: [String]) throws {
        try JSONEncoder().encode(passwords).write(to: url, options: .atomic)
    }
}

public final class MemoryPasswordStore: PasswordStore, @unchecked Sendable {
    private let lock = NSLock()
    private var passwords: [String]
    public init(_ passwords: [String] = []) { self.passwords = passwords }
    public func load() -> [String] { lock.withLock { passwords } }
    public func save(_ passwords: [String]) throws { lock.withLock { self.passwords = passwords } }
}

/// The remembered passwords: newest first, no duplicates, at most `limit`.
public struct SavedPasswords: Sendable {
    public let store: any PasswordStore
    public static let limit = 50
    /// How many to try on a new archive (7z key derivation takes a moment each).
    public static let tryLimit = 15

    public init(store: any PasswordStore) { self.store = store }

    public var all: [String] { store.load() }
    public var count: Int { all.count }

    public func remember(_ password: String) {
        guard !password.isEmpty else { return }
        var list = all.filter { $0 != password }
        list.insert(password, at: 0)
        try? store.save(Array(list.prefix(Self.limit)))
    }

    public func forgetAll() {
        try? store.save([])
    }

    /// The first remembered password that opens `source`, if any (and moves it to the top).
    public func find(for source: ArchiveSource) -> String? {
        for password in all.prefix(Self.tryLimit) {
            if Task.isCancelled { return nil }
            if (try? ArchiveReader.checkPassword(password, for: source)) == true {
                remember(password)
                return password
            }
        }
        return nil
    }
}
