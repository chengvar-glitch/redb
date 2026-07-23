use std::sync::Arc;
use std::sync::Mutex;

use crate::db::DatabaseManager as InnerManager;
use crate::sql::parser;
use crate::types::*;

/// Thread-safe handle exported via uniffi.
/// Swift sees this as `DatabaseManager` class.
#[derive(uniffi::Object)]
pub struct DatabaseManager {
    inner: Arc<Mutex<InnerManager>>,
}

#[uniffi::export]
impl DatabaseManager {
    #[uniffi::constructor]
    pub fn new(config: DatabaseConfig) -> Arc<Self> {
        Arc::new(Self {
            inner: Arc::new(Mutex::new(InnerManager::new(config))),
        })
    }

    pub fn connect(&self) -> Result<(), DbError> {
        self.inner.lock().unwrap().connect()
    }

    pub fn disconnect(&self) -> Result<(), DbError> {
        self.inner.lock().unwrap().disconnect()
    }

    pub fn status(&self) -> ConnStatus {
        self.inner.lock().unwrap().status()
    }

    pub fn list_tables(&self) -> Result<Vec<TableInfo>, DbError> {
        self.inner.lock().unwrap().list_tables()
    }

    pub fn current_database(&self) -> Result<String, DbError> {
        self.inner.lock().unwrap().current_database()
    }

    pub fn list_databases(&self) -> Result<Vec<String>, DbError> {
        self.inner.lock().unwrap().list_databases()
    }

    pub fn quick_view(&self, table_name: String, row_limit: u32) -> Result<QueryResult, DbError> {
        self.inner.lock().unwrap().quick_view(&table_name, row_limit)
    }

    pub fn execute_query(&self, sql: String) -> Result<QueryResult, DbError> {
        self.inner.lock().unwrap().execute_query(&sql)
    }

    pub fn update_row_by_primary_key(
        &self,
        table: String,
        set_column: String,
        set_value: CellValue,
        where_columns: Vec<String>,
        where_values: Vec<CellValue>,
    ) -> Result<QueryResult, DbError> {
        self.inner.lock().unwrap().update_row_by_primary_key(
            &table,
            &set_column,
            set_value,
            where_columns,
            where_values,
        )
    }

    pub fn delete_row_by_primary_key(
        &self,
        table: String,
        where_columns: Vec<String>,
        where_values: Vec<CellValue>,
    ) -> Result<QueryResult, DbError> {
        self.inner.lock().unwrap().delete_row_by_primary_key(
            &table,
            where_columns,
            where_values,
        )
    }
}

// ---------------------------------------------------------------------------
// Free functions (SQL utilities, no DB connection needed)
// ---------------------------------------------------------------------------

#[uniffi::export]
pub fn split_sql(sql: String) -> Vec<String> {
    parser::split_sql(&sql)
}

#[uniffi::export]
pub fn build_quick_view_sql(
    db_type: DatabaseType,
    table: String,
    row_limit: u32,
) -> Result<String, DbError> {
    crate::sql::builder::build_quick_view_sql(&db_type, &table, row_limit)
}

#[uniffi::export]
pub fn extract_table_names(sql: String) -> Vec<String> {
    parser::extract_table_names(&sql)
}

#[uniffi::export]
pub fn format_sql(sql: String) -> String {
    parser::format_sql(&sql)
}

#[uniffi::export]
pub fn analyze_sql_context(sql: String, cursor: u64) -> SqlContext {
    parser::analyze_sql_context(&sql, cursor as usize)
}

#[uniffi::export]
pub fn database_default_port(db_type: DatabaseType) -> u32 {
    db_type.default_port()
}

#[uniffi::export]
pub fn create_database_manager(config: DatabaseConfig) -> Arc<DatabaseManager> {
    DatabaseManager::new(config)
}
