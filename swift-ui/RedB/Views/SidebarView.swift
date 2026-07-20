import SwiftUI

private func dbIcon(for type: DbType) -> Image {
    switch type {
    case .sqlite: return Image(systemName: "cylinder.split.1x2")
    case .postgres: return Image("pgsql-icon")
    case .mysql: return Image("mysql-icon")
    case .mariaDb: return Image("mariadb-icon")
    case .sqlServer: return Image(systemName: "server.rack")
    case .db2: return Image(systemName: "square.3.layers.3d")
    }
}

struct SidebarView: View {
    @EnvironmentObject var vm: DatabaseViewModel
    var body: some View {
        List(selection: $vm.selectedConnection) {
            ForEach(vm.connections) { profile in
                ConnectionRow(profile: profile)
                    .tag(profile)
            }
            .onDelete { indices in
                for i in indices { vm.removeConnection(vm.connections[i]) }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("RedB")
        .sheet(isPresented: $showAddSheet) { AddConnectionSheet() }
        .toolbar { sidebarToolbar }
        .overlay(emptyOverlay)
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if vm.connections.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No Connections")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Click + to add a database")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @State private var showAddSheet = false

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}
// MARK: - Connection Row

private struct ConnectionRow: View {
    let profile: ConnectionProfile

    @EnvironmentObject var vm: DatabaseViewModel
    @State private var showEditSheet = false

    var body: some View {
        HStack(spacing: 10) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    dbIcon(for: profile.dbType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(profile.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                Text(profile.url)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if vm.bridge.connectionStatus == .connected
                && vm.selectedConnection?.id == profile.id {
                Button("Disconnect") {
                    Task { await vm.disconnect() }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.secondary)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: vm.bridge.connectionStatus)
        .onTapGesture(count: 2) {
            guard !vm.isConnected(profile) else { return }
            vm.selectedConnection = profile
            Task { await vm.connect(profile) }
        }
        .contextMenu {
            if vm.bridge.connectionStatus == .connected && vm.selectedConnection?.id == profile.id {
                Button {
                    vm.newQueryTab()
                } label: {
                    Label("New Query", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button {
                    vm.newQueryTab(sql: "CREATE TABLE new_table (\n    id INTEGER PRIMARY KEY,\n    name TEXT\n);")
                } label: {
                    Label("New Table", systemImage: "rectangle.stack.badge.plus")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()
            }

            Button("Edit Connection") { showEditSheet = true }
            Divider()
            if vm.bridge.connectionStatus == .connected && vm.selectedConnection?.id == profile.id {
                Button("Disconnect") { Task { await vm.disconnect() } }
            } else {
                Button("Connect") {
                    vm.selectedConnection = profile
                    Task { await vm.connect(profile) }
                }
            }
            Divider()
            Button("Remove", role: .destructive) { vm.removeConnection(profile) }
        }
        .sheet(isPresented: $showEditSheet) {
            EditConnectionSheet(profile: profile)
        }
    }

    private var statusDot: some View {
        let isActive = vm.bridge.connectionStatus == .connected
            && vm.selectedConnection?.id == profile.id
        return Circle()
            .fill(isActive ? Color.green : Color.gray.opacity(0.4))
            .frame(width: 8, height: 8)
    }
}

// MARK: - Add Connection Sheet

private struct AddConnectionSheet: View {
    @EnvironmentObject var vm: DatabaseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: DbType = .sqlite
    @State private var name: String = ""
    @State private var filePath: String = ""
    @State private var host: String = "localhost"
    @State private var port: String = ""
    @State private var database: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var testState: TestState = .idle

    private enum TestState {
        case idle, testing, success, failure(String)
    }

    private var resolvedPort: UInt32 {
        UInt32(port) ?? selectedType.defaultPort
    }

    private var isValid: Bool {
        !name.isEmpty && (selectedType == .sqlite ? !filePath.isEmpty : !database.isEmpty)
    }

    var body: some View {
        HStack(spacing: 0) {
            typeList
            Divider()
            formPanel
        }
        .frame(width: 560, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Left - Type List

    private var typeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Database Type")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(sortedTypes) { type in
                Button {
                    selectedType = type
                } label: {
                    HStack(spacing: 10) {
                        dbIcon(for: type)
                            .font(.title3)
                            .foregroundColor(selectedType == type ? .accentColor : .secondary)
                            .frame(width: 24)

                        Text(type.rawValue)
                            .fontWeight(selectedType == type ? .semibold : .regular)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedType == type ? Color.accentColor.opacity(0.1) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(width: 160)
    }

    private var sortedTypes: [DbType] {
        DbType.allCases
            .filter { $0 != .sqlite }
            .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
    }

    // MARK: Right - Form

    private var formPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    formHeader
                    formFields
                }
                .padding(20)
            }

            Divider()

            footer
        }
    }

    private var formHeader: some View {
        VStack(spacing: 4) {
            dbIcon(for: selectedType)
                .font(.system(size: 28))
                .foregroundColor(.accentColor)
            Text("Connect to \(selectedType.rawValue)")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private var formFields: some View {
        VStack(spacing: 12) {
            formField("Connection Name") {
                TextField("My Database", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            if selectedType == .sqlite {
                formField("Database File") {
                    HStack(spacing: 6) {
                        TextField("/path/to/database.sqlite", text: $filePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                        Button {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.data, .database]
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK {
                                filePath = panel.url?.path ?? ""
                                if name.isEmpty {
                                    name = panel.url?.deletingPathExtension().lastPathComponent ?? ""
                                }
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if selectedType != .sqlite {
                HStack(spacing: 8) {
                    formField("Host") {
                        TextField("localhost", text: $host)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                    }
                    formField("Port") {
                        TextField("\(selectedType.defaultPort)", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .font(.body.monospaced())
                    }
                }

                formField("Database") {
                    TextField("database_name", text: $database)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }

                formField("Username") {
                    TextField("user", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }

                formField("Password") {
                    SecureField("password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            testStatusBar
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
                Spacer()
                testButton
                Button("Add & Connect") { addAndConnect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var testStatusBar: some View {
        HStack(spacing: 6) {
            switch testState {
            case .idle:
                EmptyView()
            case .testing:
                ProgressView().scaleEffect(0.7)
                Text("Testing connection...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connection successful")
                    .font(.caption)
                    .foregroundColor(.green)
            case .failure(let msg):
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }

    private var testButton: some View {
        Button {
            Task { await performTest() }
        } label: {
            if case .testing = testState {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text("Test Connection")
        }
        .buttonStyle(.borderless)
        .disabled(!isValid || {
            if case .testing = testState { true } else { false }
        }())
    }

    private func performTest() async {
        let url = buildUrl()

        testState = .testing
        do {
            try await RustBridge.testConnect(
                dbType: selectedType.toFFI,
                url: url,
                host: host.isEmpty ? nil : host,
                port: resolvedPort,
                database: database.isEmpty ? nil : database,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password
            )
            testState = .success
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func buildUrl() -> String {
        switch selectedType {
        case .sqlite:
            return filePath.hasPrefix("/") ? "sqlite:\(filePath)" : "sqlite:/\(filePath)"
        case .postgres:
            return "postgres://\(host):\(resolvedPort)/\(database)"
        case .mysql, .mariaDb:
            return "mysql://\(host):\(resolvedPort)/\(database)"
        case .sqlServer:
            return "sqlserver://\(host):\(resolvedPort)/\(database)"
        case .db2:
            return "db2://\(host):\(resolvedPort)/\(database)"
        }
    }

    private func addAndConnect() {
        let url = buildUrl()

        let profile = ConnectionProfile(
            name: name,
            dbType: selectedType,
            url: url,
            host: host,
            port: resolvedPort,
            database: database,
            username: username,
            password: password
        )
        vm.addConnection(profile)
        dismiss()
    }

    // MARK: Helpers

    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content()
        }
    }
}

// MARK: - Edit Connection Sheet

private struct EditConnectionSheet: View {
    @EnvironmentObject var vm: DatabaseViewModel
    @Environment(\.dismiss) private var dismiss

    let profile: ConnectionProfile

    @State private var name: String = ""
    @State private var selectedType: DbType = .sqlite
    @State private var filePath: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var database: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var testState: TestState = .idle

    private enum TestState {
        case idle, testing, success, failure(String)
    }

    private var resolvedPort: UInt32 {
        UInt32(port) ?? selectedType.defaultPort
    }

    private var isValid: Bool {
        !name.isEmpty && (selectedType == .sqlite ? !filePath.isEmpty : !database.isEmpty)
    }

    var body: some View {
        HStack(spacing: 0) {
            typeList
            Divider()
            formPanel
        }
        .frame(width: 560, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            name = profile.name
            selectedType = profile.dbType
            host = profile.host
            port = "\(profile.port)"
            database = profile.database
            username = profile.username
            password = profile.password
            if profile.dbType == .sqlite {
                filePath = profile.url.replacingOccurrences(of: "sqlite:", with: "")
            }
        }
    }

    private var typeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Database Type")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(sortedTypes) { type in
                Button {
                    selectedType = type
                } label: {
                    HStack(spacing: 10) {
                        dbIcon(for: type)
                            .font(.title3)
                            .foregroundColor(selectedType == type ? .accentColor : .secondary)
                            .frame(width: 24)
                        Text(type.rawValue)
                            .fontWeight(selectedType == type ? .semibold : .regular)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedType == type ? Color.accentColor.opacity(0.1) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 160)
    }

    private var sortedTypes: [DbType] {
        DbType.allCases
            .filter { $0 != .sqlite }
            .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
    }

    private var formPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        dbIcon(for: selectedType)
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor)
                        Text("Edit \(selectedType.rawValue) Connection")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)

                    VStack(spacing: 12) {
                        formField("Connection Name") {
                            TextField("My Database", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }

                        if selectedType == .sqlite {
                            formField("Database File") {
                                HStack(spacing: 6) {
                                    TextField("/path/to/database.sqlite", text: $filePath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.body.monospaced())
                                    Button {
                                        let panel = NSOpenPanel()
                                        panel.allowedContentTypes = [.data, .database]
                                        panel.canChooseDirectories = false
                                        panel.allowsMultipleSelection = false
                                        if panel.runModal() == .OK {
                                            filePath = panel.url?.path ?? ""
                                        }
                                    } label: { Image(systemName: "folder") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }

                        if selectedType != .sqlite {
                            HStack(spacing: 8) {
                                formField("Host") {
                                    TextField("localhost", text: $host)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.body.monospaced())
                                }
                                formField("Port") {
                                    TextField("\(selectedType.defaultPort)", text: $port)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 70)
                                        .font(.body.monospaced())
                                }
                            }
                            formField("Database") {
                                TextField("database_name", text: $database)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body.monospaced())
                            }
                            formField("Username") {
                                TextField("user", text: $username)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body.monospaced())
                            }
                            formField("Password") {
                                SecureField("password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body.monospaced())
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            VStack(spacing: 8) {
                editTestStatusBar
                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.borderless)
                    Spacer()
                    editTestButton
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var editTestStatusBar: some View {
        HStack(spacing: 6) {
            switch testState {
            case .idle:
                EmptyView()
            case .testing:
                ProgressView().scaleEffect(0.7)
                Text("Testing connection...")
                    .font(.caption).foregroundColor(.secondary)
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Connection successful").font(.caption).foregroundColor(.green)
            case .failure(let msg):
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                Text(msg).font(.caption).foregroundColor(.red).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }

    private var editTestButton: some View {
        Button {
            Task { await performEditTest() }
        } label: {
            if case .testing = testState {
                ProgressView().scaleEffect(0.7)
            }
            Text("Test Connection")
        }
        .buttonStyle(.borderless)
        .disabled(!isValid || {
            if case .testing = testState { true } else { false }
        }())
    }

    private func editBuildUrl() -> String {
        switch selectedType {
        case .sqlite:
            return filePath.hasPrefix("/") ? "sqlite:\(filePath)" : "sqlite:/\(filePath)"
        case .postgres:
            return "postgres://\(host):\(resolvedPort)/\(database)"
        case .mysql, .mariaDb:
            return "mysql://\(host):\(resolvedPort)/\(database)"
        case .sqlServer:
            return "sqlserver://\(host):\(resolvedPort)/\(database)"
        case .db2:
            return "db2://\(host):\(resolvedPort)/\(database)"
        }
    }

    private func performEditTest() async {
        let url = editBuildUrl()

        testState = .testing
        do {
            try await RustBridge.testConnect(
                dbType: selectedType.toFFI,
                url: url,
                host: host.isEmpty ? nil : host,
                port: resolvedPort,
                database: database.isEmpty ? nil : database,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password
            )
            testState = .success
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func save() {
        let url = editBuildUrl()

        var updated = profile
        updated.name = name
        updated.dbType = selectedType
        updated.url = url
        updated.host = host
        updated.port = resolvedPort
        updated.database = database
        updated.username = username
        updated.password = password
        vm.updateConnection(updated)
        dismiss()
    }

    private func formField(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content()
        }
    }
}
