import Foundation

/// Swift-native representation of a query result,
/// making the uniffi `QueryResult` easier to use in SwiftUI.
struct QueryResultModel {
    let columns: [String]
    let rows: [[String]]
    let rowsAffected: UInt64
    let executionTimeMs: UInt64

    init(_ qr: QueryResult) {
        columns = qr.columns.map(\.name)
        rows = qr.rows.map { row in
            row.map { cell in
                switch cell {
                case .null:             return "NULL"
                case .int(let v):       return "\(v)"
                case .float(let v):     return "\(v)"
                case .text(let v):      return v
                case .blob(let v):      return "<blob \(v.count) bytes>"
                }
            }
        }
        rowsAffected = qr.rowsAffected
        executionTimeMs = qr.executionTimeMs
    }
}
