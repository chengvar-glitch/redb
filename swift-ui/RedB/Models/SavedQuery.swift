import Foundation

struct SavedQuery: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var sql: String
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, sql: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.sql = sql
        self.createdAt = createdAt
    }
}
