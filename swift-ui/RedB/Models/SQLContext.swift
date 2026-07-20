import Foundation

// MARK: - SQL Function Sets

let sqlKeywords: Set<String> = [
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

let mySQLFunctions: Set<String> = [
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

let pgsqlFunctions: Set<String> = [
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

let mariadbFunctions: Set<String> = [
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

let allSQLFunctions: Set<String> = mySQLFunctions.union(pgsqlFunctions).union(mariadbFunctions)

// MARK: - SQL Tokenizer & Context Tracker

enum SQLCompletionType {
    case statement     // SELECT, INSERT, UPDATE, DELETE, etc.
    case keyword       // WHERE, ORDER BY, GROUP BY, etc.
    case tableName     // table names after FROM, JOIN, INTO, etc.
    case columnName    // column names after SELECT, WHERE, ORDER BY, etc.
    case function      // SQL functions like COUNT, SUM, NOW, etc.
    case value         // values after IN, =, etc.
    case alias         // alias suggestion
}

struct SQLContext {
    let type: SQLCompletionType
    let partial: String
}

func analyzeSQLContext(_ text: String, cursor: Int) -> SQLContext {
    let ns = text as NSString
    let textBefore = ns.substring(to: min(cursor, ns.length))
    let tokens = tokenize(textBefore)
    let partial = extractCurrentWord(textBefore) ?? ""

    guard let last = tokens.last else {
        return SQLContext(type: .statement, partial: partial)
    }

    let upper = last.uppercased()

    // Statement keywords that should start a new statement
    let statementStarters: Set<String> = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
        "TRUNCATE", "WITH", "EXPLAIN", "DESCRIBE", "SHOW", "USE", "CALL"
    ]

    // Keywords that expect a table name next
    let tableExpecters: Set<String> = [
        "FROM", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "OUTER JOIN",
        "INTO", "TABLE", "UPDATE", "INTO",
    ]

    // Keywords that expect column name(s) next
    let columnExpecters: Set<String> = [
        "SELECT", "WHERE", "ORDER BY", "GROUP BY", "HAVING",
        "ON", "SET", "AND", "OR",
    ]

    // Keywords in table-expecting context
    for keyword in tableExpecters {
        if upper.hasSuffix(keyword) || hasLastWord(textBefore, keyword) {
            return SQLContext(type: .tableName, partial: partial)
        }
    }

    // Keywords in column-expecting context
    for keyword in columnExpecters {
        if upper.hasSuffix(keyword) || hasLastWord(textBefore, keyword) {
            return SQLContext(type: .columnName, partial: partial)
        }
    }

    // After IN, NOT IN, =, LIKE → suggest values or subqueries (skip for now)
    let valueOperators: Set<String> = ["IN", "=", "!=", "<>", "<", ">", "<=", ">=", "LIKE"]
    if valueOperators.contains(upper) || valueOperators.contains(where: { upper.hasSuffix($0) }) {
        return SQLContext(type: .value, partial: partial)
    }

    // If the last word looks like a function name (e.g., COUNT) → continue suggesting functions
    if upper.hasSuffix("(") {
        return SQLContext(type: .function, partial: partial)
    }

    // Start of statement or after statement separator (;, or empty)
    if tokens.count <= 1 || [";", "\n"].contains(tokens[tokens.count - 2]) {
        return SQLContext(type: .statement, partial: partial)
    }

    // Default: suggest everything
    if statementStarters.contains(upper) {
        // Already have a statement starter, expect columns/expressions
        return SQLContext(type: .columnName, partial: partial)
    }

    return SQLContext(type: .columnName, partial: partial)
}

private func tokenize(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var inString = false
    var stringChar: Character = "'"

    for ch in text {
        if inString {
            current.append(ch)
            if ch == stringChar { inString = false }
            continue
        }
        if ch == "'" || ch == "\"" || ch == "`" {
            if !current.isEmpty { tokens.append(current) }
            current = String(ch)
            inString = true
            stringChar = ch
            continue
        }
        if ch.isWhitespace || ch == "," || ch == "(" || ch == ")" || ch == ";" || ch == "\n" {
            if !current.isEmpty { tokens.append(current); current = "" }
            if ch == "\n" { tokens.append("\n") }
            continue
        }
        current.append(ch)
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

private func extractCurrentWord(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let lastSpace = trimmed.lastIndex(of: " ") ?? trimmed.lastIndex(of: "\n") else {
        return trimmed.isEmpty ? nil : trimmed
    }
    let word = trimmed[trimmed.index(after: lastSpace)...]
    return word.isEmpty ? nil : String(word)
}

private func hasLastWord(_ text: String, _ keyword: String) -> Bool {
    let upper = text.uppercased()
    let kw = keyword.uppercased()
    // Find the LAST occurrence of the keyword
    guard let range = upper.range(of: kw, options: .backwards) else { return false }
    let after = upper[range.upperBound...].trimmingCharacters(in: .whitespaces)
    // After the keyword there should be only whitespace (user is typing the next word)
    // OR the cursor is right after the keyword (nothing after)
    return after.isEmpty || !after.contains(" ")
}

// MARK: - Suggestions Generator

func sqlSuggestions(for context: SQLContext, partial: String,
                   tableFetcher: (String) -> [String],
                   columnFetcher: (String) -> [String]) -> [String] {

    let p = partial.lowercased()
    var result: [String] = []

    switch context.type {
    case .statement:
        let stmts = ["SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
                     "TRUNCATE", "WITH", "EXPLAIN", "SHOW", "USE"]
        result = stmts.filter { $0.lowercased().hasPrefix(p) }

    case .keyword:
        let clauses = ["WHERE", "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "OFFSET",
                       "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN",
                       "ON", "AND", "OR", "IN", "NOT IN", "BETWEEN", "LIKE",
                       "IS NULL", "IS NOT NULL", "UNION", "UNION ALL"]
        result = clauses.filter { $0.lowercased().hasPrefix(p) }

    case .tableName:
        result = tableFetcher(partial)
        // Also generate alias suggestions
        for t in result {
            let alias = aliasFromTableName(t)
            if !alias.isEmpty { result.append("\(t) \(alias)") }
        }

    case .columnName:
        result = columnFetcher(partial)
        // Also suggest functions
        let allFuncs = mySQLFunctions.union(mariadbFunctions).union(pgsqlFunctions)
        for f in allFuncs where f.lowercased().hasPrefix(p) {
            result.append(f + "()")
        }

    case .function:
        let allFuncs = mySQLFunctions.union(mariadbFunctions).union(pgsqlFunctions)
        result = allFuncs.filter { $0.lowercased().hasPrefix(p) }.map { $0 + "()" }

    case .value:
        result = [] // Too broad to suggest

    case .alias:
        break
    }

    return result
}

private func aliasFromTableName(_ name: String) -> String {
    let upper = name.filter { $0.isUppercase }
    if !upper.isEmpty && name.count > 3 && upper.count > 1 {
        return upper.lowercased()
    }
    if name.contains("_") {
        return name.split(separator: "_").compactMap { $0.first }.map { String($0).lowercased() }.joined()
    }
    return String(name.prefix(2).lowercased())
}
