import Foundation

/// Wraps the uniffi-generated `DatabaseManager` for safe use with Swift concurrency.
/// All FFI calls are dispatched to a background thread.
@MainActor
final class RustBridge: ObservableObject {
    enum BridgeError: LocalizedError {
        case notConnected
        case ffiError(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to any database"
            case .ffiError(let msg): return msg
            }
        }
    }

    @Published private(set) var connectionStatus: ConnStatus = .disconnected

    private var manager: DatabaseManager?
    private let ffiQueue = DispatchQueue(label: "com.redb.ffi", qos: .userInitiated)

    // MARK: - Connection

    func connect(
        dbType: DatabaseType,
        url: String,
        host: String? = nil,
        port: UInt32? = nil,
        database: String? = nil,
        username: String? = nil,
        password: String? = nil,
        logPath: String? = nil,
        useSshTunnel: Bool = false,
        sshHost: String? = nil,
        sshPort: UInt32? = nil,
        sshUsername: String? = nil,
        sshPassword: String? = nil
    ) async throws {
        let config = DatabaseConfig(
            dbType: dbType,
            url: url,
            host: host,
            port: port,
            database: database,
            username: username,
            password: password,
            maxConnections: 10,
            logPath: logPath,
            useSshTunnel: useSshTunnel,
            sshHost: sshHost,
            sshPort: sshPort,
            sshUsername: sshUsername,
            sshPassword: sshPassword
        )
        let mgr = DatabaseManager(config: config)

        return try await withCheckedThrowingContinuation { continuation in
            ffiQueue.async {
                do {
                    try mgr.connect()
                    Task { @MainActor in
                        self.manager = mgr
                        self.connectionStatus = .connected
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Test Connection

    static func testConnect(
        dbType: DatabaseType,
        url: String,
        host: String? = nil,
        port: UInt32? = nil,
        database: String? = nil,
        username: String? = nil,
        password: String? = nil,
        useSshTunnel: Bool = false,
        sshHost: String? = nil,
        sshPort: UInt32? = nil,
        sshUsername: String? = nil,
        sshPassword: String? = nil
    ) async throws {
        let config = DatabaseConfig(
            dbType: dbType,
            url: url,
            host: host,
            port: port,
            database: database,
            username: username,
            password: password,
            maxConnections: 1,
            logPath: nil,
            useSshTunnel: useSshTunnel,
            sshHost: sshHost,
            sshPort: sshPort,
            sshUsername: sshUsername,
            sshPassword: sshPassword
        )
        let mgr = DatabaseManager(config: config)
        let queue = DispatchQueue(label: "com.redb.ffi.test", qos: .default)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try mgr.connect()
                    try mgr.disconnect()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func disconnect() async throws {
        guard let mgr = manager else { throw BridgeError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            ffiQueue.async {
                do {
                    try mgr.disconnect()
                    Task { @MainActor in
                        self.manager = nil
                        self.connectionStatus = .disconnected
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Query

    func listTables() async throws -> [TableInfo] {
        guard let mgr = manager else { throw BridgeError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            ffiQueue.async {
                do {
                    let tables = try mgr.listTables()
                    continuation.resume(returning: tables)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func executeQuery(_ sql: String) async throws -> QueryResult {
        guard let mgr = manager else { throw BridgeError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            ffiQueue.async {
                do {
                    let result = try mgr.executeQuery(sql: sql)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Database Metadata

    func currentDatabase() async throws -> String {
        guard let mgr = manager else { throw BridgeError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            ffiQueue.async {
                do {
                    let db = try mgr.currentDatabase()
                    continuation.resume(returning: db)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func listDatabases() async throws -> [String] {
        guard let mgr = manager else { throw BridgeError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            ffiQueue.async {
                do {
                    let dbs = try mgr.listDatabases()
                    continuation.resume(returning: dbs)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Quick View

    func quickView(tableName: String, rowLimit: UInt32 = 200) async throws -> QueryResult {
        guard let mgr = manager else { throw BridgeError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            ffiQueue.async {
                do {
                    let result = try mgr.quickView(tableName: tableName, rowLimit: rowLimit)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
