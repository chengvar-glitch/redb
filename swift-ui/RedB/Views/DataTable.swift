import SwiftUI
import AppKit

// MARK: - Context Menu Actions

enum DataTableAction {
    case copyCell(row: Int, col: Int)
    case copyRow(row: Int)
    case copySelected(rows: Set<Int>)
    case copySelectedAsCSV(rows: Set<Int>)
    case deleteRows(rows: Set<Int>, table: String)
}

// MARK: - NSTableView Wrapper

struct DataTable: NSViewRepresentable {
    let columns: [ColumnInfo]
    let rows: [[CellValue]]
    let sortColumn: Int?
    let sortDescending: Bool
    let selectedRows: Set<Int>
    let pkColumnIndices: [Int]
    let tableName: String?

    var onSort: ((Int, Bool) -> Void)?
    var onSelectedRowsChanged: ((Set<Int>) -> Void)?
    var onCommitEdit: ((_ row: Int, _ col: Int, _ newValue: String) -> Void)?
    var onDataTableAction: ((DataTableAction) -> Void)?
    /// Called when the user clicks Save — flush all pending edits to DB.
    var onSave: (() -> Void)?
    /// Called whenever the count of unflushed edits changes (0 = no pending).
    /// Parent can show/hide a save button based on this.
    var onPendingCountChanged: ((Int) -> Void)?
    /// Increment to trigger a save from outside (e.g. toolbar button).
    var saveCounter: Int = 0
    /// Increment to revert all pending edits (discard & reload original values).
    var revertCounter: Int = 0

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
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 26
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

        // Context menu: must set a dummy menu for right-click to work on macOS
        tableView.menu = NSMenu()

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClickRow(_:))

        scrollView.documentView = tableView

        // Summary footer view
        let footer = context.coordinator.footerView
        footer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 22)
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        let coord = context.coordinator

        // Track whether data content actually changed (column/row count)
        let newVersion = columns.count * 100000 + rows.count
        let dataChanged = newVersion != coord.dataVersion

        if dataChanged {
            coord.dataVersion = newVersion

            // Rebuild columns if count changed
            if tableView.tableColumns.count - 1 != columns.count {
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
        }

        // Update sort indicators (visual-only, harmless to run every cycle)
        for i in 0..<columns.count {
            let col = tableView.tableColumns[i + 1]
            if i == sortColumn {
                col.sortDescriptorPrototype = NSSortDescriptor(
                    key: "col_\(i)",
                    ascending: !sortDescending
                )
                tableView.setIndicatorImage(
                    sortDescending
                        ? NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage()
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

        // Update selection (only if changed externally)
        let currentSelection = Set(tableView.selectedRowIndexes.filter { $0 < rows.count })
        if currentSelection != selectedRows {
            tableView.selectRowIndexes(
                IndexSet(selectedRows.filter { $0 < rows.count }),
                byExtendingSelection: false
            )
        }

        coord.parent = self

        // External save trigger (toolbar Save button via saveCounter).
        if saveCounter != coord.lastSaveCounter {
            coord.lastSaveCounter = saveCounter
            coord.savePending()
        }

        // External revert trigger (toolbar Revert button via revertCounter).
        if revertCounter != coord.lastRevertCounter {
            coord.lastRevertCounter = revertCounter
            coord.revertPending()
        }

        coord.updateFooter()

        // reloadData clears NSTableView's internal selection — skip it when only
        // UI state (selection/sort) changed, to prevent selected-row flash.
        if dataChanged {
            tableView.reloadData()
        }
    }
}

// MARK: - Coordinator

extension DataTable {
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: DataTable
        var dataVersion: Int = 0
        var editingCell: (row: Int, col: Int)? = nil
        /// Pending edits accumulated across cells; all flushed on Enter.
        var pendingEdits: [(row: Int, col: Int, newValue: String)] = []
        /// Direct reference to the text field currently being edited.
        weak var editingTextField: NSTextField? = nil
        var hoveredRow: Int? = nil
        var activeSumColumns: Set<Int> = []
        /// Used to detect save signal from parent (toolbar Save button).
        var lastSaveCounter: Int = 0
        /// Used to detect revert signal from parent (toolbar Revert button).
        var lastRevertCounter: Int = 0

        fileprivate let footerView = SummaryFooterView()

        init(_ parent: DataTable) {
            self.parent = parent
            self.activeSumColumns = Self.initialActiveSumColumns(columns: parent.columns)
        }

        /// All numeric columns are active (show sum) by default.
        private static func initialActiveSumColumns(columns: [ColumnInfo]) -> Set<Int> {
            Set(columns.enumerated().compactMap { (i, col) in
                let type = col.dataType.lowercased()
                if type.contains("int") || type.contains("float") || type.contains("double")
                    || type.contains("decimal") || type.contains("numeric") || type.contains("real") {
                    return i
                }
                return nil
            })
        }

        // --- Summary ---

        func computeSummary() -> [String] {
            let colCount = parent.columns.count
            var result = [String](repeating: "", count: colCount)
            result[0] = "\(parent.rows.count) rows"

            for colIdx in activeSumColumns.sorted() where colIdx < colCount {
                let values = parent.rows.compactMap { row in
                    colIdx < row.count ? row[colIdx] : nil
                }
                guard !values.isEmpty else { continue }

                let numericValues: [Double] = values.compactMap { v in
                    switch v {
                    case .int(let n): return Double(n)
                    case .float(let n): return n
                    default: return nil
                    }
                }
                if !numericValues.isEmpty {
                    let sum = numericValues.reduce(0, +)
                    if sum == floor(sum) {
                        result[colIdx] = "\(Int(sum))"
                    } else {
                        result[colIdx] = String(format: "%.2f", sum)
                    }
                }
            }
            return result
        }

        func toggleColumnSum(_ colIdx: Int) {
            if activeSumColumns.contains(colIdx) {
                activeSumColumns.remove(colIdx)
            } else {
                activeSumColumns.insert(colIdx)
            }
            updateFooter()
        }

        func updateFooter() {
            footerView.onToggleColumn = { [weak self] idx in
                self?.toggleColumnSum(idx)
            }
            footerView.onSave = { [weak self] in
                self?.savePending()
            }
            footerView.update(
                summary: computeSummary(),
                columns: parent.columns,
                activeColumns: activeSumColumns,
                pendingCount: pendingEdits.count
            )
        }

        // --- Data Source ---

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count else { return nil }

            let identifier = tableColumn?.identifier ?? .rowNumber
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? DataCell
                ?? DataCell(identifier: identifier)
            cell.parentCoordinator = self
            cell.row = row
            cell.textField?.delegate = self

            if identifier == .rowNumber {
                cell.textField?.stringValue = "\(row + 1)"
                cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                cell.textField?.textColor = NSColor.tertiaryLabelColor
                cell.textField?.alignment = .right
                cell.textField?.isEditable = false
                cell.textField?.isSelectable = false
                return cell
            }

            guard let idStr = identifier.rawValue.split(separator: "_").last,
                  let colIdx = Int(idStr),
                  colIdx < parent.rows[row].count else {
                cell.textField?.stringValue = ""
                cell.textField?.isEditable = false
                return cell
            }

            let value = parent.rows[row][colIdx]

            // Cell-level selection: highlight only the (row, clickedColumn) cell.
            // NSTableView has no native cell selection, so we compose it from
            // selectedRowIndexes (multi-row) × clickedColumn (single column).
            // clickedColumn is a NSTableView column index (row-number = 0, data cols 1+).
            let isActiveCell = Self.isActiveCell(
                row: row,
                dataColIdx: colIdx,
                tableView: tableView
            )
            let isEditing = (editingCell?.row == row && editingCell?.col == colIdx)
            let hasPending = pendingEdits.contains(where: { $0.row == row && $0.col == colIdx })
            Self.applyCellHighlight(to: cell, isActiveCell: isActiveCell, isEditing: isEditing, hasPending: hasPending)

            if isEditing {
                cell.textField?.isEditable = true
                cell.textField?.isSelectable = true
                cell.textField?.delegate = self
            } else {
                cell.textField?.isEditable = false
                cell.textField?.isSelectable = false
            }

            // If this cell has a pending edit (not yet flushed to DB), show the
            // typed value so the user sees what they entered before pressing Enter.
            cell.textField?.stringValue = pendingDisplayValue(for: row, col: colIdx, original: value)
            cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textField?.textColor = cellForegroundColor(value)
            cell.textField?.alignment = cellAlignment(value)

            return cell
        }

        // --- NSTextFieldDelegate ---

        @objc func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = editingTextField,
                  let cell = tf.superview as? DataCell,
                  let row = cell.row,
                  let editCell = editingCell else {
                self.editingCell = nil
                self.editingTextField = nil
                return
            }

            let newValue = tf.stringValue
            let oldValue = editCell.col < parent.rows[row].count
                ? displayCellValue(parent.rows[row][editCell.col])
                : ""
            if newValue != oldValue {
                pendingEdits.append((row: editCell.row, col: editCell.col, newValue: newValue))
                notifyPendingCount()
            }
            // Reset the text field editing visuals directly, WITHOUT reloading the
            // cell.  reloadData here would trigger viewFor while selectedRowIndexes
            // still includes the OLD row (selection hasn't updated yet), causing a
            // brief blue flash before tableViewSelectionDidChange corrects it.
            self.editingCell = nil
            self.editingTextField = nil
            tf.isEditable = false
            tf.isSelectable = false
        }

        private func _findTableView(_ from: NSView) -> NSTableView? {
            var v: NSView? = from.superview
            while let s = v?.superview {
                if let tv = s as? NSTableView { return tv }
                v = s
            }
            return nil
        }

        /// Find the NSTableView this coordinator manages by walking up from
        /// the footer view (which is always a subview of the same scroll view).
        private func findTableView() -> NSTableView? {
            guard let scrollView = footerView.superview as? NSScrollView else { return nil }
            // documentView of NSScrollView is the NSTableView.
            return scrollView.documentView as? NSTableView
        }

        func savePending() {
            flushPendingEdits()
            // After flush, pendingEdits = 0 — notify parent so save button hides.
            parent.onPendingCountChanged?(0)
            parent.onSave?()
        }

        /// Discard all pending edits and reload cells with original values.
        func revertPending() {
            discardPendingEdits()
            // After discard, pendingEdits = 0 — notify parent.
            parent.onPendingCountChanged?(0)
            // Find the table view and reload all visible cells so they show
            // original values from parent.rows.
            if let tv = findTableView() {
                tv.reloadData()
            }
        }

        /// Notify parent that pending-edit count changed (for save-button visibility).
        private func notifyPendingCount() {
            parent.onPendingCountChanged?(pendingEdits.count)
            updateFooter()
        }

        /// Flush all pending edits to the database (Enter).
        private func flushPendingEdits() {
            guard !pendingEdits.isEmpty else { return }
            for edit in pendingEdits {
                parent.onCommitEdit?(edit.row, edit.col, edit.newValue)
            }
            pendingEdits.removeAll()
            notifyPendingCount()
        }

        /// Discard all pending edits (Escape / row selection).
        private func discardPendingEdits() {
            pendingEdits.removeAll()
            notifyPendingCount()
        }

        /// Returns the display value for a cell: if there is a pending (unflushed)
        /// edit for (row, col), returns its typed value so the user sees what they
        /// entered.  Otherwise falls back to `displayCellValue(original)`.
        /// Uses `last` because the same cell may be edited multiple times before
        /// flush; each end-editing appends to `pendingEdits`.
        private func pendingDisplayValue(for row: Int, col: Int, original: CellValue) -> String {
            if let pending = pendingEdits.last(where: { $0.row == row && $0.col == col }) {
                return pending.newValue
            }
            return displayCellValue(original)
        }

        @objc func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape — discard all pending edits
                discardPendingEdits()
                editingCell = nil
                editingTextField = nil
                if let tableView = control.window?.contentView?.subviews.compactMap({ $0 as? NSTableView }).first
                    ?? control.window?.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSTableView {
                    tableView.reloadData()
                }
                control.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter — commit current cell to pending, then flush all
                control.window?.makeFirstResponder(nil)
                flushPendingEdits()
                if let tableView = control.window?.contentView?.subviews.compactMap({ $0 as? NSTableView }).first
                    ?? control.window?.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSTableView {
                    tableView.reloadData()
                }
                return true
            }
            return false
        }

        // --- Delegate: Row View (hover + selection style) ---

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let view = HoverRowView()
            view.coordinator = self
            view.row = row
            return view
        }

        // --- Delegate: Selection ---

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            // Save current edit to pending before allowing row selection,
            // so the value isn't lost when the text field resigns via reloadData.
            if editingCell != nil {
                tableView.window?.makeFirstResponder(nil)
            }
            return true
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let selected = Set(tableView.selectedRowIndexes.filter { $0 < parent.rows.count })
            parent.onSelectedRowsChanged?(selected)
            // viewFor only fires for newly visible cells; existing on-screen cells
            // keep their previous drawsBackground/backgroundColor. Re-tint them so
            // the previously selected cell drops its blue background.
            refreshVisibleCellHighlights(tableView: tableView)
        }

        private func refreshVisibleCellHighlights(tableView: NSTableView) {
            for row in 0..<tableView.numberOfRows {
                for col in 0..<tableView.numberOfColumns {
                    // Skip the row-number column (col 0) — it never tints.
                    guard col > 0,
                          let cell = tableView.view(
                              atColumn: col, row: row, makeIfNecessary: false
                          ) as? DataCell else { continue }
                    let dataColIdx = col - 1
                    let isActive = Self.isActiveCell(
                        row: row,
                        dataColIdx: dataColIdx,
                        tableView: tableView
                    )
                    let isEditing = editingCell?.row == row
                        && editingCell?.col == dataColIdx
                    let hasPending = pendingEdits.contains(where: { $0.row == row && $0.col == dataColIdx })
                    Self.applyCellHighlight(to: cell, isActiveCell: isActive, isEditing: isEditing, hasPending: hasPending)
                }
            }
        }

        /// Returns true if this cell (row, dataColIdx) is part of the active
        /// selection — i.e. its row is selected AND its column matches the
        /// last-clicked column. clickedColumn - 1 is the data-column index.
        /// If clickedColumn is invalid (header click, no click yet), no cell is active.
        static func isActiveCell(row: Int, dataColIdx: Int, tableView: NSTableView) -> Bool {
            guard tableView.selectedRowIndexes.contains(row) else { return false }
            let clickedCol = tableView.clickedColumn
            return clickedCol > 0 && (clickedCol - 1) == dataColIdx
        }

        /// Color for cells that have a pending (unflushed) edit.
        /// Warm accent so the user can see which cells they modified before saving.
        private static let pendingEditColor =
            NSColor.systemOrange.withAlphaComponent(0.12)

        /// Single source of truth for cell background tint. Called from `viewFor`
        /// when a cell is (re)created AND from `tableViewSelectionDidChange` to
        /// re-tint existing on-screen cells. Extracted so this logic is unit-testable.
        /// Priority: isEditing > isActiveCell > hasPending > default (no bg).
        fileprivate static func applyCellHighlight(
            to cell: DataCell,
            isActiveCell: Bool,
            isEditing: Bool,
            hasPending: Bool = false
        ) {
            guard let tf = cell.textField else { return }
            if isEditing {
                tf.drawsBackground = true
                tf.backgroundColor = NSColor.controlBackgroundColor
                return
            }
            if isActiveCell {
                tf.drawsBackground = true
                tf.backgroundColor = NSColor.alternateSelectedControlColor
                return
            }
            if hasPending {
                tf.drawsBackground = true
                tf.backgroundColor = Self.pendingEditColor
                return
            }
            tf.drawsBackground = false
        }

        // --- Delegate: Hover ---

        func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
            // HoverRowView handles its own tracking
        }

        // --- Delegate: Context Menu ---

        func tableView(_ tableView: NSTableView, menuForRows rows: IndexSet) -> NSMenu? {
            let rowSet = Set(rows.filter { $0 < parent.rows.count })
            let menu = NSMenu()
            menu.autoenablesItems = true

            if rowSet.count == 1, let row = rowSet.first {
                // Single row menu
                menu.addItem(withTitle: "Copy Cell", action: #selector(copyCellAction(_:)), keyEquivalent: "c")
                menu.addItem(withTitle: "Copy Row", action: #selector(copyRowAction(_:)), keyEquivalent: "")
                menu.addItem(withTitle: "Copy as CSV", action: #selector(copyRowAsCSVAction(_:)), keyEquivalent: "")
                menu.addItem(NSMenuItem.separator())

                if parent.tableName != nil {
                    menu.addItem(withTitle: "Delete Row", action: #selector(deleteRowAction(_:)), keyEquivalent: "")
                        .target = self
                }
            } else if rowSet.count > 1 {
                // Multi-row menu
                menu.addItem(withTitle: "Copy Selected (\(rowSet.count) rows)", action: #selector(copySelectedAction(_:)), keyEquivalent: "")
                menu.addItem(withTitle: "Copy as CSV", action: #selector(copySelectedCSVAction(_:)), keyEquivalent: "")
                menu.addItem(NSMenuItem.separator())

                if parent.tableName != nil {
                    menu.addItem(withTitle: "Delete Selected (\(rowSet.count) rows)", action: #selector(deleteSelectedAction(_:)), keyEquivalent: "")
                        .target = self
                }
            }

            // Tag menu items with the selected rows
            for item in menu.items {
                item.representedObject = rowSet
                item.target = self
            }

            return menu
        }

        @objc func tableView(_ tableView: NSTableView, menuForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSMenu? {
            let rows: IndexSet
            if tableView.selectedRowIndexes.contains(row) {
                rows = tableView.selectedRowIndexes
            } else {
                rows = IndexSet(integer: row)
            }
            return self.tableView(tableView, menuForRows: rows)
        }

        // --- Context Menu Actions ---

        @objc private func copyCellAction(_ sender: NSMenuItem) {
            guard let rowSet = sender.representedObject as? Set<Int>,
                  let row = rowSet.first else { return }
            // The column is not available in the menu context; just copy the first column value for now
            parent.onDataTableAction?(.copyCell(row: row, col: 0))
        }

        @objc private func copyRowAction(_ sender: NSMenuItem) {
            guard let rowSet = sender.representedObject as? Set<Int>,
                  let row = rowSet.first else { return }
            parent.onDataTableAction?(.copyRow(row: row))
        }

        @objc private func copyRowAsCSVAction(_ sender: NSMenuItem) {
            guard let rowSet = sender.representedObject as? Set<Int> else { return }
            parent.onDataTableAction?(.copySelectedAsCSV(rows: rowSet))
        }

        @objc private func copySelectedAction(_ sender: NSMenuItem) {
            guard let rowSet = sender.representedObject as? Set<Int> else { return }
            parent.onDataTableAction?(.copySelected(rows: rowSet))
        }

        @objc private func copySelectedCSVAction(_ sender: NSMenuItem) {
            guard let rowSet = sender.representedObject as? Set<Int> else { return }
            parent.onDataTableAction?(.copySelectedAsCSV(rows: rowSet))
        }

        @objc private func deleteRowAction(_ sender: NSMenuItem) {
            guard let rowSet = sender.representedObject as? Set<Int>,
                  let table = parent.tableName else { return }
            parent.onDataTableAction?(.deleteRows(rows: rowSet, table: table))
        }

        @objc private func deleteSelectedAction(_ sender: NSMenuItem) {
            guard let rowSet = sender.representedObject as? Set<Int>,
                  let table = parent.tableName else { return }
            parent.onDataTableAction?(.deleteRows(rows: rowSet, table: table))
        }

        // --- Double-click to edit (inline, uses CenteredTextFieldCell) ---

        @objc func doubleClickRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            let col = sender.clickedColumn - 1
            guard row >= 0, row < parent.rows.count,
                  col >= 0, col < parent.columns.count,
                  parent.tableName != nil else {
                if row >= 0 && row < parent.rows.count && col >= 0 && col < parent.rows[row].count {
                    let value = displayCellValue(parent.rows[row][col])
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                return
            }

            // Commit any pending edit first (sequential: save A before editing B)
            if editingCell != nil {
                sender.window?.makeFirstResponder(nil)
            }

            // Get-or-create the cell view (makeIfNecessary: true handles the case
            // where the commit's reloadData invalidated the cached view).
            if let cellView = sender.view(atColumn: sender.clickedColumn, row: row, makeIfNecessary: true) as? DataCell,
               let tf = cellView.textField {
                editingCell = (row, col)
                editingTextField = tf
                tf.isEditable = true
                tf.isSelectable = true
                tf.drawsBackground = true
                tf.backgroundColor = NSColor.controlBackgroundColor
                tf.delegate = self
                tf.window?.makeFirstResponder(tf)
                tf.currentEditor()?.selectAll(nil)
            }
        }
    }
}

// MARK: - Hover Row View

fileprivate class HoverRowView: NSTableRowView {
    weak var coordinator: DataTable.Coordinator?
    var row: Int = 0
    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateTrackingArea()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        if let ta = trackingArea {
            addTrackingArea(ta)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        coordinator?.hoveredRow = row
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        coordinator?.hoveredRow = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if coordinator?.hoveredRow == row {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.10).setFill()
            dirtyRect.fill()
        }
    }
}

// MARK: - Vertically Centered Text Field Cell

fileprivate class CenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let stringHeight = self.attributedStringValue.size().height
        var titleRect = super.titleRect(forBounds: rect)
        let offset = floor((rect.height - stringHeight) / 2)
        titleRect.origin.y += offset
        titleRect.size.height -= offset
        return titleRect
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
}

// MARK: - Data Cell

fileprivate class DataCell: NSTableCellView {
    weak var parentCoordinator: DataTable.Coordinator?
    var row: Int?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 26))

        let textField = NSTextField(frame: .zero)
        let cell = CenteredTextFieldCell()
        cell.isBordered = false
        cell.isEditable = false
        cell.isSelectable = false
        cell.drawsBackground = false
        cell.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.lineBreakMode = .byTruncatingTail
        cell.truncatesLastVisibleLine = true
        cell.usesSingleLineMode = true
        textField.cell = cell
        textField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        self.textField = textField
        self.identifier = identifier
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Summary Footer View

fileprivate class SummaryFooterView: NSView {
    private var buttons: [NSButton] = []
    private var saveButton: NSButton?
    var onToggleColumn: ((Int) -> Void)?
    var onSave: (() -> Void)?
    var activeColumns: Set<Int> = []
    private var colCount: Int = 0
    private var pendingCount: Int = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(summary: [String], columns: [ColumnInfo], activeColumns: Set<Int>,
                pendingCount: Int = 0) {
        self.activeColumns = activeColumns
        self.colCount = columns.count
        self.pendingCount = pendingCount

        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        saveButton?.removeFromSuperview()
        saveButton = nil

        guard summary.count >= columns.count else { return }

        let rowLabel = NSButton(title: summary.first ?? "", target: nil, action: nil)
        rowLabel.isBordered = false
        rowLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        rowLabel.contentTintColor = NSColor.secondaryLabelColor
        rowLabel.alignment = .right
        rowLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowLabel)
        buttons.append(rowLabel)

        for i in 0..<columns.count {
            let text = i < summary.count ? summary[i] : ""
            let isEmpty = text.isEmpty
            let btn = NSButton(title: text, target: self, action: #selector(didTapColumn(_:)))
            btn.isBordered = false
            btn.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
            btn.alignment = .left
            btn.lineBreakMode = .byTruncatingTail
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.tag = i

            let isActive = activeColumns.contains(i)
            if isEmpty {
                btn.contentTintColor = NSColor.clear
                btn.isEnabled = false
            } else if isActive {
                btn.contentTintColor = NSColor.controlAccentColor
                btn.attributedTitle = NSAttributedString(string: text, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.controlAccentColor,
                ])
            } else {
                btn.contentTintColor = NSColor.tertiaryLabelColor
                btn.attributedTitle = NSAttributedString(string: text, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ])
            }

            if !isEmpty {
                btn.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didTapColumn(_:))))
            }

            addSubview(btn)
            buttons.append(btn)
        }

        // Save button — only visible when there are pending edits.
        if pendingCount > 0 {
            let btn = NSButton(title: "Save (\(pendingCount))", target: self, action: #selector(didTapSave))
            btn.isBordered = true
            btn.bezelStyle = .roundedDisclosure
            btn.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            btn.contentTintColor = NSColor.controlAccentColor
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.toolTip = "Save all pending edits to the database"
            addSubview(btn)
            saveButton = btn
        }

        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    @objc private func didTapColumn(_ sender: Any?) {
        guard let button = sender as? NSButton else { return }
        onToggleColumn?(button.tag)
    }

    @objc private func didTapSave() {
        onSave?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 0, y: bounds.height - 0.5))
        line.line(to: NSPoint(x: bounds.width, y: bounds.height - 0.5))
        line.lineWidth = 1
        NSColor.separatorColor.setStroke()
        line.stroke()
    }

    override func layout() {
        super.layout()
        guard !buttons.isEmpty else { return }

        // Reserve space for the save button on the right edge.
        let saveWidth: CGFloat = {
            guard let btn = saveButton else { return 0 }
            btn.sizeToFit()
            let w = btn.frame.width + 12
            btn.frame = NSRect(x: bounds.width - w, y: 0, width: w, height: bounds.height)
            return w + 4
        }()

        let rowNumWidth: CGFloat = 36
        let dataWidth = max(0, bounds.width - rowNumWidth - 8 - saveWidth)
        let colCount = max(1, buttons.count - 1)
        let eachWidth = max(60, min(150, dataWidth / CGFloat(colCount)))

        var x: CGFloat = 0
        for (i, btn) in buttons.enumerated() {
            if i == 0 {
                btn.frame = NSRect(x: x, y: 0, width: rowNumWidth, height: bounds.height)
                x += rowNumWidth
            } else {
                let idx = i - 1
                let w: CGFloat
                if colCount <= 5 {
                    w = eachWidth
                } else {
                    w = max(60, min(150, (dataWidth - CGFloat(colCount - 1) * 4) / CGFloat(colCount)))
                }
                btn.frame = NSRect(x: x, y: 0, width: w, height: bounds.height)
                x += w + 4
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

// MARK: - Identifier

private extension NSUserInterfaceItemIdentifier {
    static let rowNumber = NSUserInterfaceItemIdentifier("rowNumber")
}

// MARK: - Cell value rendering

func displayCellValue(_ cv: CellValue) -> String {
    switch cv {
    case .null:         return "NULL"
    case .int(let v):   return "\(v)"
    case .float(let v): return "\(v)"
    case .text(let v):  return v
    case .blob(let v):  return "<blob \(v.count)B>"
    }
}

func cellForegroundColor(_ cv: CellValue) -> NSColor {
    switch cv {
    case .null:         return NSColor.tertiaryLabelColor
    case .int, .float:  return NSColor.controlAccentColor
    case .text:         return NSColor.labelColor
    case .blob:         return NSColor.secondaryLabelColor
    }
}

func cellAlignment(_ cv: CellValue) -> NSTextAlignment {
    switch cv {
    case .int, .float:  return .right
    case .null:         return .center
    default:            return .left
    }
}
