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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tabPill(_ tab: QueryTab) -> some View {
        let isActive = tab.id == vm.activeQueryTabId
        return HStack(spacing: 4) {
            Text(tab.title)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .lineLimit(1)

            if tab.queryLoadState.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }

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

    init(tab: QueryTab, onSave: ((QueryTab) -> Void)? = nil) {
        self.tab = tab
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            editorPane
                .frame(height: editorHeight)

            resizableDivider

            resultsPane
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

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("SQL Editor", systemImage: "pencil.and.outline")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                saveButton
                formatButton
                runAllButton
                runButton
            }

            CodeEditor(text: $tab.sqlInput)
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
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(12)
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
        .frame(maxWidth: .infinity, maxHeight: 40)
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
        .frame(maxWidth: .infinity, minHeight: 40)
    }
}
