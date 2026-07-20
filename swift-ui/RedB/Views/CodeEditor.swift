import SwiftUI
import AppKit

// MARK: - SwiftUI Wrapper

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    var onSuggest: ((String) -> [String])?
    var onTab: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?

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

        private var previousLength = 0

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let isDelete = tv.string.count < previousLength
            previousLength = tv.string.count
            parent.text = tv.string
            parent.highlight(tv)
            if !isDelete, let onSuggest = parent.onSuggest {
                let partial = currentWord(in: tv.string, cursor: tv.selectedRange().location)
                if let word = partial, word.count >= 1 {
                    _ = onSuggest(word)
                }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if parent.onTab != nil { parent.onTab!(); return true }
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if parent.onArrowUp != nil { parent.onArrowUp!(); return true }
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if parent.onArrowDown != nil { parent.onArrowDown!(); return true }
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if parent.onEnter != nil { parent.onEnter!(); return true }
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if parent.onEscape != nil { parent.onEscape!(); return true }
            }
            return false
        }

        /// Extract the word being typed at cursor position.
        private func currentWord(in text: String, cursor: Int) -> String? {
            let ns = text as NSString
            guard cursor > 0, cursor <= ns.length else { return nil }
            var start = cursor - 1
            while start >= 0 {
                let ch = ns.character(at: start)
                if (ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A) || (ch >= 0x30 && ch <= 0x39) || ch == 0x5F {
                    start -= 1
                } else { break }
            }
            start += 1
            guard start < cursor else { return nil }
            return ns.substring(with: NSRange(location: start, length: cursor - start))
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
