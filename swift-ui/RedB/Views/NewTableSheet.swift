import SwiftUI

// MARK: - MySQL Column Types

private let mysqlTypes: [(name: String, hasLen: Bool, hasAutoInc: Bool)] = [
    ("INT",        true,  true),
    ("BIGINT",     true,  true),
    ("SMALLINT",   true,  true),
    ("TINYINT",    true,  true),
    ("FLOAT",      true,  false),
    ("DOUBLE",     true,  false),
    ("DECIMAL",    true,  false),
    ("VARCHAR",    true,  false),
    ("CHAR",       true,  false),
    ("TEXT",       false, false),
    ("MEDIUMTEXT", false, false),
    ("LONGTEXT",   false, false),
    ("DATE",       false, false),
    ("DATETIME",   false, false),
    ("TIMESTAMP",  false, false),
    ("TIME",       false, false),
    ("YEAR",       false, false),
    ("BLOB",       false, false),
    ("LONGBLOB",   false, false),
    ("BOOLEAN",    false, false),
    ("JSON",       false, false),
    ("ENUM",       true,  false),
]

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

    private var isValid: Bool {
        !tableName.trimmingCharacters(in: .whitespaces).isEmpty
        && columns.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider()

            // Column list
            columnList

            Divider()
            // Footer
            footer
        }
        .frame(width: 600, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Table")
                    .font(.headline)
                TextField("Table name", text: $tableName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            Spacer()
        }
        .padding(16)
    }

    // MARK: Column List

    private var columnList: some View {
        ScrollView {
            VStack(spacing: 6) {
                // Column header labels
                HStack(spacing: 6) {
                    Text("Name").frame(width: 120, alignment: .leading)
                    Text("Type").frame(width: 100, alignment: .leading)
                    Text("Length").frame(width: 50, alignment: .leading)
                    Text("N").frame(width: 20).help("Nullable")
                    Text("PK").frame(width: 24)
                    Text("AI").frame(width: 24).help("Auto Increment")
                    Text("Default").frame(width: 80, alignment: .leading)
                    Spacer().frame(width: 20)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)

                ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                    columnRow(i: i, col: Binding(
                        get: { columns[i] },
                        set: { columns[i] = $0 }
                    ))
                }

                Button {
                    columns.append(ColumnDef())
                } label: {
                    Label("Add Column", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
        }
    }

    private func columnRow(i: Int, col: Binding<ColumnDef>) -> some View {
        HStack(spacing: 6) {
            TextField("", text: col.name)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 120)

            Picker("", selection: col.typeIndex) {
                ForEach(Array(mysqlTypes.enumerated()), id: \.offset) { j, t in
                    Text(t.name).tag(j)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)

            if mysqlTypes[col.wrappedValue.typeIndex].hasLen {
                TextField("", text: col.length)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 50)
            } else {
                Spacer().frame(width: 50)
            }

            Toggle("", isOn: col.nullable)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .frame(width: 20)

            Toggle("", isOn: col.isPrimaryKey)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .frame(width: 24)
                .onChange(of: col.wrappedValue.isPrimaryKey) { pk in
                    if pk { col.wrappedValue.nullable = false }
                }

            if mysqlTypes[col.wrappedValue.typeIndex].hasAutoInc {
                Toggle("", isOn: col.autoIncrement)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .frame(width: 24)
            } else {
                Spacer().frame(width: 24)
            }

            TextField("", text: col.defaultValue)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 80)

            Button {
                columns.remove(at: i)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(columns.count <= 1)
            .frame(width: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let err = createError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.borderless)
            Button("Create Table") {
                createTable()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Create Table

    private func createTable() {
        let name = tableName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let cols = columns.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !cols.isEmpty else { return }

        var parts: [String] = []
        var pkCols: [String] = []

        for c in cols {
            let colName = "`\(c.name.trimmingCharacters(in: .whitespaces))`"
            let typeDef = mysqlTypes[c.typeIndex]
            let typeName = typeDef.name
            let len = typeDef.hasLen && !c.length.isEmpty ? "(\(c.length))" : ""
            var def = "\(colName) \(typeName)\(len)"

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
                _ = try await vm.bridge.executeQuery(sql)
                await MainActor.run {
                    dismiss()
                    let tab = vm.newQueryTab(sql: sql)
                    tab?.title = name
                    Task { await vm.executeQuery() }
                }
            } catch {
                createError = error.localizedDescription
            }
        }
    }
}
