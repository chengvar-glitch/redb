use std::sync::Arc;
use std::sync::Mutex;

use crate::db::DatabaseManager as InnerManager;
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

    pub fn execute_query(&self, sql: String) -> Result<QueryResult, DbError> {
        self.inner.lock().unwrap().execute_query(&sql)
    }
}

// ---------------------------------------------------------------------------
// Top-level convenience function (also exported by uniffi)
// ---------------------------------------------------------------------------

#[uniffi::export]
pub fn create_database_manager(config: DatabaseConfig) -> Arc<DatabaseManager> {
    DatabaseManager::new(config)
}
