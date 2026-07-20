import SwiftUI

struct TableStructureView: View {
    let table: TableInfo
    let onRequestQuery: (() -> Void)?

    init(table: TableInfo, onRequestQuery: (() -> Void)? = nil) {
        self.table = table
        self.onRequestQuery = onRequestQuery
    }

    @EnvironmentObject var vm: DatabaseViewModel

    var body: some View {
        VStack(spacing: 0) {
            // -- Header --
            header
                .padding()
                .background(.ultraThinMaterial)

            Divider()

            // -- Columns List --
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(table.columns, id: \.name) { col in
                        ColumnRow(column: col)
                        if col.name != table.columns.last?.name {
                            Divider().padding(.leading)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(table.name)
        .toolbar { tableToolbar }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                    .font(.title3)
                    .fontWeight(.bold)
                HStack(spacing: 12) {
                    Label("\(table.columns.count) columns", systemImage: "rectangle.split.3x1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let count = table.rowCount {
                        Label("\(count) rows", systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Label(table.schema, systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button("Browse Data") {
                let sql = "SELECT * FROM \"\(table.name)\" LIMIT 50;"
                vm.newQueryTab(sql: sql)
                Task { await vm.executeQuery() }
                onRequestQuery?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    @ToolbarContentBuilder
    private var tableToolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                let sql = "SELECT * FROM \"\(table.name)\" LIMIT 50;"
                vm.newQueryTab(sql: sql)
                Task { await vm.executeQuery() }
                onRequestQuery?()
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Browse Data")
        }
    }
}

// MARK: - Column Row

private struct ColumnRow: View {
    let column: ColumnInfo

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: columnIcon)
                .foregroundColor(column.nullable ? .orange : .accentColor)
                .frame(width: 20)

            // Name
            Text(column.name)
                .fontWeight(.semibold)
                .frame(minWidth: 120, alignment: .leading)

            // Type
            Text(column.dataType.isEmpty ? "—" : column.dataType)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(minWidth: 80, alignment: .leading)

            Spacer()

            // Badges
            HStack(spacing: 4) {
                if column.nullable {
                    badge("NULL", color: .orange)
                } else {
                    badge("NOT NULL", color: .indigo)
                }
            }
            .opacity(isHovered ? 1 : 0.6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.accentColor.opacity(0.05) : .clear)
        .cornerRadius(6)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
    }

    private var columnIcon: String {
        let upper = column.dataType.uppercased()
        if upper.contains("INT") || upper.contains("BOOL") { return "number" }
        if upper.contains("CHAR") || upper.contains("TEXT") || upper.contains("VARCHAR") { return "textformat" }
        if upper.contains("FLOAT") || upper.contains("DOUBLE") || upper.contains("DECIMAL") { return "dollarsign" }
        if upper.contains("DATE") || upper.contains("TIME") { return "calendar" }
        if upper.contains("BLOB") || upper.contains("BINARY") { return "doc" }
        return "questionmark.diamond"
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }
}
