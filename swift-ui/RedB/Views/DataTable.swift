import SwiftUI
import AppKit

// MARK: - NSTableView Wrapper (native performance for large datasets)

struct DataTable: NSViewRepresentable {
    let columns: [ColumnInfo]
    let rows: [[CellValue]]
    let sortColumn: Int?
    let sortDescending: Bool
    let selectedRow: Int?

    var onSort: ((Int, Bool) -> Void)?
    var onSelectRow: ((Int?) -> Void)?
    var onCopy: (() -> Void)?
    var onDoubleClickCell: ((_ row: Int, _ col: Int) -> Void)?
    var onCommitEdit: ((_ row: Int, _ col: Int, _ newValue: String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .regular
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.floatsGroupRows = false
        tableView.headerView = NSTableHeaderView()

        // Row number column
        let rowCol = NSTableColumn(identifier: .rowNumber)
        rowCol.title = "#"
        rowCol.width = 36
        rowCol.minWidth = 36
        rowCol.maxWidth = 36
        rowCol.headerCell.alignment = .right
        rowCol.isEditable = false
        tableView.addTableColumn(rowCol)

        // Data columns
        for (i, col) in columns.enumerated() {
            let identifier = NSUserInterfaceItemIdentifier("col_\(i)")
            let tableCol = NSTableColumn(identifier: identifier)
            tableCol.title = col.name
            tableCol.width = 120
            tableCol.minWidth = 60
            tableCol.maxWidth = 500
            tableCol.headerCell.alignment = .left
            tableCol.isEditable = false
            tableCol.sortDescriptorPrototype = NSSortDescriptor(
                key: "col_\(i)", ascending: true,
                selector: #selector(NSString.localizedStandardCompare(_:))
            )
            tableView.addTableColumn(tableCol)
        }

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClickRow(_:))

        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        // Update columns if changed
        if tableView.tableColumns.count - 1 != columns.count {
            // Rebuild columns (simplified: remove all, re-add)
            while tableView.tableColumns.count > 1 {
                tableView.removeTableColumn(tableView.tableColumns.last!)
            }
            for (i, col) in columns.enumerated() {
                let identifier = NSUserInterfaceItemIdentifier("col_\(i)")
                let tableCol = NSTableColumn(identifier: identifier)
                tableCol.title = col.name
                tableCol.width = 120
                tableCol.minWidth = 60
                tableCol.maxWidth = 500
                tableCol.sortDescriptorPrototype = NSSortDescriptor(
                    key: "col_\(i)", ascending: true,
                    selector: #selector(NSString.localizedStandardCompare(_:))
                )
                tableView.addTableColumn(tableCol)
            }
        }

        // Update sort indicators
        for i in 0..<columns.count {
            let col = tableView.tableColumns[i + 1]
            if i == sortColumn {
                col.sortDescriptorPrototype = NSSortDescriptor(
                    key: "col_\(i)",
                    ascending: !sortDescending
                )
                // Set the sort indicator
                tableView.setIndicatorImage(
                    sortDescending ? NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage()
                                  : NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil) ?? NSImage(),
                    in: col
                )
            } else {
                col.sortDescriptorPrototype = NSSortDescriptor(
                    key: "col_\(i)", ascending: true,
                    selector: #selector(NSString.localizedStandardCompare(_:))
                )
                tableView.setIndicatorImage(nil, in: col)
            }
        }

        // Update selection
        if let row = selectedRow, row >= 0, row < rows.count {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }

        tableView.reloadData()
        context.coordinator.parent = self
    }
}

// MARK: - Coordinator

extension DataTable {
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: DataTable

        init(_ parent: DataTable) {
            self.parent = parent
        }

        // MARK: Data Source

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count else { return nil }

            let identifier = tableColumn?.identifier ?? .rowNumber
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? TextCell
                ?? TextCell(identifier: identifier)

            if identifier == .rowNumber {
                cell.textField?.stringValue = "\(row + 1)"
                cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                cell.textField?.textColor = NSColor.tertiaryLabelColor
                cell.textField?.alignment = .right
                return cell
            }

            guard let idStr = identifier.rawValue.split(separator: "_").last,
                  let colIdx = Int(idStr),
                  colIdx < parent.rows[row].count else {
                cell.textField?.stringValue = ""
                return cell
            }

            let value = parent.rows[row][colIdx]
            cell.textField?.stringValue = displayCellValue(value)
            cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textField?.textColor = cellForegroundColor(value)
            cell.textField?.alignment = cellAlignment(value)

            return cell
        }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            parent.onSelectRow?(row)
            return true
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let desc = tableView.sortDescriptors.first,
                  let key = desc.key,
                  let idStr = key.split(separator: "_").last,
                  let colIdx = Int(idStr) else { return }
            parent.onSort?(colIdx, !desc.ascending)
        }

        // MARK: Double-click editing

        @objc func doubleClickRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            let col = sender.clickedColumn - 1 // offset for row number column
            guard row >= 0, row < parent.rows.count,
                  col >= 0, col < parent.columns.count else { return }
            parent.onDoubleClickCell?(row, col)
        }

}
}

// MARK: - Custom Cell View

private class TextCell: NSTableCellView {
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 22))

        let textField = NSTextField(frame: .zero)
        textField.isBordered = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 20)
        ])

        self.textField = textField
        self.identifier = identifier
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Identifier

private extension NSUserInterfaceItemIdentifier {
    static let rowNumber = NSUserInterfaceItemIdentifier("rowNumber")
}

// MARK: - Cell value rendering

private func displayCellValue(_ cv: CellValue) -> String {
    switch cv {
    case .null:         return "NULL"
    case .int(let v):   return "\(v)"
    case .float(let v): return "\(v)"
    case .text(let v):  return v
    case .blob(let v):  return "<blob \(v.count)B>"
    }
}

private func cellForegroundColor(_ cv: CellValue) -> NSColor {
    switch cv {
    case .null:         return NSColor.tertiaryLabelColor
    case .int, .float:  return NSColor.controlAccentColor
    case .text:         return NSColor.labelColor
    case .blob:         return NSColor.secondaryLabelColor
    }
}

private func cellAlignment(_ cv: CellValue) -> NSTextAlignment {
    switch cv {
    case .int, .float:  return .right
    case .null:         return .center
    default:            return .left
    }
}
