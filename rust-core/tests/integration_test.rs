use redb_core::db::DatabaseManager;
use redb_core::types::{CellValue, ConnStatus, DatabaseConfig, DatabaseType};

fn create_manager() -> DatabaseManager {
    DatabaseManager::new(DatabaseConfig::new(DatabaseType::Sqlite, ":memory:"))
}

#[test]
fn test_sqlite_connect_and_query() {
    let mgr = create_manager();
    mgr.connect().expect("should connect to in-memory sqlite");
    assert_eq!(mgr.status(), ConnStatus::Connected);

    mgr.execute_query("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        .expect("should create table");
    mgr.execute_query("INSERT INTO test VALUES (1, 'hello')")
        .expect("should insert");

    let result = mgr.execute_query("SELECT * FROM test")
        .expect("should query");
    assert_eq!(result.columns.len(), 2);
    assert_eq!(result.rows.len(), 1);
    assert_eq!(format!("{}", result.rows[0][0]), "1");
    assert_eq!(format!("{}", result.rows[0][1]), "hello");

    mgr.disconnect().expect("should disconnect");
    assert_eq!(mgr.status(), ConnStatus::Disconnected);
}

#[test]
fn test_sqlite_multiple_tables() {
    let mgr = create_manager();
    mgr.connect().unwrap();

    mgr.execute_query("CREATE TABLE users (id INT, name TEXT)").unwrap();
    mgr.execute_query("CREATE TABLE posts (id INT, title TEXT)").unwrap();

    let tables = mgr.list_tables().unwrap();
    assert_eq!(tables.len(), 2);

    let names: Vec<_> = tables.iter().map(|t| t.name.as_str()).collect();
    assert!(names.contains(&"users"));
    assert!(names.contains(&"posts"));
}

#[test]
fn test_sqlite_table_columns() {
    let mgr = create_manager();
    mgr.connect().unwrap();

    mgr.execute_query(
        "CREATE TABLE inventory (id INTEGER PRIMARY KEY, name TEXT NOT NULL, price REAL, qty INTEGER DEFAULT 0)"
    ).unwrap();

    let tables = mgr.list_tables().unwrap();
    let table = &tables[0];
    assert_eq!(table.columns.len(), 4);
    assert_eq!(table.columns[0].name, "id");
    assert_eq!(table.columns[1].name, "name");

    // Verify we can query with real data
    mgr.execute_query("INSERT INTO inventory VALUES (1, 'widget', 9.99, 100)").unwrap();
    let rows = mgr.execute_query("SELECT * FROM inventory").unwrap();
    assert_eq!(rows.rows.len(), 1);
    assert_eq!(rows.rows[0].len(), 4);
}

#[test]
fn test_disconnect_twice_errors() {
    let mgr = create_manager();
    mgr.connect().unwrap();
    mgr.disconnect().unwrap();
    let err = mgr.disconnect().unwrap_err();
    assert!(matches!(err, redb_core::types::DbError::NotConnected));
}

#[test]
fn test_query_without_connect_errors() {
    let mgr = create_manager();
    let err = mgr.execute_query("SELECT 1").unwrap_err();
    assert!(matches!(err, redb_core::types::DbError::NotConnected));
}

#[test]
fn test_sqlite_leading_comment_select() {
    // S5: SELECT preceded by a leading SQL comment must still return rows.
    // Before the fix, the is_query check fails (trimmed starts with "--" not "SELECT")
    // and the row data is silently dropped.
    let mgr = create_manager();
    mgr.connect().unwrap();
    mgr.execute_query("CREATE TABLE test (id INT)").unwrap();
    mgr.execute_query("INSERT INTO test VALUES (99)").unwrap();

    let result = mgr
        .execute_query("-- leading comment\nSELECT * FROM test")
        .expect("comment-prefixed SELECT should work");
    assert_eq!(
        result.rows.len(),
        1,
        "expected 1 row from comment-prefixed SELECT, got {} — is_query detection bug",
        result.rows.len()
    );
    assert_eq!(result.columns.len(), 1);
    assert_eq!(format!("{}", result.rows[0][0]), "99");
}

#[test]
fn test_sqlite_begin_commit_executed_on_connection() {
    // Prove that control statements (BEGIN/COMMIT) actually reach the connection
    // and aren't short-circuited anymore. We can also prove INSERT inside a
    // transaction is committed.
    let mgr = create_manager();
    mgr.connect().unwrap();
    mgr.execute_query("CREATE TABLE tx_test (id INT)").unwrap();

    // BEGIN: now actually sent to SQLite
    mgr.execute_query("BEGIN").expect("BEGIN should execute on connection");
    mgr.execute_query("INSERT INTO tx_test VALUES (42)").unwrap();
    mgr.execute_query("COMMIT").expect("COMMIT should execute on connection");

    // Verify the insert persisted
    let result = mgr.execute_query("SELECT * FROM tx_test").unwrap();
    assert_eq!(result.rows.len(), 1);
    assert_eq!(format!("{}", result.rows[0][0]), "42");
}

#[test]
fn test_sqlite_update_by_pk_parametrized_handles_quote_injection() {
    let mgr = DatabaseManager::new(DatabaseConfig::new(DatabaseType::Sqlite, ":memory:"));
    mgr.connect().unwrap();
    mgr.execute_query("CREATE TABLE u (id INTEGER PRIMARY KEY, name TEXT)").unwrap();
    mgr.execute_query("INSERT INTO u VALUES (1, 'original')").unwrap();

    // A malicious payload that would break naive string interpolation.
    let payload = "Robert'); DROP TABLE u; --";
    let res = mgr
        .update_row_by_primary_key(
            "u",
            "name",
            CellValue::Text(payload.to_string()),
            vec!["id".to_string()],
            vec![CellValue::Int(1)],
        )
        .expect("update should succeed via parametrized binding");
    assert_eq!(res.rows_affected, 1);

    // Table must still exist; payload must be stored verbatim.
    let read = mgr.execute_query("SELECT name FROM u WHERE id = 1").unwrap();
    assert_eq!(read.rows.len(), 1);
    assert_eq!(format!("{}", read.rows[0][0]), payload);
}

#[test]
fn test_sqlite_delete_by_pk_composite() {
    let mgr = DatabaseManager::new(DatabaseConfig::new(DatabaseType::Sqlite, ":memory:"));
    mgr.connect().unwrap();
    mgr.execute_query("CREATE TABLE c (a INT, b TEXT, PRIMARY KEY(a, b))").unwrap();
    mgr.execute_query("INSERT INTO c VALUES (1, 'x'), (1, 'y'), (2, 'x')").unwrap();

    let res = mgr
        .delete_row_by_primary_key(
            "c",
            vec!["a".into(), "b".into()],
            vec![CellValue::Int(1), CellValue::Text("y".into())],
        )
        .unwrap();
    assert_eq!(res.rows_affected, 1);

    let remaining = mgr.execute_query("SELECT COUNT(*) FROM c").unwrap();
    assert_eq!(format!("{}", remaining.rows[0][0]), "2");
}
