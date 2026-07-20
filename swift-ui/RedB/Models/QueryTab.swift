import SwiftUI

class QueryTab: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    @Published var sqlInput: String = ""
    @Published var queryLoadState: LoadState<[QueryResult]> = .idle
    @Published var rowLimit: Int = 50
    let createdAt: Date = .now

    init(title: String = "Query", sqlInput: String = "") {
        self.title = title
        self.sqlInput = sqlInput
    }
}
