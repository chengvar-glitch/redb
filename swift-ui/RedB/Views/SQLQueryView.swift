import SwiftUI

struct SQLQueryView: View {
    @EnvironmentObject var vm: DatabaseViewModel
    @State private var showSaveSheet = false
    @State private var saveQueryName = ""
    @State private var tabToSave: QueryTab?

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            if let tab = vm.activeQueryTab {
                QueryTabContentView(tab: tab, onSave: { tabToSave = $0; saveQueryName = $0.title; showSaveSheet = true })
                    .id(tab.id)
            } else {
                emptyState
            }
        }
        .navigationTitle("Query")
        .sheet(isPresented: $showSaveSheet) {
            saveSheet
        }
    }

    private var saveSheet: some View {
        VStack(spacing: 16) {
            Text("Save Query")
                .font(.headline)
            TextField("Query name", text: $saveQueryName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack {
                Button("Cancel") { showSaveSheet = false }
                    .buttonStyle(.borderless)
                Button("Save") {
                    if let t = tabToSave ?? vm.activeQueryTab {
                        vm.saveQuery(name: saveQueryName, sql: t.sqlInput)
                    }
                    showSaveSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveQueryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(vm.queryTabs) { tab in
                    tabPill(tab)
                }

                addTabButton

                if vm.queryTabs.count > 5 {
                    tabBucketMenu
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tabBucketMenu: some View {
        Menu {
            ForEach(vm.queryTabs) { tab in
                Button {
                    vm.activeQueryTabId = tab.id
                } label: {
                    HStack(spacing: 6) {
                        if tab.id == vm.activeQueryTabId {
                            Image(systemName: "checkmark")
                        }
                        Text(tab.title)
                            .lineLimit(1)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("All Tabs")
    }

    private func tabPill(_ tab: QueryTab) -> some View {
        let isActive = tab.id == vm.activeQueryTabId
        return HStack(spacing: 4) {
            Text(tab.title)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .lineLimit(1)

            Button {
                vm.closeQueryTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            vm.activeQueryTabId = tab.id
        }
        .contextMenu {
            Button {
                tabToSave = tab
                saveQueryName = tab.title
                showSaveSheet = true
            } label: {
                Label("Save Query", systemImage: "bookmark")
            }
            .disabled(tab.sqlInput.trimmingCharacters(in: .whitespaces).isEmpty)

            Divider()

            Button {
                vm.closeQueryTab(tab)
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
    }

    private var addTabButton: some View {
        Button {
            vm.newQueryTab()
        } label: {
            Image(systemName: "plus")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help("New Query")
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.square.on.square")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No query tabs open")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("New Query") { vm.newQueryTab() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Query Tab Content

private struct QueryTabContentView: View {
    @ObservedObject var tab: QueryTab
    @EnvironmentObject var vm: DatabaseViewModel
    let onSave: ((QueryTab) -> Void)?
    @FocusState private var isEditorFocused: Bool

    @State private var editorHeight: CGFloat = 160
    @State private var showSaveDialog = false
    @State private var saveName: String = ""

    init(tab: QueryTab, onSave: ((QueryTab) -> Void)? = nil) {
        self.tab = tab
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            if tab.queryLoadState.isLoaded || tab.queryLoadState.isLoading {
                editorPane
                    .frame(height: editorHeight)
                resizableDivider
                resultsPane
            } else {
                editorPane
                    .frame(maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tab.queryLoadState.isLoaded || tab.queryLoadState.isLoading)
        .background(
            Button("") {
                saveName = tab.title
                showSaveDialog = true
            }
            .keyboardShortcut("s", modifiers: [.command])
            .hidden()
        )
        .background(
            Button("") {
                vm.newQueryTab()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .hidden()
        )
        .alert("Save Query", isPresented: $showSaveDialog) {
            TextField("Query name", text: $saveName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                vm.saveQuery(name: saveName, sql: tab.sqlInput)
            }
        } message: {
            Text("Enter a name for this query")
        }
    }

    private var resizableDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(height: 4)
            .onHover { hover in
                if hover { NSCursor.resizeUpDown.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newHeight = editorHeight + value.translation.height
                        editorHeight = max(60, min(newHeight, 600))
                    }
            )
    }

    // MARK: - Editor

    @State private var suggestions: [String] = []
    @State private var suggestPrefix = ""
    @State private var selectedIndex = 0

    private var editorPane: some View {
        CodeEditor(text: $tab.sqlInput, onSuggest: { prefix, cursor in
            suggestPrefix = prefix
            suggestions = computeSuggestions(prefix, cursor: cursor)
            selectedIndex = 0
            return suggestions
        }, onTab: {
            if !suggestions.isEmpty { acceptFirstSuggestion() }
        }, onArrowUp: {
            guard !suggestions.isEmpty else { return }
            selectedIndex = (selectedIndex - 1 + suggestions.count) % suggestions.count
        }, onArrowDown: {
            guard !suggestions.isEmpty else { return }
            selectedIndex = (selectedIndex + 1) % min(suggestions.count, 12)
        }, onEnter: {
            if !suggestions.isEmpty && selectedIndex < suggestions.count {
                acceptSuggestion(suggestions[selectedIndex])
            }
        }, onEscape: {
            suggestions = []
            suggestPrefix = ""
        })
            .frame(minHeight: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if tab.sqlInput.isEmpty {
                    Text("Enter SQL…")
                        .font(.body.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(EdgeInsets(top: 6, leading: 6, bottom: 0, trailing: 0))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 4) {
                    saveButton
                    formatButton
                    runAllButton
                    runButton
                }
                .padding(6)
            }
            .overlay(alignment: .topLeading) {
                suggestionPopup
            }
    }

    @ViewBuilder
    private var suggestionPopup: some View {
        if !suggestions.isEmpty && !suggestPrefix.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.prefix(12).enumerated()), id: \.offset) { i, item in
                        Button {
                            acceptSuggestion(item)
                        } label: {
                            Text(item)
                                .font(.body.monospaced())
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .background(
                            i == selectedIndex ? Color.accentColor.opacity(0.12) : Color.clear
                        )
                        .onHover { isHovered in
                            if isHovered { NSCursor.pointingHand.push() }
                            else { NSCursor.pop() }
                        }

                        if i < min(suggestions.count, 12) - 1 {
                            Divider().padding(.leading, 8)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            .frame(width: 260)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
            .padding(EdgeInsets(top: 30, leading: 4, bottom: 0, trailing: 0))
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeOut(duration: 0.12), value: suggestions.isEmpty)
        }
    }

    private func computeSuggestions(_ prefix: String, cursor: Int) -> [String] {
        guard prefix.count >= 1 else { return [] }

        let context = analyzeSqlContext(sql: tab.sqlInput, cursor: UInt64(cursor))
        let lower = prefix.lowercased()

        switch context.completionType {
        case .statement:
            let keywords = ["SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
                            "TRUNCATE", "WITH", "EXPLAIN", "SHOW", "USE"]
            return keywords.filter { $0.lowercased().hasPrefix(lower) }

        case .tableName:
            var tables = vm.tableSuggestions(matching: prefix)
            for t in tables {
                let alias = vm.aliasForTable(t)
                if alias != t { tables.append("\(t) \(alias)") }
            }
            return tables

        case .columnName:
            let cols = vm.columnSuggestions(matching: prefix)
            let funcs = allSQLFunctions.filter { $0.lowercased().hasPrefix(lower) }.map { "\($0)()" }
            return Array((cols + funcs).prefix(20))

        case .function:
            return allSQLFunctions.filter { $0.lowercased().hasPrefix(lower) }.map { "\($0)()" }

        case .keyword:
            let clauses = ["WHERE", "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "OFFSET",
                           "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN",
                           "ON", "AND", "OR", "IN", "NOT IN", "BETWEEN", "LIKE",
                           "IS NULL", "IS NOT NULL", "UNION", "UNION ALL"]
            return clauses.filter { $0.lowercased().hasPrefix(lower) }

        case .value:
            return []

        case .alias:
            return []
        }
    }

    private func acceptSuggestion(_ item: String) {
        guard let i = tab.sqlInput.range(of: suggestPrefix, options: [.backwards, .caseInsensitive]) else { return }
        let before = tab.sqlInput[tab.sqlInput.startIndex..<i.lowerBound]
        let after = tab.sqlInput[i.upperBound...]
        tab.sqlInput = String(before) + item + String(after)
        suggestions = []
        suggestPrefix = ""
    }

    private func acceptFirstSuggestion() {
        guard let first = suggestions.first else { return }
        acceptSuggestion(first)
    }

    private var runButton: some View {
        Button {
            Task { await vm.executeQuery() }
        } label: {
            Label("Run", systemImage: "play.fill")
                .frame(minWidth: 60)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(tab.sqlInput.trimmingCharacters(in: .whitespaces).isEmpty
            || vm.bridge.connectionStatus != .connected)
        .onHover { if $0 { NSCursor.arrow.push() } else { NSCursor.pop() } }
    }

    private var runAllButton: some View {
        Button {
            Task { await vm.executeQuery() }
        } label: {
            Label("Run All", systemImage: "play.rectangle.fill")
                .frame(minWidth: 60)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .keyboardShortcut(.return, modifiers: [.command, .shift])
        .disabled(tab.sqlInput.trimmingCharacters(in: .whitespaces).isEmpty
            || vm.bridge.connectionStatus != .connected)
        .onHover { if $0 { NSCursor.arrow.push() } else { NSCursor.pop() } }
    }

    private var saveButton: some View {
        Button {
            onSave?(tab)
        } label: {
            Image(systemName: "bookmark")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Save Query")
        .disabled(tab.sqlInput.trimmingCharacters(in: .whitespaces).isEmpty)
        .onHover { if $0 { NSCursor.arrow.push() } else { NSCursor.pop() } }
    }

    private var formatButton: some View {
        Button {
            tab.sqlInput = formatSQL(tab.sqlInput)
        } label: {
            Image(systemName: "text.redaction")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Format SQL")
        .disabled(tab.sqlInput.trimmingCharacters(in: .whitespaces).isEmpty)
        .onHover { if $0 { NSCursor.arrow.push() } else { NSCursor.pop() } }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsPane: some View {
        switch tab.queryLoadState {
        case .loading:
            loadingResults
        case .success(let results):
            if results.count == 1 {
                QueryResultView(result: results[0])
                    .environmentObject(vm)
            } else {
                MultiResultView(results: results)
            }
        case .failure(let msg):
            failureResults(msg)
        default:
            EmptyView()
        }
    }

    private struct MultiResultView: View {
        let results: [QueryResult]

        var body: some View {
            TabView {
                ForEach(Array(results.enumerated()), id: \.offset) { i, r in
                    QueryResultView(result: r)
                        .tabItem {
                            Text("Result \(i + 1)")
                        }
                }
            }
            .tabViewStyle(.automatic)
        }
    }

    private var loadingResults: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Running query…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureResults(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(.red)
            Text(msg)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: .infinity)
    }
}
