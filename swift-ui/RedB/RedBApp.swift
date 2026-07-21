import SwiftUI

@main
struct RedBApp: App {
    @StateObject private var vm = DatabaseViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands { appCommands }
    }

    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Connection") {
                NotificationCenter.default.post(name: .init("newConnection"), object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}

// MARK: - ContentView (Three-Column Layout)

struct ContentView: View {
    @EnvironmentObject var vm: DatabaseViewModel
    @State private var showErrorAlert = false
    @State private var isMiddleCollapsed = true

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)

        } detail: {
            HStack(spacing: 0) {
                TableBrowserView()
                    .frame(width: isMiddleCollapsed ? 0 : 280)
                    .clipped()
                    .opacity(isMiddleCollapsed ? 0 : 1)

                if !isMiddleCollapsed {
                    Divider()
                }

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(.easeInOut(duration: 0.18), value: isMiddleCollapsed)
            .navigationSplitViewColumnWidth(min: 400, ideal: 550)
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar { connectionToolbar }
        .background(
            Button("") {
                if let tab = vm.activeQueryTab {
                    vm.closeQueryTab(tab)
                }
            }
            .keyboardShortcut("w", modifiers: [.command])
            .hidden()
        )
        .alert("Connection Failed", isPresented: $showErrorAlert) {
            Button("Dismiss") { vm.connectionError = nil }
        } message: {
            Text(vm.connectionError ?? "")
        }
        .onChange(of: vm.connectionError) { err in
            showErrorAlert = err != nil
        }
        .onChange(of: vm.bridge.connectionStatus) { status in
            if status == .connected {
                isMiddleCollapsed = false
            }
        }
        .onChange(of: vm.selectedConnection) { profile in
            guard let p = profile,
                  vm.bridge.connectionStatus != .connected,
                  !vm.isConnecting
            else { return }
            Task { await vm.connect(p) }
        }
        .alert("Tab Limit Reached", isPresented: $vm.showMaxTabsAlert) {
            Button("Dismiss") {}
        } message: {
            Text("You can have at most \(DatabaseViewModel.maxTabs) query tabs open at once. Close some tabs before opening new ones.")
        }
    }

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if vm.quickViewLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Running query…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SQLQueryView()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var connectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 2) {
                Button {
                    isMiddleCollapsed.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help(isMiddleCollapsed ? "Show Tables" : "Hide Tables")

                if vm.bridge.connectionStatus == .connected {
                    Button {
                        Task { await vm.refreshTables() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Tables")
                }
            }
        }
    }
}
