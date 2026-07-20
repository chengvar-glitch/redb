import SwiftUI
import AppKit

// MARK: - SwiftUI Wrapper

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

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
        }
    }

    private func highlight(_ tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: full)

        let text = storage.string as NSString

        // Keywords
        let keywords = Set([
            "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL",
            "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE",
            "TABLE", "DROP", "ALTER", "ADD", "COLUMN", "INDEX", "PRIMARY",
            "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "UNIQUE",
            "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "ORDER",
            "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT",
            "CASE", "WHEN", "THEN", "ELSE", "END", "EXISTS", "BETWEEN", "LIKE",
            "COUNT", "SUM", "AVG", "MIN", "MAX", "CAST", "COALESCE", "NULLIF",
            "TRUE", "FALSE", "IF", "REPLACE", "TRUNCATE", "DESCRIBE", "SHOW",
            "USE", "DATABASE", "SCHEMA", "GRANT", "REVOKE", "COMMIT", "ROLLBACK",
            "BEGIN", "TRANSACTION", "EXPLAIN", "ANALYZE", "WITH", "RECURSIVE",
            "ASC", "DESC", "CROSS", "NATURAL", "USING", "ANY", "SOME",
        ])

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

        // Double-quoted identifiers (not for MySQL)
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
            if keywords.contains(word.uppercased()) {
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
    // Add newline before major keywords
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
