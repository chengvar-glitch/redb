use sqlparser::ast::*;
use sqlparser::dialect::GenericDialect;
use sqlparser::parser::Parser;

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
