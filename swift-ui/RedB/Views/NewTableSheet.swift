import SwiftUI

// MARK: - MySQL Column Types (grouped)

private struct MySQLTypeGroup {
    let name: String
    let types: [(name: String, hasLen: Bool, hasAutoInc: Bool)]
}

private let mysqlTypeGroups: [MySQLTypeGroup] = [
    MySQLTypeGroup(name: "Numeric", types: [
        ("TINYINT",    true,  true),
        ("SMALLINT",   true,  true),
        ("MEDIUMINT",  true,  true),
        ("INT",        true,  true),
        ("BIGINT",     true,  true),
        ("FLOAT",      true,  false),
        ("DOUBLE",     true,  false),
        ("DECIMAL",    true,  false),
    ]),
    MySQLTypeGroup(name: "String", types: [
        ("CHAR",       true,  false),
        ("VARCHAR",    true,  false),
        ("TEXT",       false, false),
        ("MEDIUMTEXT", false, false),
        ("LONGTEXT",   false, false),
        ("ENUM",       true,  false),
    ]),
    MySQLTypeGroup(name: "Date / Time", types: [
        ("DATE",       false, false),
        ("DATETIME",   false, false),
        ("TIMESTAMP",  false, false),
        ("TIME",       false, false),
        ("YEAR",       false, false),
    ]),
    MySQLTypeGroup(name: "Binary / Other", types: [
        ("BLOB",       false, false),
        ("LONGBLOB",   false, false),
        ("BOOLEAN",    false, false),
        ("JSON",       false, false),
    ]),
]

private var allMySQLTypes: [(name: String, hasLen: Bool, hasAutoInc: Bool)] {
    mysqlTypeGroups.flatMap(\.types)
}

// MARK: - Column Definition Model

private struct ColumnDef: Identifiable {
    let id = UUID()
    var name: String
    var typeIndex: Int
    var length: String
    var nullable: Bool
    var isPrimaryKey: Bool
    var autoIncrement: Bool
    var defaultValue: String

    init() {
        self.name = ""
        self.typeIndex = 0
        self.length = ""
        self.nullable = true
        self.isPrimaryKey = false
        self.autoIncrement = false
        self.defaultValue = ""
    }
}

// MARK: - New Table Sheet

struct NewTableSheet: View {
    let profile: ConnectionProfile

    @EnvironmentObject var vm: DatabaseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tableName = ""
    @State private var columns: [ColumnDef] = [ColumnDef()]
    @State private var createError: String?
    @State private var isCreating = false

    private var isValid: Bool {
        !tableName.trimmingCharacters(in: .whitespaces).isEmpty
        && columns.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            columnListView
            Divider()
            footerView
        }
        .frame(width: 680, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("New Table")
                    .font(.headline)
                Text("MySQL — \(profile.database.isEmpty ? "current database" : profile.database)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            TextField("Table name", text: $tableName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
    }

    // MARK: - Column List

    private var columnListView: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundColor(.clear)
                    .frame(width: 16)

                Group {
                    Text("Column Name").frame(width: 140, alignment: .leading)
                    Text("Data Type").frame(width: 130, alignment: .leading)
                    Text("Length").frame(width: 60, alignment: .leading)
                    Text("Default").frame(width: 90, alignment: .leading)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                Text("N").frame(width: 22).help("Nullable")
                Text("PK").frame(width: 24)
                Text("AI").frame(width: 24).help("Auto Increment")
                Spacer().frame(width: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                        columnRowView(i: i, col: Binding(
                            get: { columns[i] },
                            set: { columns[i] = $0 }
                        ))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    addColumnButton
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
                .animation(.easeInOut(duration: 0.15), value: columns.count)
                .padding(.vertical, 8)
            }
        }
    }

    private var addColumnButton: some View {
        HStack {
            Button {
                withAnimation { columns.append(ColumnDef()) }
            } label: {
                Label("Add Column", systemImage: "plus.circle")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Column Row

    private func columnRowView(i: Int, col: Binding<ColumnDef>) -> some View {
        let typeInfo = allMySQLTypes[col.wrappedValue.typeIndex]
        return HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 16)

            // Name
            TextField("column_name", text: col.name)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 140)
                .foregroundColor(col.wrappedValue.name.isEmpty ? .secondary : .primary)

            // Type picker
            typePicker(col: col)

            // Length
            if typeInfo.hasLen {
                TextField("", text: col.length)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 60)
            } else {
                Spacer().frame(width: 60)
            }

            // Default
            TextField("NULL", text: col.defaultValue)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 90)

            Spacer()

            // Nullable
            Toggle("", isOn: col.nullable)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .frame(width: 22)
                .help(col.wrappedValue.nullable ? "Nullable" : "NOT NULL")

            // Primary Key
            Toggle("", isOn: col.isPrimaryKey)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .frame(width: 24)
                .onChange(of: col.wrappedValue.isPrimaryKey) { pk in
                    if pk { col.wrappedValue.nullable = false }
                }

            // Auto Increment
            if typeInfo.hasAutoInc {
                Toggle("", isOn: col.autoIncrement)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .frame(width: 24)
            } else {
                Spacer().frame(width: 24)
            }

            // Delete
            Button {
                columns.remove(at: i)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(columns.count > 1 ? 1 : 0.3)
            .disabled(columns.count <= 1)
            .frame(width: 20)
            .help("Remove column")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(i % 2 == 0 ? Color.accentColor.opacity(0.03) : Color.clear as Color)
    }

    @ViewBuilder
    private func typePicker(col: Binding<ColumnDef>) -> some View {
        let selected = allMySQLTypes[col.wrappedValue.typeIndex].name
        Menu(selected) {
            ForEach(mysqlTypeGroups, id: \.name) { group in
                Section(group.name) {
                    ForEach(Array(group.types.enumerated()), id: \.offset) { j, typeInfo in
                        let typeName = typeInfo.name
                        Button(typeName) {
                            let flatIndex = allMySQLTypes.firstIndex(where: { $0.name == typeName }) ?? 0
                            col.wrappedValue.typeIndex = flatIndex
                        }
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(width: 130, alignment: .leading)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 12) {
            if let err = createError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape)

            if isCreating {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Button {
                createTable()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                    Text("Create Table")
                }
                .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isCreating)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Create Table Logic

    private func createTable() {
        let name = tableName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let cols = columns.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !cols.isEmpty else { return }

        isCreating = true
        createError = nil

        var parts: [String] = []
        var pkCols: [String] = []

        for c in cols {
            let colName = "`\(c.name.trimmingCharacters(in: .whitespaces))`"
            let typeInfo = allMySQLTypes[c.typeIndex]
            let len = typeInfo.hasLen && !c.length.isEmpty ? "(\(c.length))" : ""
            var def = "\(colName) \(typeInfo.name)\(len)"

            if c.autoIncrement { def += " AUTO_INCREMENT" }
            if c.isPrimaryKey {
                def += " NOT NULL"
                pkCols.append(colName)
            } else if !c.nullable {
                def += " NOT NULL"
            }
            if !c.defaultValue.isEmpty {
                def += " DEFAULT \(c.defaultValue)"
            }

            parts.append(def)
        }

        if !pkCols.isEmpty {
            parts.append("PRIMARY KEY (\(pkCols.joined(separator: ", ")))")
        }

        let sql = "CREATE TABLE `\(name)` (\n  \(parts.joined(separator: ",\n  "))\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"

        Task {
            do {
                let _: QueryResult = try await vm.bridge.executeQuery(sql)
                dismiss()
                let tab = vm.newQueryTab(sql: sql)
                tab?.title = name
                await vm.executeQuery()
            } catch {
                createError = error.localizedDescription
                isCreating = false
            }
        }
    }
}
