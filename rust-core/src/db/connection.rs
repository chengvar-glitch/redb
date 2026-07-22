use std::sync::Mutex;
use std::time::Instant;
use std::fs::{self, OpenOptions};
use std::io::Write;

use crate::sql::parser::strip_leading_comments;
use crate::types::*;

#[cfg(feature = "mysql")]
use super::ssh_tunnel::SshTunnel;

// ---------------------------------------------------------------------------
// Internal connection enum
// ---------------------------------------------------------------------------

enum DbConnection {
    #[cfg(feature = "sqlite")]
    Sqlite(rusqlite::Connection),
    #[cfg(feature = "postgres")]
    Postgres {
        client: tokio_postgres::Client,
        runtime: tokio::runtime::Runtime,
    },
    #[cfg(feature = "mysql")]
    MySql {
        conn: mysql_async::Conn,
        runtime: tokio::runtime::Runtime,
        _tunnel: Option<SshTunnel>,
    },
    #[cfg(feature = "sqlserver")]
    SqlServer {
        client: tiberius::Client<tokio_util::compat::Compat<tokio::net::TcpStream>>,
        runtime: tokio::runtime::Runtime,
    },
    #[cfg(feature = "db2")]
    Db2 {
        conn: odbc_api::Connection<'static>,
    },
}

// ---------------------------------------------------------------------------
// Database manager
// ---------------------------------------------------------------------------

pub struct DatabaseManager {
    config: DatabaseConfig,
    conn: Mutex<Option<DbConnection>>,
}

impl DatabaseManager {
    pub fn new(config: DatabaseConfig) -> Self {
        Self {
            config,
            conn: Mutex::new(None),
        }
    }

    fn detect_db_type(url: &str) -> DatabaseType {
        if url.starts_with("postgres://") || url.starts_with("postgresql://") {
            DatabaseType::Postgres
        } else if url.starts_with("mysql://") || url.starts_with("mariadb://") {
            DatabaseType::MySql
        } else if url.starts_with("sqlserver://") {
            DatabaseType::SqlServer
        } else if url.starts_with("db2://") {
            DatabaseType::Db2
        } else {
            DatabaseType::Sqlite
        }
    }

    // -- connect ------------------------------------------------------------

    pub fn connect(&self) -> Result<(), DbError> {
        let db_type =
            if self.config.db_type != DatabaseType::Sqlite || self.config.url.is_empty() {
                self.config.db_type.clone()
            } else {
                Self::detect_db_type(&self.config.url)
            };

        let conn = match db_type {
            // --- SQLite ---
            #[cfg(feature = "sqlite")]
            DatabaseType::Sqlite => {
                let c = rusqlite::Connection::open(&self.config.url).map_err(|e| {
                    DbError::ConnectionError {
                        message: e.to_string(),
                    }
                })?;
                if let Some(ref pwd) = self.config.password {
                    c.execute_batch(&format!("PRAGMA key = '{pwd}'"))
                        .map_err(|e| DbError::ConnectionError {
                            message: format!("Failed to set encryption key: {e}"),
                        })?;
                }
                DbConnection::Sqlite(c)
            }
            #[cfg(not(feature = "sqlite"))]
            DatabaseType::Sqlite => {
                return Err(DbError::ConnectionError {
                    message: "SQLite support is not enabled".to_string(),
                });
            }
            // --- PostgreSQL ---
            #[cfg(feature = "postgres")]
            DatabaseType::Postgres => {
                let runtime = tokio::runtime::Runtime::new().map_err(|e| {
                    DbError::ConnectionError {
                        message: e.to_string(),
                    }
                })?;
                let url = self.inject_credentials_into_url();
                let (client, connection) = runtime
                    .block_on(tokio_postgres::connect(&url, tokio_postgres::NoTls))
                    .map_err(|e| DbError::ConnectionError {
                        message: e.to_string(),
                    })?;
                runtime.spawn(async move {
                    if let Err(e) = connection.await {
                        eprintln!("PostgreSQL connection error: {e}");
                    }
                });
                DbConnection::Postgres { client, runtime }
            }
            #[cfg(not(feature = "postgres"))]
            DatabaseType::Postgres => {
                return Err(DbError::ConnectionError {
                    message: "PostgreSQL support is not enabled".to_string(),
                });
            }
            // --- MySQL / MariaDB ---
            #[cfg(feature = "mysql")]
            DatabaseType::MySql | DatabaseType::MariaDB => {
                let runtime = tokio::runtime::Runtime::new().map_err(|e| {
                    DbError::ConnectionError {
                        message: e.to_string(),
                    }
                })?;

                let (opts, tunnel) = Self::build_mysql_opts_with_tunnel(&self.config, &runtime)?;

                let pool = mysql_async::Pool::new(opts);
                let conn = runtime.block_on(pool.get_conn()).map_err(|e| {
                    DbError::ConnectionError {
                        message: e.to_string(),
                    }
                })?;
                DbConnection::MySql { conn, runtime, _tunnel: tunnel }
            }
            #[cfg(not(feature = "mysql"))]
            DatabaseType::MySql | DatabaseType::MariaDB => {
                return Err(DbError::ConnectionError {
                    message: "MySQL/MariaDB support is not enabled".to_string(),
                });
            }
            // --- SQL Server ---
            #[cfg(feature = "sqlserver")]
            DatabaseType::SqlServer => {
                let runtime = tokio::runtime::Runtime::new().map_err(|e| {
                    DbError::ConnectionError {
                        message: e.to_string(),
                    }
                })?;
                let client = Self::connect_sqlserver(&self.config, &runtime)?;
                DbConnection::SqlServer { client, runtime }
            }
            #[cfg(not(feature = "sqlserver"))]
            DatabaseType::SqlServer => {
                return Err(DbError::ConnectionError {
                    message: "SQL Server support is not enabled".to_string(),
                });
            }
            // --- DB2 ---
            #[cfg(feature = "db2")]
            DatabaseType::Db2 => {
                let env: &'static mut odbc_api::Environment = Box::leak(Box::new(
                    odbc_api::Environment::new().map_err(|e| DbError::ConnectionError {
                        message: format!("Failed to create ODBC environment: {e}"),
                    })?,
                ));
                let conn = Self::connect_db2(&self.config, env)?;
                DbConnection::Db2 { conn }
            }
            #[cfg(not(feature = "db2"))]
            DatabaseType::Db2 => {
                return Err(DbError::ConnectionError {
                    message: "DB2 support is not enabled".to_string(),
                });
            }
        };

        *self.conn.lock().unwrap() = Some(conn);
        Ok(())
    }

    pub fn disconnect(&self) -> Result<(), DbError> {
        let mut guard = self.conn.lock().unwrap();
        guard.take().ok_or(DbError::NotConnected)?;
        Ok(())
    }

    pub fn status(&self) -> ConnStatus {
        self.conn
            .lock()
            .unwrap()
            .as_ref()
            .map_or(ConnStatus::Disconnected, |_| ConnStatus::Connected)
    }

    // -- list_tables -------------------------------------------------------

    pub fn list_tables(&self) -> Result<Vec<TableInfo>, DbError> {
        let mut guard = self.conn.lock().unwrap();
        let conn = guard.as_mut().ok_or(DbError::NotConnected)?;
        match conn {
            #[cfg(feature = "sqlite")]
            DbConnection::Sqlite(c) => Self::list_tables_sqlite(c),
            #[cfg(feature = "postgres")]
            DbConnection::Postgres { client, runtime } => {
                Self::list_tables_postgres(client, runtime)
            }
            #[cfg(feature = "mysql")]
            DbConnection::MySql { conn, runtime, .. } => Self::list_tables_mysql(conn, runtime),
            #[cfg(feature = "sqlserver")]
            DbConnection::SqlServer { client, runtime } => {
                Self::list_tables_sqlserver(client, runtime)
            }
            #[cfg(feature = "db2")]
            DbConnection::Db2 { conn } => Self::list_tables_db2(conn),
        }
    }

    // -- current_database --------------------------------------------------

    pub fn current_database(&self) -> Result<String, DbError> {
        let sql = match self.config.db_type {
            DatabaseType::Postgres => "SELECT current_database()",
            DatabaseType::MySql | DatabaseType::MariaDB => "SELECT DATABASE()",
            DatabaseType::SqlServer => "SELECT DB_NAME()",
            _ => return Ok("main".to_string()),
        };
        let result = self.execute_query(sql)?;
        let val = result.rows.first()
            .and_then(|r| r.first())
            .map(|cv| format!("{}", cv))
            .unwrap_or_default();
        Ok(val)
    }

    // -- list_databases ----------------------------------------------------

    pub fn list_databases(&self) -> Result<Vec<String>, DbError> {
        let sql = match self.config.db_type {
            DatabaseType::Postgres =>
                "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname",
            DatabaseType::MySql | DatabaseType::MariaDB => "SHOW DATABASES",
            DatabaseType::SqlServer =>
                "SELECT name FROM sys.databases ORDER BY name",
            _ => return Ok(vec!["main".to_string()]),
        };
        let result = self.execute_query(sql)?;
        Ok(result.rows.iter().filter_map(|r| {
            r.first().map(|cv| format!("{}", cv))
        }).collect())
    }

    // -- quick_view --------------------------------------------------------

    pub fn quick_view(&self, table_name: &str, row_limit: u32) -> Result<QueryResult, DbError> {
        let q = self.config.db_type.quote_char();
        let sql = format!("SELECT * FROM {q}{table_name}{q} LIMIT {row_limit}");
        self.execute_query(&sql)
    }

    // -- execute_query ------------------------------------------------------

    pub fn execute_query(&self, sql: &str) -> Result<QueryResult, DbError> {
        let start = Instant::now();

        let mut guard = self.conn.lock().unwrap();
        let conn = guard.as_mut().ok_or(DbError::NotConnected)?;

        match conn {
            #[cfg(feature = "sqlite")]
            DbConnection::Sqlite(c) => Self::execute_query_sqlite(c, sql, start),
            #[cfg(feature = "postgres")]
            DbConnection::Postgres { client, runtime } => {
                Self::execute_query_postgres(client, runtime, sql, start)
            }
            #[cfg(feature = "mysql")]
            DbConnection::MySql { conn, runtime, .. } => {
                Self::execute_query_mysql(conn, runtime, sql, start)
            }
            #[cfg(feature = "sqlserver")]
            DbConnection::SqlServer { client, runtime } => {
                Self::execute_query_sqlserver(client, runtime, sql, start)
            }
            #[cfg(feature = "db2")]
            DbConnection::Db2 { conn } => Self::execute_query_db2(conn, sql, start),
        }
        .inspect(|_| self.log_query(sql, start))
    }

    fn log_query(&self, sql: &str, start: Instant) {
        if let Some(ref log_path) = self.config.log_path {
            let elapsed = start.elapsed().as_millis();

            // Build ISO-8601 timestamp without chrono
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default();
            let secs = now.as_secs();
            // Simple UTC date-time (no timezone)
            let _days = secs / 86400;
            let time_secs = secs % 86400;
            let ts = format!("{}T{:02}:{:02}:{:02}Z",
                date_from_timestamp(secs),
                time_secs / 3600, (time_secs % 3600) / 60, time_secs % 60);

            if let Some(parent) = std::path::Path::new(log_path).parent() {
                let _ = fs::create_dir_all(parent);
            }
            let line = format!("{} | {} | {}ms\n", ts, sql.replace('\n', " "), elapsed);
            if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(log_path) {
                let _ = write!(file, "{}", line);
            }
        }
    }
}

// Helper to convert days since epoch to ISO date string
fn date_from_timestamp(secs: u64) -> String {
    let days = secs / 86400;
    let mut y = 1970i64;
    let mut remaining = days as i64;
    loop {
        let days_in_year = if is_leap(y) { 366 } else { 365 };
        if remaining < days_in_year { break; }
        remaining -= days_in_year;
        y += 1;
    }
    let m = [31, if is_leap(y) { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut month = 1;
    for &days_in_month in &m {
        if remaining < days_in_month { break; }
        remaining -= days_in_month;
        month += 1;
    }
    format!("{:04}-{:02}-{:02}", y, month, remaining + 1)
}

fn is_leap(year: i64) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

// ===========================================================================
//  Connection helpers
// ===========================================================================

impl DatabaseManager {
    #[cfg(feature = "mysql")]
    fn build_mysql_opts_with_tunnel(
        config: &DatabaseConfig,
        runtime: &tokio::runtime::Runtime,
    ) -> Result<(mysql_async::Opts, Option<SshTunnel>), DbError> {
        let (host, port, tunnel) = if config.use_ssh_tunnel {
            let ssh_host = config.ssh_host.clone().ok_or_else(|| DbError::ConnectionError {
                message: "SSH tunnel enabled but ssh_host is empty".to_string(),
            })?;
            let ssh_port = config.ssh_port.unwrap_or(22) as u16;
            let ssh_user = config.ssh_username.clone().unwrap_or_default();
            let ssh_pass = config.ssh_password.clone().unwrap_or_default();
            let target_host = config.host.clone().unwrap_or_else(|| "127.0.0.1".to_string());
            let target_port = config.port.unwrap_or(3306) as u16;

            let tunnel = runtime.block_on(SshTunnel::open(
                ssh_host,
                ssh_port,
                ssh_user,
                ssh_pass,
                target_host,
                target_port,
            ))?;
            ("127.0.0.1".to_string(), tunnel.local_port() as u32, Some(tunnel))
        } else {
            (
                config.host.clone().unwrap_or_else(|| "127.0.0.1".to_string()),
                config.port.unwrap_or(3306),
                None,
            )
        };

        let builder = mysql_async::OptsBuilder::default()
            .ip_or_hostname(host)
            .tcp_port(port as u16)
            .user(config.username.clone())
            .pass(config.password.clone())
            .db_name(config.database.clone());
        Ok((builder.into(), tunnel))
    }

    #[cfg(feature = "sqlserver")]
    fn connect_sqlserver(
        config: &DatabaseConfig,
        runtime: &tokio::runtime::Runtime,
    ) -> Result<
        tiberius::Client<tokio_util::compat::Compat<tokio::net::TcpStream>>,
        DbError,
    > {
        use tokio_util::compat::TokioAsyncWriteCompatExt;

        let host = config.host.as_deref().unwrap_or("localhost");
        let port = config.port.unwrap_or(1433);
        let addr = format!("{host}:{port}");

        let mut tiberius_config = tiberius::Config::new();
        tiberius_config.host(host);
        tiberius_config.port(port as u16);
        tiberius_config.authentication(tiberius::AuthMethod::sql_server(
            config.username.as_deref().unwrap_or(""),
            config.password.as_deref().unwrap_or(""),
        ));
        if let Some(db) = &config.database {
            tiberius_config.database(db);
        }

        let tcp = runtime
            .block_on(tokio::net::TcpStream::connect(&addr))
            .map_err(|e| DbError::ConnectionError {
                message: format!("Failed to connect to SQL Server: {e}"),
            })?;
        tcp.set_nodelay(true).ok();

        let client = runtime
            .block_on(tiberius::Client::connect(tiberius_config, tcp.compat_write()))
            .map_err(|e| DbError::ConnectionError {
                message: format!("SQL Server auth failed: {e}"),
            })?;

        Ok(client)
    }

    #[cfg(feature = "db2")]
    fn connect_db2(
        config: &DatabaseConfig,
        env: &'static odbc_api::Environment,
    ) -> Result<odbc_api::Connection<'static>, DbError> {
        let host = config.host.as_deref().unwrap_or("localhost");
        let port = config.port.unwrap_or(50000);
        let db = config.database.as_deref().unwrap_or("mydb");
        let user = config.username.as_deref().unwrap_or("");
        let pass = config.password.as_deref().unwrap_or("");

        let conn_str = format!(
            "DRIVER={{IBM DB2 ODBC DRIVER}};DATABASE={db};HOSTNAME={host};PORT={port};PROTOCOL=TCPIP;UID={user};PWD={pass};"
        );

        let conn = env
            .connect_with_connection_string(&conn_str, odbc_api::ConnectionOptions::default())
            .map_err(|e| DbError::ConnectionError {
                message: format!("Failed to connect to DB2: {e}"),
            })?;

        Ok(conn)
    }

    fn inject_credentials_into_url(&self) -> String {
        let mut url = self.config.url.clone();
        if url.contains('@') {
            return url;
        }
        if let (Some(user), Some(pass)) = (&self.config.username, &self.config.password) {
            if let Some(pos) = url.find("://") {
                let insert_at = pos + 3;
                url.insert_str(insert_at, &format!("{user}:{pass}@"));
            }
        } else if let Some(user) = &self.config.username {
            if let Some(pos) = url.find("://") {
                let insert_at = pos + 3;
                url.insert_str(insert_at, &format!("{user}@"));
            }
        }
        url
    }
}

// ===========================================================================
//  SQLite helpers
// ===========================================================================

#[cfg(feature = "sqlite")]
impl DatabaseManager {
    fn list_tables_sqlite(conn: &mut rusqlite::Connection) -> Result<Vec<TableInfo>, DbError> {
        let table_names: Vec<String> = {
            let mut stmt = conn
                .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
                .map_err(|e| DbError::QueryError {
                    message: e.to_string(),
                })?;
            let names: Vec<String> = stmt
                .query_map([], |row| row.get(0))
                .map_err(|e| DbError::QueryError {
                    message: e.to_string(),
                })?
                .filter_map(|r| r.ok())
                .collect();
            names
        };

        let mut tables = Vec::new();
        for name in table_names {
            let columns = Self::get_columns_sqlite(conn, &name)?;
            let row_count = conn
                .query_row(&format!("SELECT COUNT(*) FROM \"{name}\""), [], |row| {
                    row.get::<_, i64>(0)
                })
                .ok()
                .map(|c| c as u64);

            tables.push(TableInfo {
                name,
                schema: "main".to_string(),
                columns,
                row_count,
            });
        }
        Ok(tables)
    }

    fn get_columns_sqlite(
        conn: &mut rusqlite::Connection,
        table: &str,
    ) -> Result<Vec<ColumnInfo>, DbError> {
        let mut stmt = conn
            .prepare(&format!("PRAGMA table_info(\"{table}\")"))
            .map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })?;

        let columns = stmt
            .query_map([], |row| {
                Ok(ColumnInfo {
                    name: row.get(1)?,
                    data_type: row.get::<_, String>(2).unwrap_or_default(),
                    nullable: row.get::<_, i32>(3).unwrap_or(1) != 0,
                    is_primary_key: row.get::<_, i32>(5).unwrap_or(0) != 0,
                })
            })
            .map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })?
            .filter_map(|r| r.ok())
            .collect();

        Ok(columns)
    }

    fn execute_query_sqlite(
        conn: &mut rusqlite::Connection,
        sql: &str,
        start: Instant,
    ) -> Result<QueryResult, DbError> {
        use rusqlite::types::ValueRef;

        let stripped = strip_leading_comments(sql);
        let sql_upper = stripped.to_uppercase();
        let is_query = sql_upper.starts_with("SELECT")
            || sql_upper.starts_with("PRAGMA")
            || sql_upper.starts_with("WITH");

        if is_query {
            let mut stmt = conn.prepare(sql).map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })?;

            let col_count = stmt.column_count();
            let columns: Vec<ColumnInfo> = (0..col_count)
                .map(|i| ColumnInfo {
                is_primary_key: false,
                    name: stmt.column_name(i).unwrap_or("?").to_string(),
                    data_type: String::new(),
                    nullable: true,
                })
                .collect();

            let rows: Vec<Vec<CellValue>> = {
                let mapped = stmt
                    .query_map([], |row| {
                        let mut values = Vec::with_capacity(col_count);
                        for i in 0..col_count {
                            let val = match row.get_ref(i).unwrap_or(ValueRef::Null) {
                                ValueRef::Null => CellValue::Null,
                                ValueRef::Integer(v) => CellValue::Int(v),
                                ValueRef::Real(v) => CellValue::Float(v),
                                ValueRef::Text(v) => CellValue::Text(
                                    String::from_utf8_lossy(v).to_string(),
                                ),
                                ValueRef::Blob(v) => CellValue::Blob(v.to_vec()),
                            };
                            values.push(val);
                        }
                        Ok(values)
                    })
                    .map_err(|e| DbError::QueryError {
                        message: e.to_string(),
                    })?;
                mapped.filter_map(|r| r.ok()).collect()
            };

            let elapsed = start.elapsed().as_millis() as u64;
            Ok(QueryResult {
                columns,
                rows,
                rows_affected: 0,
                execution_time_ms: elapsed,
            })
        } else {
            let rows_affected = conn.execute(sql, []).map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })? as u64;

            let elapsed = start.elapsed().as_millis() as u64;
            Ok(QueryResult {
                columns: vec![],
                rows: vec![],
                rows_affected,
                execution_time_ms: elapsed,
            })
        }
    }
}

// ===========================================================================
//  PostgreSQL helpers
// ===========================================================================

#[cfg(feature = "postgres")]
impl DatabaseManager {
    fn list_tables_postgres(
        client: &tokio_postgres::Client,
        runtime: &tokio::runtime::Runtime,
    ) -> Result<Vec<TableInfo>, DbError> {
        let rows = runtime
            .block_on(client.query(
                "SELECT table_schema, table_name \
                 FROM information_schema.tables \
                 WHERE table_type = 'BASE TABLE' \
                   AND table_schema NOT IN ('pg_catalog', 'information_schema') \
                 ORDER BY table_schema, table_name",
                &[],
            ))
            .map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })?;

        let mut tables = Vec::new();
        for row in rows {
            let schema: String = row.get(0);
            let name: String = row.get(1);
            let columns = Self::get_columns_postgres(client, runtime, &schema, &name)?;
            let row_count = runtime
                .block_on(client.query_one(
                    &format!("SELECT COUNT(*) FROM \"{schema}\".\"{name}\""),
                    &[],
                ))
                .ok()
                .map(|r| r.get::<_, i64>(0) as u64);

            tables.push(TableInfo {
                name,
                schema,
                columns,
                row_count,
            });
        }
        Ok(tables)
    }

    fn get_columns_postgres(
        client: &tokio_postgres::Client,
        runtime: &tokio::runtime::Runtime,
        schema: &str,
        table: &str,
    ) -> Result<Vec<ColumnInfo>, DbError> {
        let rows = runtime
            .block_on(client.query(
                "SELECT column_name, data_type, is_nullable \
                 FROM information_schema.columns \
                 WHERE table_schema = $1 AND table_name = $2 \
                 ORDER BY ordinal_position",
                &[&schema, &table],
            ))
            .map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })?;

        let columns = rows
            .iter()
            .map(|row| {
                let nullable: String = row.get(2);
                ColumnInfo {
                is_primary_key: false,
                    name: row.get(0),
                    data_type: row.get(1),
                    nullable: nullable == "YES",
                }
            })
            .collect();

        Ok(columns)
    }

    fn execute_query_postgres(
        client: &tokio_postgres::Client,
        runtime: &tokio::runtime::Runtime,
        sql: &str,
        start: Instant,
    ) -> Result<QueryResult, DbError> {
        use tokio_postgres::types::Type;

        let stripped = strip_leading_comments(sql);
        let sql_upper = stripped.to_uppercase();
        let is_query = sql_upper.starts_with("SELECT")
            || sql_upper.starts_with("WITH")
            || sql_upper.starts_with("EXPLAIN")
            || sql_upper.starts_with("SHOW");

        if is_query {
            let result = runtime
                .block_on(client.query(sql, &[]))
                .map_err(|e| DbError::QueryError {
                    message: e.to_string(),
                })?;

            if result.is_empty() {
                let elapsed = start.elapsed().as_millis() as u64;
                return Ok(QueryResult {
                    columns: vec![],
                    rows: vec![],
                    rows_affected: 0,
                    execution_time_ms: elapsed,
                });
            }

            let col_count = result[0].len();
            let columns: Vec<ColumnInfo> = (0..col_count)
                .map(|i| ColumnInfo {
                is_primary_key: false,
                    name: result[0].columns()[i].name().to_string(),
                    data_type: result[0].columns()[i].type_().to_string(),
                    nullable: true,
                })
                .collect();

            let rows: Vec<Vec<CellValue>> = result
                .iter()
                .map(|row| {
                    let mut values = Vec::with_capacity(col_count);
                    for i in 0..col_count {
                        let val: CellValue = match row.columns()[i].type_() {
                            &Type::BOOL => {
                                let v: bool = row.get(i);
                                CellValue::Int(if v { 1 } else { 0 })
                            }
                            &Type::INT2 | &Type::INT4 => {
                                let v: i32 = row.get(i);
                                CellValue::Int(v as i64)
                            }
                            &Type::INT8 => {
                                let v: i64 = row.get(i);
                                CellValue::Int(v)
                            }
                            &Type::FLOAT4 => {
                                let v: f32 = row.get(i);
                                CellValue::Float(v as f64)
                            }
                            &Type::FLOAT8 => {
                                let v: f64 = row.get(i);
                                CellValue::Float(v)
                            }
                            &Type::TEXT
                            | &Type::VARCHAR
                            | &Type::BPCHAR
                            | &Type::NAME => {
                                let v: Option<&str> = row.try_get(i).ok();
                                CellValue::Text(v.unwrap_or("").to_string())
                            }
                            &Type::BYTEA => {
                                let v: Vec<u8> = row.get(i);
                                CellValue::Blob(v)
                            }
                            &Type::NUMERIC => {
                                let v: Option<&str> = row.try_get(i).ok();
                                CellValue::Text(v.unwrap_or("").to_string())
                            }
                            _ => {
                                let v: String = row.get(i);
                                CellValue::Text(v)
                            }
                        };
                        values.push(val);
                    }
                    Ok(values)
                })
                .filter_map(|r: Result<Vec<CellValue>, DbError>| r.ok())
                .collect();

            let elapsed = start.elapsed().as_millis() as u64;
            Ok(QueryResult {
                columns,
                rows,
                rows_affected: 0,
                execution_time_ms: elapsed,
            })
        } else {
            let rows_affected = runtime
                .block_on(client.execute(sql, &[]))
                .map_err(|e| DbError::QueryError {
                    message: e.to_string(),
                })? as u64;

            let elapsed = start.elapsed().as_millis() as u64;
            Ok(QueryResult {
                columns: vec![],
                rows: vec![],
                rows_affected,
                execution_time_ms: elapsed,
            })
        }
    }
}

// ===========================================================================
//  MySQL / MariaDB helpers
// ===========================================================================

#[cfg(feature = "mysql")]
impl DatabaseManager {
    fn list_tables_mysql(
        conn: &mut mysql_async::Conn,
        runtime: &tokio::runtime::Runtime,
    ) -> Result<Vec<TableInfo>, DbError> {
        use mysql_async::prelude::Queryable;

        let db_name: Option<String> = runtime
            .block_on(conn.query_first("SELECT DATABASE()"))
            .map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })?;

        let rows: Vec<mysql_async::Row> = runtime
            .block_on(conn.query("SHOW TABLES"))
            .map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })?;

        let table_names: Vec<String> = rows
            .iter()
            .filter_map(|row| row.get::<String, usize>(0))
            .collect();

        let mut tables = Vec::new();
        for name in table_names {
            let columns = Self::get_columns_mysql(conn, runtime, &name)?;
            let row_count: Option<u64> = runtime
                .block_on(conn.query_first(format!("SELECT COUNT(*) FROM `{name}`")))
                .ok()
                .flatten()
                .and_then(|v: i64| Some(v as u64));

            tables.push(TableInfo {
                name,
                schema: db_name.clone().unwrap_or_default(),
                columns,
                row_count,
            });
        }
        Ok(tables)
    }

    fn get_columns_mysql(
        conn: &mut mysql_async::Conn,
        runtime: &tokio::runtime::Runtime,
        table: &str,
    ) -> Result<Vec<ColumnInfo>, DbError> {
        use mysql_async::prelude::Queryable;

        let rows: Vec<mysql_async::Row> = runtime
            .block_on(conn.query(format!("SHOW COLUMNS FROM `{table}`")))
            .map_err(|e| DbError::QueryError {
                message: e.to_string(),
            })?;

        let columns = rows
            .iter()
            .map(|row| ColumnInfo {
                is_primary_key: false,
                name: row.get::<String, usize>(0).unwrap_or_default(),
                data_type: row.get::<String, usize>(1).unwrap_or_default(),
                nullable: row
                    .get::<String, usize>(2)
                    .map(|s| s == "YES")
                    .unwrap_or(true),
            })
            .collect();

        Ok(columns)
    }

    fn execute_query_mysql(
        conn: &mut mysql_async::Conn,
        runtime: &tokio::runtime::Runtime,
        sql: &str,
        start: Instant,
    ) -> Result<QueryResult, DbError> {
        use mysql_async::prelude::Queryable;
        use std::fmt::Write;

        let stripped = strip_leading_comments(sql);
        let sql_upper = stripped.to_uppercase();
        let is_query = sql_upper.starts_with("SELECT")
            || sql_upper.starts_with("SHOW")
            || sql_upper.starts_with("DESCRIBE")
            || sql_upper.starts_with("EXPLAIN")
            || sql_upper.starts_with("WITH");

        if is_query {
            let result = runtime
                .block_on(async {
                    let mut query = conn.query_iter(sql).await.map_err(|e| {
                        DbError::QueryError {
                            message: e.to_string(),
                        }
                    })?;

                    let columns: Vec<ColumnInfo> = query
                        .columns()
                        .map(|cols| {
                            cols.iter()
                                .map(|c| {
                                    let mut type_str = String::new();
                                    let _ = write!(type_str, "{:?}", c.column_type());
                                    ColumnInfo {
                is_primary_key: false,
                                        name: c.name_str().to_string(),
                                        data_type: type_str,
                                        nullable: false,
                                    }
                                })
                                .collect()
                        })
                        .unwrap_or_default();

                    let mut rows: Vec<Vec<CellValue>> = Vec::new();
                    while let Some(row) = query.next().await.map_err(|e| {
                        DbError::QueryError {
                            message: e.to_string(),
                        }
                    })? {
                        let mut values = Vec::new();
                        for i in 0..row.len() {
                            let val = match row.as_ref(i) {
                                None | Some(mysql_async::Value::NULL) => CellValue::Null,
                                Some(mysql_async::Value::Int(v)) => CellValue::Int(*v as i64),
                                Some(mysql_async::Value::UInt(v)) => CellValue::Int(*v as i64),
                                Some(mysql_async::Value::Float(v)) => CellValue::Float(*v as f64),
                                Some(mysql_async::Value::Double(v)) => CellValue::Float(*v),
                                Some(mysql_async::Value::Bytes(v)) => {
                                    CellValue::Text(String::from_utf8_lossy(v.as_slice()).to_string())
                                }
                                Some(mysql_async::Value::Date(..))
                                | Some(mysql_async::Value::Time(..)) => {
                                    CellValue::Text(row.get::<String, usize>(i).unwrap_or_default())
                                }
                            };
                            values.push(val);
                        }
                        rows.push(values);
                    }

                    Ok::<_, DbError>((columns, rows))
                })
                .map_err(|e| DbError::QueryError {
                    message: e.to_string(),
                })?;

            let (columns, rows) = result;
            let elapsed = start.elapsed().as_millis() as u64;
            Ok(QueryResult {
                columns,
                rows,
                rows_affected: 0,
                execution_time_ms: elapsed,
            })
        } else {
            let rows_affected = runtime
                .block_on(conn.exec(sql, ()))
                .map_err(|e| DbError::QueryError {
                    message: e.to_string(),
                })
                .map(|_r: Vec<mysql_async::Row>| 0u64)?;

            let elapsed = start.elapsed().as_millis() as u64;
            Ok(QueryResult {
                columns: vec![],
                rows: vec![],
                rows_affected,
                execution_time_ms: elapsed,
            })
        }
    }
}

// ===========================================================================
//  SQL Server (tiberius) helpers
// ===========================================================================

#[cfg(feature = "sqlserver")]
impl DatabaseManager {
    fn list_tables_sqlserver(
        client: &mut tiberius::Client<tokio_util::compat::Compat<tokio::net::TcpStream>>,
        runtime: &tokio::runtime::Runtime,
    ) -> Result<Vec<TableInfo>, DbError> {
        let results = runtime
            .block_on(async {
                let rows = client
                    .query(
                        "SELECT TABLE_SCHEMA, TABLE_NAME \
                         FROM INFORMATION_SCHEMA.TABLES \
                         WHERE TABLE_TYPE = 'BASE TABLE' \
                         ORDER BY TABLE_SCHEMA, TABLE_NAME",
                        &[],
                    )
                    .await
                    .map_err(|e| DbError::QueryError {
                        message: e.to_string(),
                    })?;
                rows.into_results()
                    .await
                    .map_err(|e| DbError::QueryError {
                        message: e.to_string(),
                    })
            })?;

        let mut tables = Vec::new();
        for batch in results {
            for row in &batch {
                let schema: String = match row.try_get::<&str, _>(0) {
                    Ok(Some(v)) => v.to_string(),
                    _ => String::new(),
                };
                let name: String = match row.try_get::<&str, _>(1) {
                    Ok(Some(v)) => v.to_string(),
                    _ => continue,
                };
                let columns =
                    Self::get_columns_sqlserver(client, runtime, &schema, &name)?;
                let row_count =
                    Self::table_row_count_sqlserver(client, runtime, &schema, &name);
                tables.push(TableInfo {
                    name,
                    schema,
                    columns,
                    row_count,
                });
            }
        }
        Ok(tables)
    }

    fn get_columns_sqlserver(
        client: &mut tiberius::Client<tokio_util::compat::Compat<tokio::net::TcpStream>>,
        runtime: &tokio::runtime::Runtime,
        schema: &str,
        table: &str,
    ) -> Result<Vec<ColumnInfo>, DbError> {
        let results = runtime
            .block_on(async {
                let rows = client
                    .query(
                        "SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE \
                         FROM INFORMATION_SCHEMA.COLUMNS \
                         WHERE TABLE_SCHEMA = @P1 AND TABLE_NAME = @P2 \
                         ORDER BY ORDINAL_POSITION",
                        &[&schema, &table],
                    )
                    .await
                    .map_err(|e| DbError::QueryError {
                        message: e.to_string(),
                    })?;
                rows.into_results()
                    .await
                    .map_err(|e| DbError::QueryError {
                        message: e.to_string(),
                    })
            })?;

        let mut columns = Vec::new();
        for batch in results {
            for row in &batch {
                let name: String = match row.try_get::<&str, _>(0) {
                    Ok(Some(v)) => v.to_string(),
                    _ => continue,
                };
                let data_type: String = row
                    .try_get::<&str, _>(1)
                    .ok()
                    .flatten()
                    .unwrap_or("")
                    .to_string();
                let nullable: bool = row
                    .try_get::<&str, _>(2)
                    .ok()
                    .flatten()
                    .unwrap_or("NO")
                    == "YES";
                columns.push(ColumnInfo {
                is_primary_key: false,
                    name,
                    data_type,
                    nullable,
                });
            }
        }
        Ok(columns)
    }

    fn table_row_count_sqlserver(
        client: &mut tiberius::Client<tokio_util::compat::Compat<tokio::net::TcpStream>>,
        runtime: &tokio::runtime::Runtime,
        schema: &str,
        table: &str,
    ) -> Option<u64> {
        runtime
            .block_on(async {
                let rows = client
                    .query(
                        &format!("SELECT COUNT(*) FROM \"{schema}\".\"{table}\""),
                        &[],
                    )
                    .await
                    .ok()?;
                let results = rows.into_results().await.ok()?;
                let batch = results.first()?;
                let row = batch.first()?;
                row.get::<i32, _>(0).map(|c| c as u64)
            })
    }

    fn execute_query_sqlserver(
        client: &mut tiberius::Client<tokio_util::compat::Compat<tokio::net::TcpStream>>,
        runtime: &tokio::runtime::Runtime,
        sql: &str,
        start: Instant,
    ) -> Result<QueryResult, DbError> {
        let stripped = strip_leading_comments(sql);
        let sql_upper = stripped.to_uppercase();
        let is_query = sql_upper.starts_with("SELECT")
            || sql_upper.starts_with("WITH")
            || sql_upper.starts_with("EXEC")
            || sql_upper.starts_with("EXECUTE")
            || sql_upper.starts_with("PRINT");

        if is_query {
            let results = runtime
                .block_on(async {
                    let rows = client.query(sql, &[]).await.map_err(|e| {
                        DbError::QueryError {
                            message: e.to_string(),
                        }
                    })?;
                    rows.into_results()
                        .await
                        .map_err(|e| DbError::QueryError {
                            message: e.to_string(),
                        })
                })?;

            if results.is_empty() || results[0].is_empty() {
                let elapsed = start.elapsed().as_millis() as u64;
                return Ok(QueryResult {
                    columns: vec![],
                    rows: vec![],
                    rows_affected: 0,
                    execution_time_ms: elapsed,
                });
            }

            // Get column names from first row
            let col_count = results[0][0].len();
            let columns: Vec<ColumnInfo> = (0..col_count)
                .map(|i| ColumnInfo {
                is_primary_key: false,
                    name: format!("col_{i}"),
                    data_type: String::new(),
                    nullable: true,
                })
                .collect();

            let rows: Vec<Vec<CellValue>> = results
                .iter()
                .flat_map(|batch| batch.iter())
                .map(|row| {
                    let mut values = Vec::with_capacity(col_count);
                    for i in 0..col_count {
                        let val = sqlserver_cell(row, i);
                        values.push(val);
                    }
                    values
                })
                .collect();

            let elapsed = start.elapsed().as_millis() as u64;
            Ok(QueryResult {
                columns,
                rows,
                rows_affected: 0,
                execution_time_ms: elapsed,
            })
        } else {
            let result = runtime
                .block_on(async { client.execute(sql, &[]).await })
                .map_err(|e| DbError::QueryError {
                    message: e.to_string(),
                })?;

            let elapsed = start.elapsed().as_millis() as u64;
            Ok(QueryResult {
                columns: vec![],
                rows: vec![],
                rows_affected: result.rows_affected().last().copied().unwrap_or(0),
                execution_time_ms: elapsed,
            })
        }
    }
}

/// Extract a cell value from a tiberius Row using text representation.
#[cfg(feature = "sqlserver")]
fn sqlserver_cell(row: &tiberius::Row, i: usize) -> CellValue {
    match row.try_get::<&str, _>(i) {
        Ok(Some(v)) => CellValue::Text(v.to_string()),
        Ok(None) => CellValue::Null,
        Err(_) => CellValue::Null,
    }
}

// ===========================================================================
//  DB2 (ODBC) helpers
// ===========================================================================

#[cfg(feature = "db2")]
impl DatabaseManager {
    fn list_tables_db2(
        _conn: &odbc_api::Connection<'static>,
    ) -> Result<Vec<TableInfo>, DbError> {
        Ok(Vec::new())
    }

    fn execute_query_db2(
        conn: &odbc_api::Connection<'static>,
        sql: &str,
        start: Instant,
    ) -> Result<QueryResult, DbError> {
        conn.execute(sql, ()).map_err(|e| DbError::QueryError {
            message: format!("DB2 query failed: {e}"),
        })?;
        let elapsed = start.elapsed().as_millis() as u64;
        Ok(QueryResult {
            columns: vec![],
            rows: vec![],
            rows_affected: 0,
            execution_time_ms: elapsed,
        })
    }
}
