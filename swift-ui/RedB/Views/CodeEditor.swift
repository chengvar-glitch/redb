import SwiftUI
import AppKit

private let sqlKeywords: Set<String> = [
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
]

private let pgsqlFunctions: Set<String> = [
    "NOW", "CURRENT_DATE", "CURRENT_TIME", "CURRENT_TIMESTAMP",
    "DATE_PART", "DATE_TRUNC", "EXTRACT", "AGE", "NOW",
    "TO_CHAR", "TO_DATE", "TO_NUMBER", "TO_TIMESTAMP",
    "MAKE_DATE", "MAKE_TIME", "MAKE_TIMESTAMP", "MAKE_INTERVAL",
    "GREATEST", "LEAST", "COALESCE", "NULLIF",
    "ARRAY_AGG", "ARRAY_APPEND", "ARRAY_CAT", "ARRAY_DIMS",
    "ARRAY_FILL", "ARRAY_LENGTH", "ARRAY_LOWER", "ARRAY_POSITION",
    "ARRAY_PREPEND", "ARRAY_REMOVE", "ARRAY_REPLACE", "ARRAY_TO_STRING",
    "ARRAY_UPPER", "CARDINALITY", "STRING_AGG", "UNNEST",
    "GENERATE_SERIES", "GENERATE_SUBSCRIPTS",
    "CONCAT", "CONCAT_WS", "FORMAT", "INITCAP", "LEFT", "RIGHT",
    "LENGTH", "LOWER", "LPAD", "LTRIM", "REGEXP_MATCH", "REGEXP_REPLACE",
    "REGEXP_SPLIT_TO_ARRAY", "REGEXP_SPLIT_TO_TABLE", "REPEAT", "REPLACE",
    "REVERSE", "RPAD", "RTRIM", "SPLIT_PART", "STRPOS", "SUBSTR", "SUBSTRING",
    "TRANSLATE", "TRIM", "UPPER",
    "ABS", "CEIL", "CEILING", "DIV", "EXP", "FLOOR", "LN", "LOG",
    "MOD", "POWER", "RANDOM", "ROUND", "SETSEED", "SIGN", "SQRT",
    "TRUNC", "WIDTH_BUCKET",
    "COUNT", "SUM", "AVG", "MIN", "MAX", "STDDEV", "VARIANCE",
    "ROW_NUMBER", "RANK", "DENSE_RANK", "NTILE", "LAG", "LEAD",
    "FIRST_VALUE", "LAST_VALUE", "NTH_VALUE",
    "CAST", "CONVERT", "BOOL_AND", "BOOL_OR", "EVERY",
]

private let mariadbFunctions: Set<String> = [
    "NOW", "CURDATE", "CURTIME", "UTC_DATE", "UTC_TIME", "UTC_TIMESTAMP",
    "DATE", "TIME", "YEAR", "MONTH", "DAY", "DAYNAME", "DAYOFMONTH",
    "DAYOFWEEK", "DAYOFYEAR", "HOUR", "MINUTE", "SECOND", "MICROSECOND",
    "DATE_ADD", "DATE_SUB", "DATEDIFF", "DATE_FORMAT", "STR_TO_DATE",
    "UNIX_TIMESTAMP", "FROM_UNIXTIME", "TIMESTAMPDIFF", "TIMESTAMPADD",
    "LAST_DAY", "MAKEDATE", "MAKETIME", "PERIOD_ADD", "PERIOD_DIFF",
    "QUARTER", "SEC_TO_TIME", "TIME_TO_SEC", "TIMEDIFF", "TO_DAYS",
    "CONCAT", "CONCAT_WS", "GROUP_CONCAT", "SUBSTRING", "SUBSTRING_INDEX",
    "TRIM", "LTRIM", "RTRIM", "UPPER", "LOWER", "LENGTH", "CHAR_LENGTH",
    "CHARACTER_LENGTH", "REPLACE", "LOCATE", "INSTR", "POSITION",
    "LEFT", "RIGHT", "REPEAT", "REVERSE", "SPACE", "LPAD", "RPAD",
    "INSERT", "ELT", "FIELD", "FIND_IN_SET", "FORMAT", "HEX", "UNHEX",
    "IFNULL", "COALESCE", "NULLIF", "IF", "CASE",
    "ABS", "CEIL", "CEILING", "FLOOR", "ROUND", "TRUNCATE", "MOD",
    "POW", "POWER", "SQRT", "EXP", "LOG", "LOG10", "LOG2", "RAND",
    "SIGN", "PI", "DEGREES", "RADIANS", "SIN", "COS", "TAN", "ACOS",
    "ASIN", "ATAN", "ATAN2", "COT",
    "COUNT", "SUM", "AVG", "MIN", "MAX", "GROUP_CONCAT", "STD", "STDDEV",
    "VARIANCE", "VAR_POP", "VAR_SAMP", "BIT_AND", "BIT_OR", "BIT_XOR",
    "ROW_NUMBER", "RANK", "DENSE_RANK", "NTILE",
    "CAST", "CONVERT", "JSON_EXTRACT", "JSON_UNQUOTE", "JSON_SET",
    "JSON_REPLACE", "JSON_REMOVE", "JSON_KEYS", "JSON_CONTAINS",
]

private let mySQLFunctions: Set<String> = [
    "NOW", "CURDATE", "CURTIME", "DATE", "TIME", "YEAR", "MONTH", "DAY",
    "HOUR", "MINUTE", "SECOND", "DATE_FORMAT", "STR_TO_DATE", "UNIX_TIMESTAMP",
    "FROM_UNIXTIME", "TIMESTAMPDIFF", "TIMESTAMPADD", "CONCAT", "CONCAT_WS",
    "GROUP_CONCAT", "SUBSTRING", "TRIM", "LTRIM", "RTRIM", "UPPER", "LOWER",
    "LENGTH", "CHAR_LENGTH", "REPLACE", "LOCATE", "INSTR", "LEFT", "RIGHT",
    "REPEAT", "REVERSE", "SPACE", "FORMAT", "IFNULL", "COALESCE", "NULLIF",
    "IF", "CASE", "CAST", "CONVERT", "JSON_EXTRACT", "JSON_UNQUOTE",
    "JSON_SET", "JSON_REPLACE", "JSON_REMOVE", "ROW_NUMBER", "RANK",
    "DENSE_RANK", "LEAD", "LAG", "FIRST_VALUE", "LAST_VALUE",
    "ABS", "CEIL", "FLOOR", "ROUND", "TRUNCATE", "MOD", "POW", "POWER",
    "SQRT", "EXP", "LOG", "LOG10", "RAND", "SIGN",
]

// MARK: - SwiftUI Wrapper

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    var tableSuggestions: ((String) -> [String])?

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

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let partial = (textView.string as NSString).substring(with: charRange).lowercased()

            var result: [String] = []

            // Functions (combined from all DB types)
            let allFunctions = mySQLFunctions.union(mariadbFunctions).union(pgsqlFunctions)
            for f in allFunctions where f.lowercased().hasPrefix(partial) {
                result.append(f + "()")
            }

            // SQL clause keywords
            let clauses = ["WHERE", "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "OFFSET",
                           "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "OUTER JOIN",
                           "ON", "AS", "AND", "OR", "IN", "NOT IN", "BETWEEN", "LIKE",
                           "IS NULL", "IS NOT NULL", "UNION", "UNION ALL", "EXCEPT", "INTERSECT",
                           "WITH", "RECURSIVE", "RETURNING", "FOR UPDATE", "FOR SHARE"]
            for c in clauses where c.lowercased().hasPrefix(partial) {
                result.append(c)
            }

            // Table names (contextual)
            if isTableNameContext(in: textView.string, cursor: charRange.location),
               let suggester = parent.tableSuggestions {
                let tables = suggester(String(partial))
                result.append(contentsOf: tables)
            }

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
