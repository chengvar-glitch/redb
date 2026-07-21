/// Core data types, annotated with uniffi derives for FFI export.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize, uniffi::Enum)]
pub enum DatabaseType {
    Sqlite,
    Postgres,
    MySql,
    MariaDB,
    SqlServer,
    Db2,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum CellValue {
    Null,
    Int(i64),
    Float(f64),
    Text(String),
    Blob(Vec<u8>),
}

impl std::fmt::Display for CellValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CellValue::Null => write!(f, "NULL"),
            CellValue::Int(v) => write!(f, "{v}"),
            CellValue::Float(v) => write!(f, "{v}"),
            CellValue::Text(v) => write!(f, "{v}"),
            CellValue::Blob(v) => write!(f, "<blob {} bytes>", v.len()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum ConnStatus {
    Connected,
    Disconnected,
    Error { message: String },
}

// ---------------------------------------------------------------------------
// Records (dicts)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
pub struct ColumnInfo {
    pub name: String,
    pub data_type: String,
    pub nullable: bool,
    pub is_primary_key: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct QueryResult {
    pub columns: Vec<ColumnInfo>,
    pub rows: Vec<Vec<CellValue>>,
    pub rows_affected: u64,
    pub execution_time_ms: u64,
}

impl QueryResult {
    pub fn empty() -> Self {
        Self {
            columns: vec![],
            rows: vec![],
            rows_affected: 0,
            execution_time_ms: 0,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
pub struct TableInfo {
    pub name: String,
    pub schema: String,
    pub columns: Vec<ColumnInfo>,
    pub row_count: Option<u64>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
pub struct DatabaseConfig {
    pub db_type: DatabaseType,
    pub url: String,
    pub host: Option<String>,
    pub port: Option<u32>,
    pub database: Option<String>,
    pub username: Option<String>,
    pub password: Option<String>,
    pub max_connections: u32,
    pub log_path: Option<String>,
}

impl DatabaseType {
    pub fn default_port(&self) -> u32 {
        match self {
            DatabaseType::Sqlite => 0,
            DatabaseType::Postgres => 5432,
            DatabaseType::MySql | DatabaseType::MariaDB => 3306,
            DatabaseType::SqlServer => 1433,
            DatabaseType::Db2 => 50000,
        }
    }

    pub fn quote_char(&self) -> &str {
        match self {
            DatabaseType::MySql | DatabaseType::MariaDB => "`",
            _ => "\"",
        }
    }
}

impl DatabaseConfig {
    pub fn new(db_type: DatabaseType, url: impl Into<String>) -> Self {
        Self {
            db_type,
            url: url.into(),
            host: None,
            port: None,
            database: None,
            username: None,
            password: None,
            max_connections: 10,
            log_path: None,
        }
    }

    pub fn build_url(&self) -> String {
        let host = self.host.as_deref().unwrap_or("localhost");
        let db = self.database.as_deref().unwrap_or("mydb");
        let user_pass = match (&self.username, &self.password) {
            (Some(u), Some(p)) => format!("{u}:{p}@"),
            (Some(u), None) => format!("{u}@"),
            _ => String::new(),
        };
        match self.db_type {
            DatabaseType::Sqlite => self.url.clone(),
            DatabaseType::Postgres => {
                let port = self.port.unwrap_or(5432);
                format!("postgres://{user_pass}{host}:{port}/{db}")
            }
            DatabaseType::MySql | DatabaseType::MariaDB => {
                let port = self.port.unwrap_or(3306);
                format!("mysql://{user_pass}{host}:{port}/{db}")
            }
            DatabaseType::SqlServer => {
                let port = self.port.unwrap_or(1433);
                format!("sqlserver://{user_pass}{host}:{port}/{db}")
            }
            DatabaseType::Db2 => {
                let port = self.port.unwrap_or(50000);
                format!("db2://{user_pass}{host}:{port}/{db}")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Persisted query data
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
pub struct SavedQuery {
    pub id: String,
    pub name: String,
    pub sql: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
pub struct TableUsageEntry {
    pub table_name: String,
    pub count: i32,
}

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, thiserror::Error, uniffi::Error)]
pub enum DbError {
    #[error("Connection failed: {message}")]
    ConnectionError { message: String },
    #[error("Query failed: {message}")]
    QueryError { message: String },
    #[error("Not connected")]
    NotConnected,
}

// ---------------------------------------------------------------------------
// Auto-complete types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum SqlCompletionType {
    Statement,
    Keyword,
    TableName,
    ColumnName,
    Function,
    Value,
    Alias,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct SqlContext {
    pub completion_type: SqlCompletionType,
    pub partial: String,
}
