import Foundation
import Combine

// MARK: - Connection Profile

enum DbType: String, CaseIterable, Identifiable {
    case sqlite = "SQLite"
    case postgres = "PostgreSQL"
    case mysql = "MySQL"
    case mariaDb = "MariaDB"
    case sqlServer = "SQL Server"
    case db2 = "DB2"

    var id: String { rawValue }

    var defaultPort: UInt32 {
        switch self {
        case .sqlite: return 0
        case .postgres: return 5432
        case .mysql: return 3306
        case .mariaDb: return 3306
        case .sqlServer: return 1433
        case .db2: return 50000
        }
    }

    var toFFI: DatabaseType {
        switch self {
        case .sqlite: return .sqlite
        case .postgres: return .postgres
        case .mysql: return .mySql
        case .mariaDb: return .mariaDb
        case .sqlServer: return .sqlServer
        case .db2: return .db2
        }
    }

    init(from ffi: DatabaseType) {
        switch ffi {
        case .sqlite: self = .sqlite
        case .postgres: self = .postgres
        case .mySql: self = .mysql
        case .mariaDb: self = .mariaDb
        case .sqlServer: self = .sqlServer
        case .db2: self = .db2
        }
    }
}

struct ConnectionProfile: Identifiable, Hashable {
    let id: String
    var name: String
    var dbType: DbType
    var url: String
    var host: String
    var port: UInt32
    var database: String
    var username: String
    var password: String
    var lastConnected: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        dbType: DbType = .sqlite,
        url: String = "",
        host: String = "",
        port: UInt32 = 0,
        database: String = "",
        username: String = "",
        password: String = ""
    ) {
        self.id = id
        self.name = name
        self.dbType = dbType
        self.url = url
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.password = password
    }

    var toConfig: DatabaseConfig {
        DatabaseConfig(
            dbType: dbType.toFFI,
            url: url,
            host: host.isEmpty ? nil : host,
            port: port,
            database: database.isEmpty ? nil : database,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password,
            maxConnections: 10
        )
    }

    init(from saved: SavedConnection) {
        self.id = saved.id
        self.name = saved.name
        self.dbType = DbType(from: saved.config.dbType)
        self.url = saved.config.url
        self.host = saved.config.host ?? ""
        self.port = saved.config.port ?? 0
        self.database = saved.config.database ?? ""
        self.username = saved.config.username ?? ""
        self.password = saved.config.password ?? ""
    }
}

// MARK: - Store Path

private let storeFileName = "redb_connections.json"

private func appSupportDir() -> String {
    let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    let dir = paths[0].appendingPathComponent("RedB")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
}

private func defaultStorePath() -> String {
    let dir = appSupportDir()
    return (dir as NSString).appendingPathComponent(storeFileName)
}

// MARK: - Load State

enum LoadState<T> {
    case idle
    case loading
    case success(T)
    case failure(String)

    var isLoaded: Bool {
        if case .success = self { true } else { false }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
}

// MARK: - ViewModel

@MainActor
final class DatabaseViewModel: ObservableObject {
    let bridge = RustBridge()

    private let store: ConnectionStore?
    private let queryStore: QueryStore?

    // -- Connections --
    @Published var selectedDbType: DbType = .sqlite
    @Published var connections: [ConnectionProfile] = []
    @Published var selectedConnection: ConnectionProfile?

    // -- Tables --
    @Published var tablesLoadState: LoadState<[TableInfo]> = .idle

    // -- Query --
    @Published var queryTabs: [QueryTab] = []
    @Published var activeQueryTabId: UUID?

    var activeQueryTab: QueryTab? {
        guard let id = activeQueryTabId else { return nil }
        return queryTabs.first { $0.id == id }
    }

    // -- Table Usage (for auto-complete) --
    @Published var tableUsage: [String: Int] = [:]

    var availableTableNames: [String] {
        guard case .success(let tables) = tablesLoadState else { return [] }
        return tables.map(\.name)
    }

    func columnSuggestions(matching prefix: String) -> [String] {
        guard case .success(let tables) = tablesLoadState else { return [] }
        let sql = activeQueryTab?.sqlInput ?? ""
        let tableNames = extractTableNames(from: sql)
        guard let firstName = tableNames.first,
              let table = tables.first(where: { $0.name == firstName })
        else { return [] }
        return table.columns
            .map { $0.name }
            .filter { prefix.isEmpty || $0.lowercased().hasPrefix(prefix.lowercased()) }
            .sorted()
    }

    func aliasForTable(_ name: String) -> String {
        // camelCase: UserLoginLog → ull
        let upper = name.filter { $0.isUppercase }
        if !upper.isEmpty && name.count > 3 && upper.count > 1 {
            return upper.lowercased()
        }
        // snake_case: sys_user → su
        if name.contains("_") {
            return name.split(separator: "_").compactMap { $0.first }.map { String($0).lowercased() }.joined()
        }
        // Default: first 2 chars
        return String(name.prefix(2).lowercased())
    }

    func tableSuggestions(matching prefix: String) -> [String] {
        let lower = prefix.lowercased()
        let all = availableTableNames
        let filtered = all.filter { $0.lowercased().hasPrefix(lower) }
        return filtered.sorted { a, b in
            let af = tableUsage[a] ?? 0
            let bf = tableUsage[b] ?? 0
            if af != bf { return af > bf }
            return a.localizedCompare(b) == .orderedAscending
        }
    }

    func recordTableUsage(_ table: String) {
        tableUsage[table, default: 0] += 1
        try? queryStore?.recordTableUsage(tableName: table)
    }

    // -- Saved Queries --
    @Published var savedQueries: [SavedQuery] = []

    // -- 已废弃：quick view 直接走 query tab

    // -- Row Limit --
    @Published var rowLimit: Int = 200

    // -- Connection state --
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?

    private var cancellables = Set<AnyCancellable>()

    private let lastConnKey = "lastConnectionId"
    private let lastQueryKey = "lastQuerySql"

    init() {
        let path = defaultStorePath()
        print("[RedB] Store path: \(path)")
        let s = try? ConnectionStore.open(path: path)
        if s == nil {
            print("[RedB] Warning: Could not open connection store at \(path)")
        } else {
            print("[RedB] Store opened successfully")
        }
        self.store = s
        self.queryStore = try? QueryStore.open(baseDir: appSupportDir())

        loadSavedConnections()
        loadSavedQueries()
        loadTableUsage()

        bridge.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        autoConnectLast()
    }

    private func autoConnectLast() {
        guard let id = UserDefaults.standard.string(forKey: lastConnKey),
              let profile = connections.first(where: { $0.id == id }) else { return }
        selectedConnection = profile
        Task { await connect(profile) }
    }

    // MARK: - Store Persistence

    private func loadSavedConnections() {
        guard let s = store else {
            print("[RedB] No store available")
            return
        }
        guard let saved = try? s.listAll() else {
            print("[RedB] Failed to list saved connections")
            return
        }
        print("[RedB] Loaded \(saved.count) saved connections")
        connections = saved.map(ConnectionProfile.init(from:))
    }

    private func saveToStore(_ profile: ConnectionProfile) {
        try? store?.save(id: profile.id, name: profile.name, config: profile.toConfig)
    }

    private func deleteFromStore(_ profile: ConnectionProfile) {
        try? store?.delete(id: profile.id)
    }

    // MARK: - Connection

    func connect(_ profile: ConnectionProfile) async {
        guard !isConnecting else { return }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            try await bridge.connect(
                dbType: profile.dbType.toFFI,
                url: profile.url,
                host: profile.host.isEmpty ? nil : profile.host,
                port: profile.port,
                database: profile.database.isEmpty ? nil : profile.database,
                username: profile.username.isEmpty ? nil : profile.username,
                password: profile.password.isEmpty ? nil : profile.password
            )
            selectedConnection = profile
            updateLastConnected(profile)
            UserDefaults.standard.set(profile.id, forKey: lastConnKey)
            // Load cached tables if available; otherwise fetch from remote
            if !loadCachedTables(for: profile) {
                await refreshTables()
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func disconnect() async {
        try? await bridge.disconnect()
        selectedConnection = nil
        tablesLoadState = .idle
        queryTabs.removeAll()
        activeQueryTabId = nil
    }

    func addConnection(_ profile: ConnectionProfile) {
        connections.append(profile)
        saveToStore(profile)
    }

    func removeConnection(_ profile: ConnectionProfile) {
        connections.removeAll { $0.id == profile.id }
        if selectedConnection?.id == profile.id {
            selectedConnection = nil
        }
        deleteFromStore(profile)
    }

    func updateConnection(_ profile: ConnectionProfile) {
        guard let i = connections.firstIndex(where: { $0.id == profile.id }) else { return }
        connections[i] = profile
        saveToStore(profile)
    }

    func connectNew(profile: ConnectionProfile) async {
        selectedConnection = profile
        addConnection(profile)
        await connect(profile)
        // First connection: fetch from remote and cache
        await refreshTables()
    }

    private func updateLastConnected(_ profile: ConnectionProfile) {
        guard let i = connections.firstIndex(where: { $0.id == profile.id }) else { return }
        connections[i].lastConnected = .now
    }

    // MARK: - Tables

    @discardableResult
    func loadCachedTables(for profile: ConnectionProfile) -> Bool {
        guard let s = store,
              let saved = try? s.load(id: profile.id),
              let cached = saved.cachedTables
        else { return false }
        tablesLoadState = .success(cached)
        return true
    }

    func refreshTables() async {
        tablesLoadState = .loading
        do {
            let tables = try await bridge.listTables()
            tablesLoadState = .success(tables)
            // Persist to disk
            if let conn = selectedConnection {
                _ = try? store?.saveCachedTables(id: conn.id, tables: tables)
            }
        } catch {
            tablesLoadState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Query

    @discardableResult
    func newQueryTab(sql: String = "", loading: Bool = false) -> QueryTab {
        let n = queryTabs.count + 1
        let tab = QueryTab(title: "Query \(n)", sqlInput: sql)
        if loading { tab.queryLoadState = .loading }
        queryTabs.append(tab)
        activeQueryTabId = tab.id
        return tab
    }

    func closeQueryTab(_ tab: QueryTab) {
        UserDefaults.standard.set(tab.sqlInput, forKey: lastQueryKey)
        guard let i = queryTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let wasActive = activeQueryTabId == tab.id
        queryTabs.remove(at: i)
        if wasActive {
            activeQueryTabId = queryTabs.last?.id ?? queryTabs.first?.id
        }
    }

    func executeQuery() async {
        guard let tab = activeQueryTab else { return }
        let trimmed = tab.sqlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        UserDefaults.standard.set(trimmed, forKey: lastQueryKey)

        // Store base SQL (without any trailing LIMIT) for lazy loading
        var clean = trimmed
        if let limitRange = clean.range(of: "LIMIT", options: [.caseInsensitive, .backwards]) {
            let before = clean[..<limitRange.lowerBound].trimmingCharacters(in: .whitespaces)
            if before.hasSuffix("LIMIT") || before.hasSuffix("limit") {
                clean = String(before)
            }
        }
        tab.baseSql = clean

        let statements = splitSQL(trimmed)
        guard !statements.isEmpty else { return }

        tab.queryLoadState = .loading
        var results: [QueryResult] = []

        for stmt in statements {
            do {
                let r = try await bridge.executeQuery(stmt)
                results.append(r)
            } catch {
                results.append(QueryResult(
                    columns: [],
                    rows: [],
                    rowsAffected: 0,
                    executionTimeMs: 0
                ))
                tab.queryLoadState = .failure("\(stmt.prefix(40))...\n\(error.localizedDescription)")
                return
            }
        }

        tab.queryLoadState = .success(results)

        // Record table usage for auto-complete
        for stmt in statements {
            for table in extractTableNames(from: stmt) {
                recordTableUsage(table)
            }
        }
    }

    private func extractTableNames(from sql: String) -> Set<String> {
        let upper = sql.uppercased()
        let keywords: Set<String> = ["FROM", "JOIN", "INTO", "UPDATE", "TABLE", "INTO"]
        var names = Set<String>()
        let parts = upper.components(separatedBy: .whitespacesAndNewlines)
        for (i, word) in parts.enumerated() {
            if keywords.contains(word) {
                let nextIdx = i + 1
                if nextIdx < parts.count {
                    var name = parts[nextIdx].trimmingCharacters(in: CharacterSet(charactersIn: "\"'`;"))
                    if !name.isEmpty && !keywords.contains(name) {
                        // Skip if looks like a subquery or function
                        if !name.hasPrefix("(") && !name.hasPrefix("SELECT") {
                            names.insert(name)
                        }
                    }
                }
            }
        }
        return names
    }

    private func splitSQL(_ sql: String) -> [String] {
        sql.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Table Usage

    private func loadTableUsage() {
        guard let qs = queryStore,
              let entries = try? qs.getTableUsage()
        else { return }
        tableUsage = Dictionary(uniqueKeysWithValues: entries.map { ($0.tableName, Int($0.count)) })
    }

    // MARK: - Saved Queries

    private func loadSavedQueries() {
        guard let qs = queryStore, let list = try? qs.listSavedQueries() else { return }
        savedQueries = list
    }

    func saveQuery(name: String, sql: String) {
        guard let qs = queryStore else { return }
        let id = UUID().uuidString
        let created = Int64(Date.now.timeIntervalSince1970)
        if (try? qs.saveQuery(id: id, name: name, sql: sql, createdAt: created)) != nil {
            savedQueries.append(SavedQuery(id: id, name: name, sql: sql, createdAt: created))
        }
    }

    func deleteSavedQuery(_ query: SavedQuery) {
        guard let qs = queryStore, (try? qs.deleteSavedQuery(id: query.id)) != nil else { return }
        savedQueries.removeAll { $0.id == query.id }
    }

    func renameSavedQuery(_ query: SavedQuery, name: String) {
        guard let qs = queryStore else { return }
        let created = query.createdAt
        guard (try? qs.saveQuery(id: query.id, name: name, sql: query.sql, createdAt: created)) != nil,
              let i = savedQueries.firstIndex(where: { $0.id == query.id })
        else { return }
        savedQueries[i].name = name
    }

    // MARK: - Quick View

    func quickView(table: TableInfo) async {
        let q = selectedConnection?.dbType == .mysql || selectedConnection?.dbType == .mariaDb ? "" : "\""
        let sql = "SELECT * FROM \(q)\(table.name)\(q) LIMIT \(rowLimit);"
        let tab = newQueryTab(sql: sql, loading: true)
        await executeQuery()
        tab.title = table.name
    }

    func isConnected(_ profile: ConnectionProfile) -> Bool {
        bridge.connectionStatus == .connected && selectedConnection?.id == profile.id
    }
}
