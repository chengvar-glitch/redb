use crate::types::{CellValue, DatabaseType, DbError};

pub struct SqlWithParams {
    pub sql: String,
    pub params: Vec<CellValue>,
}

fn param_placeholder(db: &DatabaseType, index_1based: usize) -> String {
    match db {
        DatabaseType::Postgres => format!("${index_1based}"),
        DatabaseType::SqlServer => format!("@P{index_1based}"),
        _ => "?".to_string(),
    }
}

fn quote_ident(db: &DatabaseType, name: &str) -> Result<String, DbError> {
    if name.is_empty() {
        return Err(DbError::QueryError { message: "identifier is empty".into() });
    }
    let q = db.quote_char();
    // Reject the quote char itself inside identifiers to prevent SQL injection
    // via crafted column/table names — we do not attempt to double-escape it.
    if name.contains(q) {
        return Err(DbError::QueryError {
            message: format!("identifier contains reserved quote character `{q}`: {name}"),
        });
    }
    Ok(format!("{q}{name}{q}"))
}

fn is_bindable(v: &CellValue) -> bool {
    // NULL cannot be bound as a normal parameter for equality (`= NULL` is always
    // false in SQL; `IS NULL` has no rhs) — emit it inline. Blob is excluded from
    // WHERE altogether by callers, and would fail equality anyway.
    !matches!(v, CellValue::Null | CellValue::Blob(_))
}

fn where_clause(
    db: &DatabaseType,
    where_columns: &[String],
    where_values: &[CellValue],
    params: &mut Vec<CellValue>,
) -> Result<String, DbError> {
    if where_columns.is_empty() {
        return Err(DbError::QueryError {
            message: "WHERE clause needs at least one column".into(),
        });
    }
    if where_columns.len() != where_values.len() {
        return Err(DbError::QueryError {
            message: "column/value length mismatch in WHERE clause".into(),
        });
    }
    let mut parts: Vec<String> = Vec::with_capacity(where_columns.len());
    for (c, v) in where_columns.iter().zip(where_values.iter()) {
        if matches!(v, CellValue::Blob(_)) {
            continue;
        }
        let col_q = quote_ident(db, c)?;
        if matches!(v, CellValue::Null) {
            parts.push(format!("{col_q} IS NULL"));
        } else {
            let ph = param_placeholder(db, params.len() + 1);
            parts.push(format!("{col_q} = {ph}"));
            params.push(v.clone());
        }
    }
    if parts.is_empty() {
        return Err(DbError::QueryError {
            message: "no usable WHERE columns (blob values cannot be matched literally)".into(),
        });
    }
    Ok(parts.join(" AND "))
}

pub fn build_update_by_pk(
    db: &DatabaseType,
    table: &str,
    set_column: &str,
    set_value: &CellValue,
    where_columns: &[String],
    where_values: &[CellValue],
) -> Result<SqlWithParams, DbError> {
    let table_q = quote_ident(db, table)?;
    let set_col_q = quote_ident(db, set_column)?;
    let mut params: Vec<CellValue> = Vec::new();

    let set_clause = if is_bindable(set_value) {
        let ph = param_placeholder(db, params.len() + 1);
        params.push(set_value.clone());
        format!("{set_col_q} = {ph}")
    } else {
        // NULL is the only non-bindable SET target we honor; Blob is coerced
        // to NULL to keep the surface small (Blob writes are out of scope).
        format!("{set_col_q} = NULL")
    };

    let where_sql = where_clause(db, where_columns, where_values, &mut params)?;
    Ok(SqlWithParams {
        sql: format!("UPDATE {table_q} SET {set_clause} WHERE {where_sql}"),
        params,
    })
}

pub fn build_delete_by_pk(
    db: &DatabaseType,
    table: &str,
    where_columns: &[String],
    where_values: &[CellValue],
) -> Result<SqlWithParams, DbError> {
    let table_q = quote_ident(db, table)?;
    let mut params: Vec<CellValue> = Vec::new();
    let where_sql = where_clause(db, where_columns, where_values, &mut params)?;
    Ok(SqlWithParams {
        sql: format!("DELETE FROM {table_q} WHERE {where_sql}"),
        params,
    })
}

pub fn build_quick_view_sql(
    db: &DatabaseType,
    table: &str,
    row_limit: u32,
) -> Result<String, DbError> {
    let table_q = quote_ident(db, table)?;
    if row_limit == 0 {
        Ok(format!("SELECT * FROM {table_q}"))
    } else {
        Ok(format!("SELECT * FROM {table_q} LIMIT {row_limit}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn update_by_pk_postgres_uses_dollar_placeholders() {
        let out = build_update_by_pk(
            &DatabaseType::Postgres,
            "users",
            "name",
            &CellValue::Text("O'Brien".into()),
            &["id".into()],
            &[CellValue::Int(42)],
        )
        .unwrap();
        assert_eq!(out.sql, r#"UPDATE "users" SET "name" = $1 WHERE "id" = $2"#);
        assert_eq!(out.params.len(), 2);
    }

    #[test]
    fn update_by_pk_mysql_uses_backticks_and_qmarks() {
        let out = build_update_by_pk(
            &DatabaseType::MySql,
            "users",
            "email",
            &CellValue::Text("a@b".into()),
            &["id".into()],
            &[CellValue::Int(1)],
        )
        .unwrap();
        assert_eq!(out.sql, "UPDATE `users` SET `email` = ? WHERE `id` = ?");
        assert_eq!(out.params.len(), 2);
    }

    #[test]
    fn update_set_null_is_inlined_not_bound() {
        let out = build_update_by_pk(
            &DatabaseType::Postgres,
            "t",
            "col",
            &CellValue::Null,
            &["id".into()],
            &[CellValue::Int(1)],
        )
        .unwrap();
        assert_eq!(out.sql, r#"UPDATE "t" SET "col" = NULL WHERE "id" = $1"#);
        assert_eq!(out.params.len(), 1);
    }

    #[test]
    fn delete_by_pk_sqlserver_uses_named_placeholders() {
        let out = build_delete_by_pk(
            &DatabaseType::SqlServer,
            "t",
            &["a".into(), "b".into()],
            &[CellValue::Int(1), CellValue::Text("x".into())],
        )
        .unwrap();
        assert_eq!(out.sql, r#"DELETE FROM "t" WHERE "a" = @P1 AND "b" = @P2"#);
        assert_eq!(out.params.len(), 2);
    }

    #[test]
    fn where_null_stays_inline() {
        let out = build_delete_by_pk(
            &DatabaseType::Postgres,
            "t",
            &["a".into(), "b".into()],
            &[CellValue::Int(1), CellValue::Null],
        )
        .unwrap();
        assert_eq!(out.sql, r#"DELETE FROM "t" WHERE "a" = $1 AND "b" IS NULL"#);
        assert_eq!(out.params.len(), 1);
    }

    #[test]
    fn rejects_identifier_with_quote_char() {
        let err = build_update_by_pk(
            &DatabaseType::Postgres,
            "us\"ers",
            "x",
            &CellValue::Int(1),
            &["id".into()],
            &[CellValue::Int(1)],
        );
        assert!(err.is_err());
    }
}
