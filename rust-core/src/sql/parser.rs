use sqlparser::ast::*;
use sqlparser::dialect::GenericDialect;
use sqlparser::parser::Parser;

use crate::types::{SqlCompletionType, SqlContext};

#[derive(Debug)]
pub enum QueryType {
    Select,
    Insert,
    Update,
    Delete,
    Create,
    Alter,
    Drop,
    Other,
}

#[derive(Debug)]
pub struct ParsedStatement {
    pub query_type: QueryType,
    pub tables_used: Vec<String>,
}

fn extract_tables_from_query(query: &Query) -> Vec<String> {
    let mut tables = Vec::new();
    if let SetExpr::Select(select) = query.body.as_ref() {
        for item in &select.from {
            if let TableFactor::Table { name, .. } = &item.relation {
                tables.push(name.to_string());
            }
        }
    }
    tables
}

pub fn classify_sql(sql: &str) -> Result<ParsedStatement, String> {
    let dialect = GenericDialect;
    let stmts = Parser::parse_sql(&dialect, sql).map_err(|e| e.to_string())?;

    let stmt = stmts.into_iter().next().ok_or("Empty SQL statement")?;

    let (query_type, tables_used) = match &stmt {
        Statement::Query(query) => (QueryType::Select, extract_tables_from_query(query)),
        Statement::Insert(insert) => (QueryType::Insert, vec![insert.table_name.to_string()]),
        Statement::Update { table, .. } => (QueryType::Update, vec![table.to_string()]),
        Statement::Delete { .. } => (QueryType::Delete, vec![]),
        Statement::CreateTable(ct) => (QueryType::Create, vec![ct.name.to_string()]),
        Statement::CreateIndex { .. }
        | Statement::CreateView { .. }
        | Statement::CreateSchema { .. }
        | Statement::CreateDatabase { .. } => (QueryType::Create, vec![]),
        Statement::AlterTable { name, .. } => (QueryType::Alter, vec![name.to_string()]),
        Statement::Drop { .. } => (QueryType::Drop, vec![]),
        _ => (QueryType::Other, vec![]),
    };

    Ok(ParsedStatement {
        query_type,
        tables_used,
    })
}

// ---------------------------------------------------------------------------
// Split SQL into statements by semicolons
// ---------------------------------------------------------------------------

pub fn split_sql(sql: &str) -> Vec<String> {
    sql.split(';')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

pub fn strip_leading_comments(sql: &str) -> &str {
    let bytes = sql.as_bytes();
    let mut i = 0;
    let n = bytes.len();
    loop {
        while i < n && bytes[i].is_ascii_whitespace() {
            i += 1;
        }
        if i + 1 < n && bytes[i] == b'-' && bytes[i + 1] == b'-' {
            while i < n && bytes[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        if i + 1 < n && bytes[i] == b'/' && bytes[i + 1] == b'*' {
            i += 2;
            while i + 1 < n && !(bytes[i] == b'*' && bytes[i + 1] == b'/') {
                i += 1;
            }
            if i + 1 < n {
                i += 2;
            } else {
                i = n;
            }
            continue;
        }
        break;
    }
    &sql[i..]
}

// ---------------------------------------------------------------------------
// Extract table names from SQL
// ---------------------------------------------------------------------------

pub fn extract_table_names(sql: &str) -> Vec<String> {
    let dialect = GenericDialect;
    let raw: Vec<String> = if let Ok(stmts) = Parser::parse_sql(&dialect, sql) {
        let mut tables = Vec::new();
        for stmt in stmts {
            match &stmt {
                Statement::Query(query) => tables.extend(extract_tables_from_query(query)),
                Statement::Insert(insert) => tables.push(insert.table_name.to_string()),
                Statement::Update { table, .. } => tables.push(table.to_string()),
                Statement::CreateTable(ct) => tables.push(ct.name.to_string()),
                _ => {}
            }
        }
        tables
    } else {
        // Fallback: simple keyword-based extraction
        let upper = sql.to_uppercase();
        let keywords = ["FROM", "JOIN", "INTO", "UPDATE", "TABLE", "INTO"];
        let parts: Vec<&str> = upper.split_whitespace().collect();
        let mut tables = Vec::new();
        for (i, word) in parts.iter().enumerate() {
            if keywords.contains(word) {
                if let Some(next) = parts.get(i + 1) {
                    let name = next.trim_matches(|c: char| c == '"' || c == '\'' || c == '`' || c == ';');
                    if !name.is_empty() && !keywords.contains(&name) {
                        tables.push(name.to_string());
                    }
                }
            }
        }
        tables
    };
    raw.into_iter().map(|t| strip_identifier_quotes(&t)).collect()
}

fn strip_identifier_quotes(raw: &str) -> String {
    // sqlparser preserves the original quote characters in `to_string()`; strip
    // the outermost matching pair for `"`, `` ` ``, or `[]` so downstream code
    // (dialect-aware quote_ident, etc.) can re-quote appropriately.
    let bytes = raw.as_bytes();
    if bytes.len() >= 2 {
        let first = bytes[0];
        let last = bytes[bytes.len() - 1];
        let matched = (first == b'"' && last == b'"')
            || (first == b'`' && last == b'`')
            || (first == b'[' && last == b']');
        if matched {
            return raw[1..raw.len() - 1].to_string();
        }
    }
    raw.to_string()
}

// ---------------------------------------------------------------------------
// SQL formatter — add newlines before major keywords
// ---------------------------------------------------------------------------

pub fn format_sql(sql: &str) -> String {
    let keywords = [
        "SELECT", "FROM", "WHERE", "ORDER BY", "GROUP BY", "HAVING",
        "LIMIT", "OFFSET", "INSERT INTO", "UPDATE", "SET", "DELETE FROM",
        "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "UNION", "UNION ALL",
        "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "OUTER JOIN",
        "ON", "WITH",
    ];

    let mut result = sql.to_string();
    for kw in keywords {
        let upper = result.to_uppercase();
        let mut search_start = 0;
        loop {
            let kw_upper = kw.to_uppercase();
            if let Some(pos) = upper[search_start..].find(&kw_upper) {
                let actual_pos = search_start + pos;
                // Check it's a word boundary (prev char is space/newline or start)
                if actual_pos > 0 {
                    let prev = result.as_bytes()[actual_pos - 1];
                    if prev != b' ' && prev != b'\n' {
                        search_start = actual_pos + 1;
                        continue;
                    }
                }
                // Check next char is word boundary too
                let end = actual_pos + kw.len();
                if end < result.len() {
                    let next = result.as_bytes()[end];
                    if next.is_ascii_alphanumeric() || next == b'_' {
                        search_start = actual_pos + 1;
                        continue;
                    }
                }
                // Insert newline before the keyword (replace preceding space)
                if actual_pos > 0 {
                    let before = result.as_bytes()[actual_pos - 1];
                    if before != b'\n' {
                        result.insert(actual_pos, '\n');
                        if before == b' ' {
                            result.remove(actual_pos + 1);
                        }
                        search_start = actual_pos + kw.len() + 1;
                        continue;
                    }
                }
                search_start = actual_pos + kw.len();
            } else {
                break;
            }
        }
    }

    result
}

// ---------------------------------------------------------------------------
// SQL context analysis for auto-complete
// ---------------------------------------------------------------------------

fn tokenize_sql(text: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut in_string = false;
    let mut string_char = '\'';

    for ch in text.chars() {
        if in_string {
            current.push(ch);
            if ch == string_char {
                in_string = false;
            }
            continue;
        }
        if ch == '\'' || ch == '"' || ch == '`' {
            if !current.is_empty() {
                tokens.push(current.clone());
            }
            current = String::new();
            current.push(ch);
            in_string = true;
            string_char = ch;
            continue;
        }
        if ch.is_whitespace() || ch == ',' || ch == '(' || ch == ')' || ch == ';' || ch == '\n' {
            if !current.is_empty() {
                tokens.push(current.clone());
                current.clear();
            }
            if ch == '\n' {
                tokens.push("\n".to_string());
            }
            continue;
        }
        current.push(ch);
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    tokens
}

fn extract_current_word(text: &str) -> Option<String> {
    let trimmed = text.trim_end();
    let last_space = trimmed.rfind(|c: char| c == ' ' || c == '\n');
    match last_space {
        Some(pos) => {
            let word = trimmed[pos + 1..].trim();
            if word.is_empty() { None } else { Some(word.to_string()) }
        }
        None => {
            if trimmed.is_empty() { None } else { Some(trimmed.to_string()) }
        }
    }
}

fn has_last_word(text: &str, keyword: &str) -> bool {
    let upper = text.to_uppercase();
    let kw = keyword.to_uppercase();
    if let Some(pos) = upper.rfind(&kw) {
        let after = upper[pos + kw.len()..].trim();
        after.is_empty() || !after.contains(' ')
    } else {
        false
    }
}

const TABLE_EXPECTERS: &[&str] = &[
    "FROM", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "OUTER JOIN",
    "INTO", "TABLE", "UPDATE",
];

const COLUMN_EXPECTERS: &[&str] = &[
    "SELECT", "WHERE", "ORDER BY", "GROUP BY", "HAVING",
    "ON", "SET", "AND", "OR",
];

const STATEMENT_STARTERS: &[&str] = &[
    "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
    "TRUNCATE", "WITH", "EXPLAIN", "DESCRIBE", "SHOW", "USE", "CALL",
];

const VALUE_OPERATORS: &[&str] = &["IN", "=", "!=", "<>", "<", ">", "<=", ">=", "LIKE"];

pub fn analyze_sql_context(sql: &str, cursor: usize) -> SqlContext {
    let len = sql.len();
    let pos = cursor.min(len);
    let text_before = &sql[..pos];
    let tokens = tokenize_sql(text_before);
    let partial = extract_current_word(text_before).unwrap_or_default();

    if tokens.is_empty() {
        return SqlContext {
            completion_type: SqlCompletionType::Statement,
            partial,
        };
    }

    let last = tokens.last().map(|s| s.as_str()).unwrap_or("");
    let upper_last = last.to_uppercase();

    for kw in TABLE_EXPECTERS {
        if upper_last == *kw || has_last_word(text_before, kw) {
            return SqlContext { completion_type: SqlCompletionType::TableName, partial };
        }
    }

    for kw in COLUMN_EXPECTERS {
        if upper_last == *kw || has_last_word(text_before, kw) {
            return SqlContext { completion_type: SqlCompletionType::ColumnName, partial };
        }
    }

    for op in VALUE_OPERATORS {
        if upper_last == *op || has_last_word(text_before, op) {
            return SqlContext { completion_type: SqlCompletionType::Value, partial };
        }
    }

    if upper_last.ends_with('(') {
        return SqlContext { completion_type: SqlCompletionType::Function, partial };
    }

    if tokens.len() <= 1 || tokens.get(tokens.len().wrapping_sub(2)).map(|s| s.as_str()) == Some("\n") {
        return SqlContext { completion_type: SqlCompletionType::Statement, partial };
    }

    if STATEMENT_STARTERS.contains(&upper_last.as_str()) {
        return SqlContext { completion_type: SqlCompletionType::ColumnName, partial };
    }

    SqlContext {
        completion_type: SqlCompletionType::ColumnName,
        partial,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_sql() {
        let r = split_sql("SELECT 1; SELECT 2");
        assert_eq!(r.len(), 2);
    }

    #[test]
    fn test_extract_table_names() {
        let r = extract_table_names("SELECT * FROM users JOIN orders ON users.id = orders.user_id");
        assert!(r.contains(&"users".to_string()));
    }

    #[test]
    fn test_extract_table_names_strips_quotes() {
        let bt = extract_table_names("SELECT * FROM `mytable`");
        assert_eq!(bt, vec!["mytable".to_string()]);
        let dq = extract_table_names("SELECT * FROM \"mytable\"");
        assert_eq!(dq, vec!["mytable".to_string()]);
    }

    #[test]
    fn test_format_sql() {
        let r = format_sql("SELECT * FROM users WHERE id = 1");
        assert!(r.contains('\n'));
    }

    #[test]
    fn test_analyze_sql_context_table() {
        let ctx = analyze_sql_context("SELECT * FROM ", 14);
        assert_eq!(ctx.completion_type, SqlCompletionType::TableName);
    }

    #[test]
    fn test_sql_context_statement_start() {
        let ctx = analyze_sql_context("", 0);
        assert_eq!(ctx.completion_type, SqlCompletionType::Statement);
    }

    #[test]
    fn test_strip_leading_comments_line() {
        // S1: single line comment before WITH
        assert_eq!(strip_leading_comments("-- 汇总\nWITH cte AS (SELECT 1) SELECT * FROM cte"),
                   "WITH cte AS (SELECT 1) SELECT * FROM cte");
    }

    #[test]
    fn test_strip_leading_comments_block() {
        // S2: block comment before SELECT
        assert_eq!(strip_leading_comments("/* multiline\n comment */\n\nSELECT 1"),
                   "SELECT 1");
    }

    #[test]
    fn test_strip_leading_comments_mixed() {
        // S3: mixed line + block + line comments before WITH
        let input = "-- a\n-- b\n/* c\n multi */\n-- d\nWITH x AS (SELECT 1) SELECT x FROM x";
        assert_eq!(strip_leading_comments(input),
                   "WITH x AS (SELECT 1) SELECT x FROM x");
    }

    #[test]
    fn test_strip_leading_comments_only() {
        // S4: only comments, no SQL — returns empty
        assert_eq!(strip_leading_comments("-- only\n/* stuff */\n   "), "");
    }

    #[test]
    fn test_strip_leading_comments_no_comment() {
        // Sanity: pass-through when no leading comment
        assert_eq!(strip_leading_comments("SELECT 1"), "SELECT 1");
        assert_eq!(strip_leading_comments("   SELECT 1"), "SELECT 1");
    }

    #[test]
    fn test_strip_leading_comments_inline_not_leading() {
        // Regression: comments AFTER the keyword must be preserved verbatim
        let sql = "SELECT 1 -- trailing";
        assert_eq!(strip_leading_comments(sql), "SELECT 1 -- trailing");
    }
}
