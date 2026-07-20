import SwiftUI

struct TableBrowserView: View {
    @EnvironmentObject var vm: DatabaseViewModel
    @State private var searchText = ""
    @State private var savedQueriesExpanded = false

    var body: some View {
        Group {
            switch vm.tablesLoadState {
        case .idle:
            idleState
        case .loading:
            loadingState
            case .success(let tables):
                loadedState(tables)
            case .failure(let msg):
                failureState(msg)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.tablesLoadState.isLoaded)
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.full")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Double-click a connection to connect")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Loading tables…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loaded

    private func loadedState(_ tables: [TableInfo]) -> some View {
        let filtered = searchText.isEmpty ? tables : tables.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }

        return List {
            if !vm.savedQueries.isEmpty {
                savedQueriesSection
            }

            if !searchText.isEmpty && filtered.isEmpty {
                Text("No tables matching \"\(searchText)\"")
                    .foregroundColor(.secondary)
            }

            ForEach(filtered, id: \.name) { table in
                TableRow(table: table)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Filter tables")
    }

    // MARK: - Saved Queries Section

    private var savedQueriesSection: some View {
        Section {
            if savedQueriesExpanded {
                ForEach(vm.savedQueries) { query in
                    SavedQueryRow(query: query)
                }
            }
        } header: {
            Button {
                withAnimation { savedQueriesExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: savedQueriesExpanded ? "folder.fill" : "folder")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("查询")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(vm.savedQueries.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Failure

    private func failureState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.orange)
            Text(msg)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await vm.refreshTables() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Saved Query Row

private struct SavedQueryRow: View {
    let query: SavedQuery
    @EnvironmentObject var vm: DatabaseViewModel
    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.caption)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(query.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(query.sql)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            vm.newQueryTab(sql: query.sql)
        }
        .contextMenu {
            Button {
                vm.newQueryTab(sql: query.sql)
            } label: {
                Label("Open Query", systemImage: "plus.square.on.square")
            }

            Divider()

            Button {
                renameText = query.name
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                vm.deleteSavedQuery(query)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .foregroundColor(.red)
        }
        .sheet(isPresented: $showRename) {
            renameSheet
        }
    }

    private var renameSheet: some View {
        VStack(spacing: 16) {
            Text("Rename Query")
                .font(.headline)
            TextField("Query name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack {
                Button("Cancel") { showRename = false }
                    .buttonStyle(.borderless)
                Button("Save") {
                    vm.renameSavedQuery(query, name: renameText)
                    showRename = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - Table Row

private struct TableRow: View {
    let table: TableInfo

    @EnvironmentObject var vm: DatabaseViewModel

    private var quote: String {
        guard let db = vm.selectedConnection?.dbType else { return "\"" }
        switch db {
        case .mysql, .mariaDb: return ""
        default: return "\""
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tablecells")
                .foregroundColor(.accentColor)
                .font(.body)

            Text(table.name)
                .fontWeight(.semibold)
                .lineLimit(1)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            Task { await vm.quickView(table: table) }
        }
        .contextMenu {
            Button {
                Task { await vm.quickView(table: table) }
            } label: {
                Label("Quick View", systemImage: "eye")
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])

            Button {
                vm.newQueryTab(sql: "SELECT * FROM \(quote)\(table.name)\(quote) LIMIT 50;")
            } label: {
                Label("SELECT * FROM \(quote)\(table.name)\(quote) LIMIT 50", systemImage: "play")
            }

            Button {
                vm.newQueryTab(sql: "SELECT COUNT(*) FROM \(quote)\(table.name)\(quote);")
            } label: {
                Label("SELECT COUNT(*) FROM \(quote)\(table.name)\(quote)", systemImage: "number.circle")
            }

            Button {
                vm.newQueryTab(sql: "SELECT * FROM \(quote)\(table.name)\(quote);")
            } label: {
                Label("SELECT * FROM \(quote)\(table.name)\(quote)", systemImage: "tablecells")
            }

            Divider()

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(table.name, forType: .string)
            } label: {
                Label("Copy Table Name", systemImage: "doc.on.doc")
            }
        }
    }
}
