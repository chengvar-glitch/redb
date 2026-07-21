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
            // -- Status & Toolbar --
            toolbarBar
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // -- Data Table --
            if !result.columns.isEmpty {
                ResultDataTable(columns: result.columns, rows: result.rows, baseSql: vm.activeQueryTab?.baseSql ?? "", rowLimit: vm.rowLimit)
                    .frame(maxHeight: .infinity)
            } else if result.rowsAffected > 0 {
                affectedOnlyState
                    .frame(maxHeight: .infinity)
            }

            if !result.columns.isEmpty {
                Divider()
                statusBar
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Toolbar Bar

    private var toolbarBar: some View {
        HStack(spacing: 6) {
            if result.rowsAffected > 0 {
                Label("\(result.rowsAffected) affected", systemImage: "pencil")
            }

            Spacer()

            if !result.columns.isEmpty {
                Divider()
                    .frame(height: 14)

                Button {
                    copyAsCSV()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy as CSV")

                Button {
                    copyAsInsert()
                } label: {
                    Image(systemName: "list.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Copy as INSERT")

                Button {
                    copyAsMarkdown()
                } label: {
                    Image(systemName: "table")
                }
                .buttonStyle(.borderless)
                .help("Copy as Markdown")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: Copy Actions

    private func limitButton(_ value: Int, label: String? = nil) -> some View {
        let isActive = vm.rowLimit == value
        return Button(label ?? "\(value)") {
            vm.rowLimit = value
            guard let tab = vm.activeQueryTab else { return }
            let base = tab.sqlInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard base.uppercased().hasPrefix("SELECT") else { return }
            let limitSql = value > 0 ? "\(tab.baseSql) LIMIT \(value)" : tab.baseSql
            tab.sqlInput = limitSql
            Task { await vm.executeQuery() }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.caption)
        .foregroundColor(isActive ? .accentColor : .secondary)
        .fontWeight(isActive ? .semibold : .regular)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
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
                limitButton(50)
                limitButton(100)
                limitButton(200)
                limitButton(500)
                limitButton(1000)
                limitButton(0, label: "All")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()

            Divider()
                .frame(height: 12)

            Label("\(result.executionTimeMs) ms", systemImage: "clock")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var affectedOnlyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
            Text("\(result.rowsAffected) row(s) affected")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ResultDataTable

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
    @State private var scrollPosition: CGPoint = .zero
    @State private var sortColumn: Int? = nil
    @State private var sortDescending: Bool = true

    // -- Performance: cached column widths --
    @State private var memoizedWidths: [CGFloat]? = nil
    @State private var lastMeasureId: Int = 0

    // -- Performance: cached sorted rows --
    @State private var cachedSortedRows: [[CellValue]]? = nil

    // -- Selection state --
    @State private var selectedRow: Int? = nil
    @State private var hoveredRow: Int? = nil

    // -- Editing state --
    @State private var editingCell: (row: Int, col: Int)? = nil
    @State private var editText: String = ""
    @State private var dirtyCells: [Int: [Int: CellValue]] = [:]

    // -- Column resize --
    @State private var customColumnWidths: [Int: CGFloat] = [:]
    private let minColWidth: CGFloat = 80
    private let maxColWidth: CGFloat = 400

    private var hasDirtyCells: Bool {
        !dirtyCells.isEmpty
    }

    private var sortedRows: [[CellValue]] {
        guard let col = sortColumn else { return rows }
        if let cached = cachedSortedRows { return cached }
        let result = rows.sorted { a, b in
            guard col < a.count, col < b.count else { return false }
            return sortDescending
                ? compareCell(a[col], b[col]) == .orderedDescending
                : compareCell(a[col], b[col]) == .orderedAscending
        }
        Task { @MainActor in cachedSortedRows = result }
        return result
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

    private var tableName: String? {
        extractTableName(from: vm.activeQueryTab?.sqlInput ?? "")
    }

    private var quote: String {
        guard let db = vm.selectedConnection?.dbType else { return "\"" }
        switch db {
        case .mysql, .mariaDb: return ""
        default: return "\""
        }
    }

    /// Computed column widths with memoization + custom resize overrides
    private func columnWidths(availableWidth: CGFloat) -> [CGFloat] {
        let measureId = columns.count * 100000 + rows.count
        if let memoized = memoizedWidths, lastMeasureId == measureId, customColumnWidths.isEmpty {
            return memoized
        }

        let padding: CGFloat = 20
        var widths: [CGFloat] = columns.enumerated().map { i, col in
            // Use custom width if set
            if let custom = customColumnWidths[i] { return max(minColWidth, min(custom, maxColWidth)) }

            let headerW = (col.name as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)]).width + 24
            var contentW = headerW
            for row in rows {
                if i < row.count {
                    let text = displayCell(row[i])
                    let w = (text as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]).width + padding
                    if w > contentW { contentW = w }
                }
            }
            return min(max(contentW + padding, minColWidth), maxColWidth)
        }

        let totalContent = widths.reduce(0, +)
        let n = CGFloat(widths.count)
        if n > 0 && totalContent < availableWidth {
            let extra = (availableWidth - totalContent) / n
            for i in widths.indices {
                widths[i] = min(widths[i] + extra, maxColWidth)
            }
        }

        memoizedWidths = widths
        lastMeasureId = measureId
        return widths
    }

    var body: some View {
        GeometryReader { geo in
            let widths = columnWidths(availableWidth: geo.size.width)
        let displayRows = sortColumn != nil ? sortedRows : lazyRows
            return VStack(spacing: 0) {
                // Edit bar
                editBar

                // Data grid
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Header with resize handles
                        headerRow(widths: widths, availableWidth: geo.size.width)
                        separatorRow
                        // Data rows with row numbers + keyboard support
                        dataRows(displayRows: displayRows, widths: widths)
                        if isLoadingMore {
                            loadingMoreIndicator
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
                // Keyboard navigation handled via hidden button shortcuts
                // Table is the primary View for keyboard handling
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .onAppear {
            lazyRows = rows
            lazyOffset = rows.count
            let maxLimit = rowLimit > 0 ? rowLimit : Int.max
            hasMore = rows.count >= batchSize && lazyOffset < maxLimit
        }
        .onChange(of: columns.count) { _ in resetWidthsCache() }
        .onChange(of: rows.count) { _ in resetWidthsCache() }
        .onChange(of: sortColumn) { _ in cachedSortedRows = nil }
        .onChange(of: sortDescending) { _ in cachedSortedRows = nil }
    }

    // MARK: Edit Bar

    @ViewBuilder
    private var editBar: some View {
        if hasDirtyCells {
            HStack {
                Text("\(dirtyCellsCount) cell(s) modified")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { cancelEdits() }
                    .controlSize(.small)
                Button("Save") { saveEdits() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.04))
            Divider()
        }
    }

    // MARK: Data Rows

    private func dataRows(displayRows: [[CellValue]], widths: [CGFloat]) -> some View {
        ForEach(Array(displayRows.enumerated()), id: \.offset) { i, row in
            HStack(spacing: 0) {
                // Row number
                Text("\(i + 1)")
                    .font(.caption2)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 36, alignment: .trailing)
                    .padding(.trailing, 4)

                Divider()

                // Data cells
                dataRow(row, index: i, widths: widths)
            }
            .background(rowBackground(isSelected: selectedRow == i, isHovered: hoveredRow == i, index: i))
            .onTapGesture {
                selectedRow = i; editingCell = nil
            }
            .onHover { hovering in
                hoveredRow = hovering ? i : nil
            }
            .contextMenu { rowContextMenu(row: row) }

            if i < displayRows.count - 1 {
                Divider().padding(.leading, 40)
            }
            if i >= displayRows.count - 5 && hasMore && !isLoadingMore && sortColumn == nil {
                Color.clear.onAppear { loadMore() }
            }
        }
    }

    // MARK: Header

    private func headerRow(widths: [CGFloat], availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Row number header
            Text("#")
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 4)

            Divider()

            ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                Button {
                    if sortColumn == i {
                        sortDescending.toggle()
                    } else {
                        sortColumn = i
                        sortDescending = true
                    }
                    cachedSortedRows = nil
                } label: {
                    HStack(spacing: 4) {
                        headerIcon(col)
                        Text(col.name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if sortColumn == i {
                            Image(systemName: sortDescending ? "chevron.down" : "chevron.up")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: widths[i], alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(sortColumn == i ? Color.accentColor.opacity(0.1) : Color.accentColor.opacity(0.06))

                // Resize handle
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 3)
                    .frame(height: 16)
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() }
                        else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newW = widths[i] + value.translation.width
                                customColumnWidths[i] = max(minColWidth, min(newW, maxColWidth))
                                memoizedWidths = nil
                            }
                    )

                if i < columns.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color.accentColor.opacity(0.03))
    }

    private func iconForType(_ type: String) -> String {
        let u = type.uppercased()
        if u.contains("INT") || u.contains("BOOL") { return "number" }
        if u.contains("CHAR") || u.contains("TEXT") || u.contains("VARCHAR") { return "textformat" }
        if u.contains("FLOAT") || u.contains("DOUBLE") || u.contains("DECIMAL") { return "dollarsign" }
        if u.contains("DATE") || u.contains("TIME") { return "calendar" }
        return "questionmark.diamond"
    }

    @ViewBuilder
    private func headerIcon(_ col: ColumnInfo) -> some View {
        if col.isPrimaryKey {
            Image(systemName: "key.fill")
                .foregroundColor(.orange)
                .font(.caption2)
        } else {
            Image(systemName: iconForType(col.dataType))
                .font(.caption2)
        }
    }

    private var separatorRow: some View {
        Divider()
    }

    // MARK: Data Row

    private func dataRow(_ row: [CellValue], index: Int, widths: [CGFloat]) -> some View {
        let hasDirty = dirtyCells[index] != nil && !dirtyCells[index]!.isEmpty

        return HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                if editingCell?.row == index && editingCell?.col == i {
                    TextField("", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: widths[i], height: 22)
                        .padding(.horizontal, 10)
                        .background(Color.accentColor.opacity(0.15))
                        .onSubmit {
                            commitEdit(row: index, col: i)
                        }
                } else {
                    Text(displayCell(cell))
                        .foregroundColor(foregroundForCell(cell))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: widths[i], height: 22, alignment: cellAlignment(cell))
                        .padding(.horizontal, 10)
                        .background(
                            hasDirty && dirtyCells[index]?[i] != nil
                                ? Color.orange.opacity(0.08)
                                : Color.clear
                        )
                        .onTapGesture(count: 2) {
                            beginEdit(row: index, col: i, value: cell)
                        }
                }

                if i < row.count - 1 {
                    Divider()
                }
            }
        }
    }

    // MARK: - Context Menu

    private func rowContextMenu(row: [CellValue]) -> some View {
        Group {
            if let tbl = tableName {
                Button {
                    vm.activeQueryTab?.sqlInput = buildDeleteSQL(table: tbl, row: row)
                } label: {
                    Label("Delete Row", systemImage: "trash")
                }

                Button {
                    vm.activeQueryTab?.sqlInput = buildInsertSQL(table: tbl, row: row)
                } label: {
                    Label("Duplicate Row", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button {
                copyCellToClipboard(row: row)
            } label: {
                Label("Copy Row", systemImage: "doc.on.doc")
            }
        }
    }

    private func copyCellToClipboard(row: [CellValue]) {
        let text = row.map { displayCell($0) }.joined(separator: "\t")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func buildDeleteSQL(table: String, row: [CellValue]) -> String {
        let q = quote
        let conditions = zip(columns, row).map { col, val -> String in
            let escaped = sqlEscape(val)
            return "\(q)\(col.name)\(q) = \(escaped)"
        }.joined(separator: " AND ")
        return "DELETE FROM \(q)\(table)\(q) WHERE \(conditions);"
    }

    private func buildInsertSQL(table: String, row: [CellValue]) -> String {
        let q = quote
        let colNames = columns.map { "\(q)\($0.name)\(q)" }.joined(separator: ", ")
        let vals = row.map { sqlEscape($0) }.joined(separator: ", ")
        return "INSERT INTO \(q)\(table)\(q) (\(colNames)) VALUES (\(vals));"
    }

    private func sqlEscape(_ val: CellValue) -> String {
        switch val {
        case .null: return "NULL"
        case .int(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .text(let v):
            let escaped = v.replacingOccurrences(of: "'", with: "''")
            return "'\(escaped)'"
        case .blob: return "X''"
        }
    }

    // MARK: - Lazy Loading

    private func loadMore() {
        guard !baseSql.isEmpty else { return }
        let maxLimit = rowLimit > 0 ? rowLimit : Int.max
        guard lazyOffset < maxLimit else { hasMore = false; return }
        isLoadingMore = true
        let fetchCount = min(batchSize, maxLimit - lazyOffset)
        Task {
            let sql = "\(baseSql) LIMIT \(fetchCount) OFFSET \(lazyOffset)"
            if let r = try? await vm.bridge.executeQuery(sql) {
                Task { @MainActor in
                    lazyRows.append(contentsOf: r.rows)
                    lazyOffset += r.rows.count
                    hasMore = r.rows.count >= batchSize && lazyOffset < maxLimit
                    isLoadingMore = false
                }
            } else {
                Task { @MainActor in isLoadingMore = false }
            }
        }
    }

    // MARK: - Cell Editing

    private var dirtyCellsCount: Int {
        dirtyCells.values.reduce(0) { $0 + $1.count }
    }

    private func beginEdit(row: Int, col: Int, value: CellValue) {
        guard sortColumn == nil else { return }
        editingCell = (row, col)
        selectedRow = nil
        editText = displayCell(value)
        if editText == "NULL" { editText = "" }
    }

    private func commitEdit(row: Int, col: Int) {
        let newVal = cellValueFromString(editText)
        if dirtyCells[row] == nil { dirtyCells[row] = [:] }
        dirtyCells[row]?[col] = newVal
        editingCell = nil
        editText = ""
    }

    private func cellValueFromString(_ s: String) -> CellValue {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.uppercased() == "NULL" { return .null }
        if let v = Int(trimmed) { return .int(Int64(v)) }
        if let v = Double(trimmed) { return .float(v) }
        return .text(trimmed)
    }

    private func cancelEdits() {
        dirtyCells = [:]
        editingCell = nil
        editText = ""
    }

    private func saveEdits() {
        guard let tbl = tableName else { return }
        let pkCols = columns.enumerated().filter { $0.element.isPrimaryKey }.map { $0.offset }
        let q = quote

        for (rowIdx, cols) in dirtyCells {
            guard rowIdx < rows.count else { continue }
            let originalRow = rows[rowIdx]

            // Build SET clause
            let sets = cols.map { (colIdx, newVal) -> String in
                "\(q)\(columns[colIdx].name)\(q) = \(sqlEscape(newVal))"
            }.joined(separator: ", ")

            // Build WHERE clause using PK columns (or all columns if no PK)
            let conditions: String
            if !pkCols.isEmpty {
                conditions = pkCols.map { i in
                    let val = cols[i] ?? originalRow[i]
                    return "\(q)\(columns[i].name)\(q) = \(sqlEscape(val))"
                }.joined(separator: " AND ")
            } else {
                conditions = columns.enumerated().map { (i, col) in
                    let val = cols[i] ?? originalRow[i]
                    return "\(q)\(col.name)\(q) = \(sqlEscape(val))"
                }.joined(separator: " AND ")
            }

            let sql = "UPDATE \(q)\(tbl)\(q) SET \(sets) WHERE \(conditions);"
            vm.activeQueryTab?.sqlInput = sql
            Task { await vm.executeQuery() }
        }

        dirtyCells = [:]
    }

    private func displayCell(_ cv: CellValue) -> String {
        switch cv {
        case .null:         return "NULL"
        case .int(let v):   return "\(v)"
        case .float(let v): return "\(v)"
        case .text(let v):  return v
        case .blob(let v):  return "<blob \(v.count)B>"
        }
    }

    private func foregroundForCell(_ cv: CellValue) -> Color {
        switch cv {
        case .null:         return Color(nsColor: .tertiaryLabelColor)
        case .int, .float:  return .accentColor
        case .text:         return .primary
        case .blob:         return .secondary
        }
    }

    private func cellAlignment(_ cv: CellValue) -> Alignment {
        switch cv {
        case .int, .float:  return .trailing
        case .null:         return .center
        default:            return .leading
        }
    }

    private func rowBackground(isSelected: Bool, isHovered: Bool, index: Int) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        } else if isHovered {
            return Color.accentColor.opacity(0.06)
        } else if index % 2 == 0 {
            return Color.clear
        } else {
            return Color.gray.opacity(0.04)
        }
    }

    // MARK: - Helpers

    private func resetWidthsCache() {
        memoizedWidths = nil
        customColumnWidths = [:]
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard let row = selectedRow else { return }
        switch direction {
        case .up:
            if row > 0 { selectedRow = row - 1 }
        case .down:
            if row < lazyRows.count - 1 { selectedRow = row + 1 }
        case .left:
            if let editing = editingCell, editing.col > 0 {
                editingCell = (editing.row, editing.col - 1)
            }
        case .right:
            if let editing = editingCell, editing.col < columns.count - 1 {
                editingCell = (editing.row, editing.col + 1)
            }
        @unknown default:
            break
        }
    }

    private var loadingMoreIndicator: some View {
        HStack {
            ProgressView().scaleEffect(0.6)
            Text("Loading more...").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
