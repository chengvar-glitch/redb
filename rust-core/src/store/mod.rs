use std::fs;
use std::path::Path;
use std::sync::Mutex;

use crate::types::*;

/// A saved connection entry returned by the store.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
pub struct SavedConnection {
    pub id: String,
    pub name: String,
    pub config: DatabaseConfig,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cached_tables: Option<Vec<TableInfo>>,
}

/// Thread-safe store for saving/loading connection configurations
/// to a local JSON file.
#[derive(uniffi::Object)]
pub struct ConnectionStore {
    path: String,
    lock: Mutex<()>,
}

#[uniffi::export]
impl ConnectionStore {
    /// Open (or create) a store at `path`.
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Self, DbError> {
        // Ensure parent directory exists
        if let Some(parent) = Path::new(&path).parent() {
            fs::create_dir_all(parent).map_err(|e| DbError::ConnectionError {
                message: format!("Failed to create store directory: {e}"),
            })?;
        }
        // Create or validate file
        let file_exists = Path::new(&path).exists();
        if !file_exists {
            fs::write(&path, "[]").map_err(|e| DbError::ConnectionError {
                message: format!("Failed to create store file: {e}"),
            })?;
        } else {
            // Validate existing content; reset if corrupt (e.g. old SQLite .db)
            let content = fs::read_to_string(&path).unwrap_or_default();
            if serde_json::from_str::<Vec<SavedConnection>>(&content).is_err() {
                fs::write(&path, "[]").map_err(|e| DbError::ConnectionError {
                    message: format!("Failed to reset corrupt store file: {e}"),
                })?;
            }
        }
        Ok(Self {
            path,
            lock: Mutex::new(()),
        })
    }

    /// Save a connection config. If `id` already exists it is updated.
    pub fn save(&self, id: String, name: String, config: DatabaseConfig) -> Result<(), DbError> {
        let _guard = self.lock.lock().unwrap();
        let mut connections = self.read_all()?;

        if let Some(existing) = connections.iter_mut().find(|c| c.id == id) {
            existing.name = name;
            existing.config = config;
        } else {
            connections.push(SavedConnection { id, name, config, cached_tables: None });
        }

        self.write_all(&connections)
    }

    /// Load a connection config by id.
    pub fn load(&self, id: String) -> Result<Option<SavedConnection>, DbError> {
        let _guard = self.lock.lock().unwrap();
        let connections = self.read_all()?;
        Ok(connections.into_iter().find(|c| c.id == id))
    }

    /// List all saved connections.
    pub fn list_all(&self) -> Result<Vec<SavedConnection>, DbError> {
        let _guard = self.lock.lock().unwrap();
        self.read_all()
    }

    /// Cached tables for a connection.
    pub fn save_cached_tables(&self, id: String, tables: Vec<TableInfo>) -> Result<(), DbError> {
        let _guard = self.lock.lock().unwrap();
        let mut connections = self.read_all()?;
        if let Some(existing) = connections.iter_mut().find(|c| c.id == id) {
            existing.cached_tables = Some(tables);
        }
        self.write_all(&connections)
    }

    /// Delete a saved connection by id.
    pub fn delete(&self, id: String) -> Result<(), DbError> {
        let _guard = self.lock.lock().unwrap();
        let mut connections = self.read_all()?;
        connections.retain(|c| c.id != id);
        self.write_all(&connections)
    }
}

// Internal helpers
impl ConnectionStore {
    fn read_all(&self) -> Result<Vec<SavedConnection>, DbError> {
        let data = fs::read_to_string(&self.path).map_err(|e| DbError::QueryError {
            message: format!("Failed to read store: {e}"),
        })?;
        serde_json::from_str(&data).map_err(|e| DbError::QueryError {
            message: format!("Failed to parse store: {e}"),
        })
    }

    fn write_all(&self, connections: &[SavedConnection]) -> Result<(), DbError> {
        let data = serde_json::to_string_pretty(connections).map_err(|e| {
            DbError::QueryError {
                message: format!("Failed to serialize store: {e}"),
            }
        })?;
        // Atomic write via temp file
        let tmp = format!("{}.tmp", self.path);
        fs::write(&tmp, &data).map_err(|e| DbError::QueryError {
            message: format!("Failed to write store: {e}"),
        })?;
        fs::rename(&tmp, &self.path).map_err(|e| DbError::QueryError {
            message: format!("Failed to commit store: {e}"),
        })?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// QueryStore: saved queries + table usage
// ---------------------------------------------------------------------------

/// Thread-safe store for saved queries and table usage statistics.
#[derive(uniffi::Object)]
pub struct QueryStore {
    queries_path: String,
    usage_path: String,
    lock: Mutex<()>,
}

#[uniffi::export]
impl QueryStore {
    #[uniffi::constructor]
    pub fn open(base_dir: String) -> Result<Self, DbError> {
        let dir = Path::new(&base_dir);
        fs::create_dir_all(dir).map_err(|e| DbError::ConnectionError {
            message: format!("Failed to create store directory: {e}"),
        })?;

        let queries_path = dir.join("saved_queries.json");
        let usage_path = dir.join("table_usage.json");

        // Init saved_queries.json
        if !queries_path.exists() {
            fs::write(&queries_path, "[]").map_err(|e| DbError::ConnectionError {
                message: format!("Failed to init queries file: {e}"),
            })?;
        }

        // Init table_usage.json
        if !usage_path.exists() {
            fs::write(&usage_path, "[]").map_err(|e| DbError::ConnectionError {
                message: format!("Failed to init usage file: {e}"),
            })?;
        }

        Ok(Self {
            queries_path: queries_path.to_string_lossy().to_string(),
            usage_path: usage_path.to_string_lossy().to_string(),
            lock: Mutex::new(()),
        })
    }

    // -- Saved Queries --

    pub fn save_query(&self, id: String, name: String, sql: String, created_at: i64) -> Result<(), DbError> {
        let _guard = self.lock.lock().unwrap();
        let mut queries: Vec<SavedQuery> = self.read_json(&self.queries_path)?;
        if let Some(existing) = queries.iter_mut().find(|q| q.id == id) {
            existing.name = name;
            existing.sql = sql;
        } else {
            queries.push(SavedQuery { id, name, sql, created_at });
        }
        self.write_json(&self.queries_path, &queries)
    }

    pub fn list_saved_queries(&self) -> Result<Vec<SavedQuery>, DbError> {
        let _guard = self.lock.lock().unwrap();
        self.read_json(&self.queries_path)
    }

    pub fn delete_saved_query(&self, id: String) -> Result<(), DbError> {
        let _guard = self.lock.lock().unwrap();
        let mut queries: Vec<SavedQuery> = self.read_json(&self.queries_path)?;
        queries.retain(|q| q.id != id);
        self.write_json(&self.queries_path, &queries)
    }

    // -- Table Usage --

    pub fn record_table_usage(&self, table_name: String) -> Result<(), DbError> {
        let _guard = self.lock.lock().unwrap();
        let mut usage: Vec<TableUsageEntry> = self.read_json(&self.usage_path)?;
        if let Some(entry) = usage.iter_mut().find(|e| e.table_name == table_name) {
            entry.count += 1;
        } else {
            usage.push(TableUsageEntry { table_name, count: 1 });
        }
        self.write_json(&self.usage_path, &usage)
    }

    pub fn get_table_usage(&self) -> Result<Vec<TableUsageEntry>, DbError> {
        let _guard = self.lock.lock().unwrap();
        self.read_json(&self.usage_path)
    }

    pub fn reset_table_usage(&self) -> Result<(), DbError> {
        let _guard = self.lock.lock().unwrap();
        self.write_json(&self.usage_path, &Vec::<TableUsageEntry>::new())
    }
}

// Internal helpers
impl QueryStore {
    fn read_json<T: serde::de::DeserializeOwned>(&self, path: &str) -> Result<T, DbError> {
        let data = fs::read_to_string(path).map_err(|e| DbError::QueryError {
            message: format!("Failed to read store file: {e}"),
        })?;
        serde_json::from_str(&data).map_err(|e| DbError::QueryError {
            message: format!("Failed to parse store file: {e}"),
        })
    }

    fn write_json<T: serde::Serialize>(&self, path: &str, value: &T) -> Result<(), DbError> {
        let data = serde_json::to_string_pretty(value).map_err(|e| DbError::QueryError {
            message: format!("Failed to serialize store: {e}"),
        })?;
        let tmp = format!("{path}.tmp");
        fs::write(&tmp, &data).map_err(|e| DbError::QueryError {
            message: format!("Failed to write store: {e}"),
        })?;
        fs::rename(&tmp, path).map_err(|e| DbError::QueryError {
            message: format!("Failed to commit store: {e}"),
        })?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::DatabaseType;

    fn test_config() -> DatabaseConfig {
        DatabaseConfig {
            db_type: DatabaseType::Postgres,
            url: "postgres://user:pass@localhost:5432/mydb".into(),
            host: Some("localhost".into()),
            port: Some(5432),
            database: Some("mydb".into()),
            username: Some("user".into()),
            password: Some("pass".into()),
            max_connections: 5,
        }
    }

    #[test]
    fn test_save_and_load() {
        let tmp = std::env::temp_dir().join("redb_test_store.json");
        let _ = std::fs::remove_file(&tmp);

        let store = ConnectionStore::open(tmp.to_str().unwrap().to_string()).unwrap();

        let config = test_config();
        store
            .save("conn1".into(), "My PG".into(), config.clone())
            .unwrap();

        let loaded = store.load("conn1".into()).unwrap().unwrap();
        assert_eq!(loaded.id, "conn1");
        assert_eq!(loaded.name, "My PG");
        assert_eq!(loaded.config.db_type, DatabaseType::Postgres);
        assert_eq!(loaded.config.host, Some("localhost".into()));
        assert_eq!(loaded.config.username, Some("user".into()));
        assert_eq!(loaded.config.password, Some("pass".into()));

        let all = store.list_all().unwrap();
        assert_eq!(all.len(), 1);

        // Update
        store
            .save("conn1".into(), "Renamed".into(), config)
            .unwrap();
        let loaded = store.load("conn1".into()).unwrap().unwrap();
        assert_eq!(loaded.name, "Renamed");

        store.delete("conn1".into()).unwrap();
        assert!(store.load("conn1".into()).unwrap().is_none());

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn test_multiple_connections() {
        let tmp = std::env::temp_dir().join("redb_test_multi.json");
        let _ = std::fs::remove_file(&tmp);
        let store = ConnectionStore::open(tmp.to_str().unwrap().to_string()).unwrap();

        store
            .save("a".into(), "A".into(), test_config())
            .unwrap();
        store
            .save("b".into(), "B".into(), test_config())
            .unwrap();
        store
            .save("c".into(), "C".into(), test_config())
            .unwrap();

        assert_eq!(store.list_all().unwrap().len(), 3);

        store.delete("b".into()).unwrap();
        assert_eq!(store.list_all().unwrap().len(), 2);

        let _ = std::fs::remove_file(&tmp);
    }
}
