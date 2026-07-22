import SwiftUI

private func extractTableName(from sql: String) -> String? {
    let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
    let upper = trimmed.uppercased()
    guard let fromRange = upper.range(of: " FROM ") else { return nil }
    var afterFrom = String(trimmed[fromRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    if afterFrom.hasPrefix("\"") {
        afterFrom = String(afterFrom.dropFirst())
        if let idx = afterFrom.firstIndex(of: "\"") {
            return String(afterFrom[..<idx])
        }
    } else {
        let parts = afterFrom.split(whereSeparator: { $0.isWhitespace || $0 == "\n" || $0 == "," || $0 == ";" })
        if let first = parts.first {
            return String(first)
        }
    }
    return nil
}

struct QueryResultView: View {
    let result: QueryResult
    @EnvironmentObject var vm: DatabaseViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbarBar
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            if !result.columns.isEmpty {
                ResultDataTable(columns: result.columns, rows: result.rows, baseSql: vm.activeQueryTab?.baseSql ?? "", rowLimit: vm.rowLimit)
                    .frame(maxHeight: .infinity)
            } else if result.rowsAffected > 0 {
                affectedOnlyState.frame(maxHeight: .infinity)
            }
            if !result.columns.isEmpty {
                Divider()
                statusBar
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var toolbarBar: some View {
        HStack(spacing: 6) {
            if result.rowsAffected > 0 {
                Label("\(result.rowsAffected) affected", systemImage: "pencil")
            }
            Spacer()
            if !result.columns.isEmpty {
                Divider().frame(height: 14)
                Button { copyAsCSV() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy as CSV")
                Button { copyAsInsert() } label: { Image(systemName: "list.clipboard") }
                    .buttonStyle(.borderless).help("Copy as INSERT")
                Button { copyAsMarkdown() } label: { Image(systemName: "table") }
                    .buttonStyle(.borderless).help("Copy as Markdown")
            }
        }
        .font(.caption).foregroundColor(.secondary)
    }

    private func limitButton(_ value: Int, label: String? = nil) -> some View {
        let isActive = vm.rowLimit == value
        return Button(label ?? "\(value)") {
            vm.rowLimit = value
            guard let tab = vm.activeQueryTab else { return }
            let base = tab.sqlInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard base.uppercased().hasPrefix("SELECT") else { return }
            tab.sqlInput = value > 0 ? "\(tab.baseSql) LIMIT \(value)" : tab.baseSql
            Task { await vm.executeQuery() }
        }
        .buttonStyle(.borderless).controlSize(.small).font(.caption)
        .foregroundColor(isActive ? .accentColor : .secondary)
        .fontWeight(isActive ? .semibold : .regular)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(isActive ? Color.accentColor.opacity(0.12) : .clear)
    }

    private func copyAsCSV() {
        var csv = result.columns.map(\.name).joined(separator: ",") + "\n"
        for row in result.rows {
            csv += row.map { cell in
                switch cell {
                case .null: return ""
                case .int(let v): return "\(v)"
                case .float(let v): return "\(v)"
                case .text(let v): return "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\""
                case .blob: return "<blob>"
                }
            }.joined(separator: ",") + "\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
    }

    private func copyAsInsert() {
        let tableName = "results"
        let cols = result.columns.map(\.name).joined(separator: ", ")
        var sql = ""
        for row in result.rows {
            let vals = row.map { cell -> String in
                switch cell {
                case .null: return "NULL"
                case .int(let v): return "\(v)"
                case .float(let v): return "\(v)"
                case .text(let v): return "'\(v.replacingOccurrences(of: "'", with: "''"))'"
                case .blob: return "X'...'"
                }
            }.joined(separator: ", ")
            sql += "INSERT INTO \(tableName) (\(cols)) VALUES (\(vals));\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sql, forType: .string)
    }

    private func copyAsMarkdown() {
        var md = "| " + result.columns.map(\.name).joined(separator: " | ") + " |\n"
        md += "| " + result.columns.map { _ in "---" }.joined(separator: " | ") + " |\n"
        for row in result.rows {
            md += "| " + row.map { cell in
                switch cell {
                case .null: return ""
                case .int(let v): return "\(v)"
                case .float(let v): return "\(v)"
                case .text(let v): return v
                case .blob: return "<blob>"
                }
            }.joined(separator: " | ") + " |\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Label("\(result.columns.count) cols", systemImage: "rectangle.split.3x1")
            Text("·").foregroundStyle(.tertiary)
            Label("\(result.rows.count) rows", systemImage: "tablecells")
            Spacer()
            Menu("Limit: \(vm.rowLimit == 0 ? "All" : "\(vm.rowLimit)")") {
                limitButton(50); limitButton(100); limitButton(200); limitButton(500); limitButton(1000)
                limitButton(0, label: "All")
            }
            .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
            Divider().frame(height: 12)
            Label("\(result.executionTimeMs) ms", systemImage: "clock")
        }
        .font(.caption).foregroundColor(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 2)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var affectedOnlyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
            Text("\(result.rowsAffected) row(s) affected").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ResultDataTable (NSTableView backend)

private struct ResultDataTable: View {
    let columns: [ColumnInfo]
    let rows: [[CellValue]]
    let baseSql: String
    let rowLimit: Int

    @EnvironmentObject var vm: DatabaseViewModel
    @State private var lazyRows: [[CellValue]] = []
    @State private var lazyOffset: Int = 0
    @State private var isLoadingMore = false
    @State private var hasMore = true
    private let batchSize = 200
    @State private var sortColumn: Int? = nil
    @State private var sortDescending: Bool = true
    @State private var selectedRows: Set<Int> = []
    @State private var cachedSortedRows: [[CellValue]]? = nil

    private var pkColumnIndices: [Int] {
        columns.enumerated().filter { $0.element.isPrimaryKey }.map { $0.offset }
    }

    private var tableName: String? {
        extractTableName(from: baseSql)
    }

    private var dataRows: [[CellValue]] {
        sortColumn != nil ? sortedRows : lazyRows
    }

    private var sortedRows: [[CellValue]] {
        guard let col = sortColumn else { return rows }
        if let cached = cachedSortedRows { return cached }
        let r = rows.sorted { a, b in
            guard col < a.count, col < b.count else { return false }
            return sortDescending ? compareCell(a[col], b[col]) == .orderedDescending : compareCell(a[col], b[col]) == .orderedAscending
        }
        Task { @MainActor in cachedSortedRows = r }
        return r
    }

    private func compareCell(_ a: CellValue, _ b: CellValue) -> ComparisonResult {
        switch (a, b) {
        case (.int(let x), .int(let y)): return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (.float(let x), .float(let y)): return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (.text(let x), .text(let y)): return x.localizedCompare(y)
        case (.null, .null): return .orderedSame
        case (.null, _): return .orderedAscending
        case (_, .null): return .orderedDescending
        default: return .orderedSame
        }
    }

    var body: some View {
        DataTable(
            columns: columns,
            rows: dataRows,
            sortColumn: sortColumn,
            sortDescending: sortDescending,
            selectedRows: selectedRows,
            pkColumnIndices: pkColumnIndices,
            tableName: tableName,
            onSort: { col, desc in sortColumn = col; sortDescending = desc; cachedSortedRows = nil },
            onSelectedRowsChanged: { selectedRows = $0 },
            onCommitEdit: { row, col, newValue in
                vm.updateCell(tableName: tableName, row: row, col: col, newValue: newValue,
                              pkColumns: pkColumnIndices, dataRows: dataRows, columns: columns)
            },
            onDataTableAction: { action in
                handleDataTableAction(action)
            }
        )
        .onAppear {
            lazyRows = rows; lazyOffset = rows.count
            let maxLimit = rowLimit > 0 ? rowLimit : Int.max
            hasMore = rows.count >= batchSize && lazyOffset < maxLimit
        }
        .onChange(of: columns.count) { _ in cachedSortedRows = nil }
        .onChange(of: rows.count) { _ in cachedSortedRows = nil }
    }

    private func handleDataTableAction(_ action: DataTableAction) {
        let data = dataRows
        switch action {
        case .copyCell(let row, let col):
            guard row < data.count, col < data[row].count else { return }
            let value = displayCellValue(data[row][col])
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)

        case .copyRow(let row):
            guard row < data.count else { return }
            let line = columns.map(\.name).joined(separator: "\t") + "\n"
                + data[row].map { displayCellValue($0) }.joined(separator: "\t")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(line, forType: .string)

        case .copySelected(let rows):
            let lines: [String] = rows.sorted().compactMap { r -> String? in
                guard r < data.count else { return nil }
                return data[r].map { displayCellValue($0) }.joined(separator: "\t")
            }
            let result = columns.map(\.name).joined(separator: "\t") + "\n" + lines.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)

        case .copySelectedAsCSV(let rows):
            let lines: [String] = rows.sorted().compactMap { r -> String? in
                guard r < data.count else { return nil }
                return data[r].map { cell in
                    switch cell {
                    case .text(let v): return "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\""
                    case .null: return ""
                    default: return displayCellValue(cell)
                    }
                }.joined(separator: ",")
            }
            let result = columns.map(\.name).joined(separator: ",") + "\n" + lines.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)

        case .deleteRows(let rows, let table):
            Task {
                await vm.deleteRows(rows: rows.sorted(), table: table,
                                    pkColumns: pkColumnIndices, dataRows: data, columns: columns)
            }
        }
    }
}
