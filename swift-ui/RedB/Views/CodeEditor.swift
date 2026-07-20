import SwiftUI
import AppKit

// MARK: - SwiftUI Wrapper

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    var tableSuggestions: ((String) -> [String])?
    var columnSuggestions: ((String) -> [String])?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let tv = NSTextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.font = font
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.drawsBackground = false
        tv.isRichText = false
        tv.usesFontPanel = false
        tv.allowsUndo = true
        tv.delegate = context.coordinator

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            highlight(tv)
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.highlight(tv)
            triggerCompletionIfNeeded(tv)
        }

        private func triggerCompletionIfNeeded(_ tv: NSTextView) {
            let sel = tv.selectedRange()
            guard sel.length == 0, sel.location > 0 else { return }
            let ns = tv.string as NSString
            guard sel.location <= ns.length else { return }

            let partial = currentWordPrefix(in: tv.string, cursor: sel.location)
            guard let word = partial, !word.isEmpty else { return }

            // Check if we have anything to suggest
            let allFunctions = mySQLFunctions.union(mariadbFunctions).union(pgsqlFunctions)
            let funcs = allFunctions.filter { $0.lowercased().hasPrefix(word.lowercased()) }
            var tables: [String] = []
            if isTableNameContext(in: tv.string, cursor: sel.location), let t = parent.tableSuggestions {
                tables = t(word)
            }
            guard !funcs.isEmpty || !tables.isEmpty else { return }

            tv.complete(nil)
        }

        /// Extract the partial word at cursor position.
        private func currentWordPrefix(in text: String, cursor: Int) -> String? {
            let ns = text as NSString
            guard cursor > 0, cursor <= ns.length else { return nil }
            var start = cursor - 1
            while start >= 0 {
                let ch = ns.character(at: start)
                if ch.isASCIIWordCharacter { start -= 1 } else { break }
            }
            start += 1
            guard start < cursor else { return nil }
            return ns.substring(with: NSRange(location: start, length: cursor - start))
        }

        /// Check if cursor follows a keyword that expects table names.
        private func isColumnContext(in text: String, cursor: Int) -> Bool {
        let ns = text as NSString
        let prefix = ns.substring(to: min(cursor, ns.length))
        let words = prefix.split { $0.isWhitespace || $0 == "\n" || $0 == "," || $0 == "(" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard words.count >= 2 else { return false }
        let contextKeywords: Set<String> = [
            "WHERE", "AND", "OR", "ORDER BY", "GROUP BY", "HAVING",
            "ON", "SET", "SELECT", "BETWEEN", "IN", "NOT IN",
            "IS NULL", "IS NOT NULL", "LIKE",
        ]
        let prev = words[words.count - 2].uppercased()
        for kw in contextKeywords {
            if prev.hasSuffix(kw) || prev == kw { return true }
        }
        // Also suggest columns after a comma in SELECT clause
        if prev == "," && words.count >= 3 {
            let prev2 = words[words.count - 3].uppercased()
            if prev2 == "SELECT" || prev2 == "," { return true }
        }
        return false
    }

    private func isTableNameContext(in text: String, cursor: Int) -> Bool {
            let keywords = Set(["FROM", "JOIN", "INTO", "UPDATE", "TABLE", "ON"])
            let ns = text as NSString
            guard cursor > 0 else { return false }
            let prefix = ns.substring(to: min(cursor, ns.length))
            let words = prefix.split { $0.isWhitespace || $0 == "\n" || $0 == "," }
            guard words.count >= 2 else { return false }
            let prev = String(words[words.count - 2]).uppercased()
            return keywords.contains(prev)
        }

        // MARK: - NSTextViewDelegate completions

        // Cancel completion popup on backspace so it deletes characters instead
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if replacementString == nil || replacementString?.isEmpty == true {
                textView.complete(nil)
            }
            return true
        }

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let context = analyzeSQLContext(textView.string, cursor: charRange.location)
            let partial = (textView.string as NSString).substring(with: charRange)

            let result = sqlSuggestions(
                for: context,
                partial: partial,
                tableFetcher: { prefix in
                    parent.tableSuggestions?(prefix) ?? []
                },
                columnFetcher: { prefix in
                    parent.columnSuggestions?(prefix) ?? []
                }
            )

            return result.isEmpty ? words : result
        }
    }

    private func highlight(_ tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: full)

        let text = storage.string as NSString

        // Numbers
        let numRegex = try! NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#)
        numRegex.enumerateMatches(in: tv.string, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: r)
        }

        // Single-quoted strings
        let strRegex = try! NSRegularExpression(pattern: #"'[^']*'"#)
        strRegex.enumerateMatches(in: tv.string, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: r)
        }

        // Double-quoted identifiers
        let dqRegex = try! NSRegularExpression(pattern: #""[^"]*""#)
        dqRegex.enumerateMatches(in: tv.string, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: r)
        }

        // Backtick identifiers (MySQL)
        let btRegex = try! NSRegularExpression(pattern: "`[^`]*`")
        btRegex.enumerateMatches(in: tv.string, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: r)
        }

        // Comments: -- to end of line
        let lineCommentRegex = try! NSRegularExpression(pattern: "--[^\n]*")
        lineCommentRegex.enumerateMatches(in: tv.string, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: r)
        }

        // Keywords
        let wordRegex = try! NSRegularExpression(pattern: #"\b[A-Za-z_]\w*\b"#)
        wordRegex.enumerateMatches(in: tv.string, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            let word = text.substring(with: r)
            if sqlKeywords.contains(word.uppercased()) {
                storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: r)
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold), range: r)
            }
        }

        storage.endEditing()
    }
}

// MARK: - SQL Formatter

func formatSQL(_ sql: String) -> String {
    let keywords = ["SELECT", "FROM", "WHERE", "AND", "OR", "ORDER BY", "GROUP BY",
                    "HAVING", "LIMIT", "OFFSET", "INSERT INTO", "VALUES",
                    "UPDATE", "SET", "DELETE FROM", "CREATE TABLE", "ALTER TABLE",
                    "DROP TABLE", "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN",
                    "OUTER JOIN", "ON", "UNION", "UNION ALL", "EXISTS", "NOT EXISTS",
                    "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN", "COMMIT",
                    "ROLLBACK", "WITH", "AS"]

    var result = sql
    for kw in ["SELECT", "FROM", "WHERE", "ORDER BY", "GROUP BY", "HAVING",
               "LIMIT", "OFFSET", "INSERT INTO", "UPDATE", "SET", "DELETE FROM",
               "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "UNION", "UNION ALL",
               "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "OUTER JOIN",
               "ON", "WITH"] {
        let pattern = "(?i)\\b\(kw)\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsrange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsrange).reversed()
            for m in matches {
                guard let range = Range(m.range, in: result) else { continue }
                let word = result[range]
                let isFirst = range.lowerBound == result.startIndex
                if !isFirst {
                    let before = result[result.index(before: range.lowerBound)]
                    if before != "\n" && before != " " {
                        result.insert(contentsOf: "\n", at: range.lowerBound)
                    }
                }
            }
        }
    }

    return result
}

// MARK: - Unicode helper

private extension UInt16 {
    /// ASCII letters, digits, underscore — valid inside a SQL identifier / function name.
    var isASCIIWordCharacter: Bool {
        (self >= 0x41 && self <= 0x5A) ||  // A-Z
        (self >= 0x61 && self <= 0x7A) ||  // a-z
        (self >= 0x30 && self <= 0x39) ||  // 0-9
        self == 0x5F                       // _
    }
}
