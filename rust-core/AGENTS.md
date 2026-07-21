# rust-core/

Rust database engine — multi-backend SQL + schema browsing, exported via uniffi.
**Core layer — ALL business logic lives here. UI layer must not contain any of this.**

## CORE RESPONSIBILITIES (MANDATORY)

**Rust Core MUST handle:**
- 数据库连接管理、查询执行、元数据获取
- SQL 解析、分类、格式化、上下文分析（`sql/parser.rs`）
- 自动补全上下文分析（`analyze_sql_context`）
- 控制语句识别（SET/USE/BEGIN/COMMIT/ROLLBACK）
- 连接配置持久化（`ConnectionStore`/`QueryStore`）
- 多后端差异封装（各数据库方言在 core 内部处理，UI 端不分后端）

**FFI export boundary (`ffi.rs`):**
- 所有 UI 可调用方法必须通过 `ffi.rs` 导出
- 不暴露内部类型，只导出 uniffi-compatible 类型
- 新平台接入只需实现 `Generated/redb_core.swift` 对应的绑定

## STRUCTURE

```
rust-core/src/
├── lib.rs              # uniffi scaffolding + pub re-exports
├── ffi.rs              # #[uniffi::export] FFI wrapper over inner types
├── db/
│   ├── mod.rs          # re-exports DatabaseManager
│   └── connection.rs   # DbConnection enum + per-backend impl blocks
├── sql/
│   ├── mod.rs
│   └── parser.rs       # sqlparser wrapper: classify_sql(), QueryType enum
├── store/
│   └── mod.rs          # ConnectionStore + QueryStore (JSON-file persistence)
├── types/
│   └── mod.rs          # All shared types (CellValue, QueryResult, TableInfo, DbError, etc.)
└── build.rs            # empty — uniffi scaffolding in lib.rs
```

## WHERE TO LOOK

| Task | File |
|------|------|
| Add a DB backend | `connection.rs`: new `DbConnection` variant + `impl DatabaseManager` block behind `#[cfg(feature)]` |
| Add FFI export | `ffi.rs`: `#[uniffi::export] impl` on `DatabaseManager` (FFI wrapper) |
| Add shared type | `types/mod.rs`: derive both `serde` and `uniffi` |
| Add persistence | `store/mod.rs`: new store type following `ConnectionStore`/`QueryStore` pattern |
| Add SQL classification | `parser.rs`: new arm in `classify_sql()` match |

## KEY TYPES

- **DbConnection** (enum, private): Sqlite | Postgres | MySql | SqlServer | Db2 — each behind cfg gate
- **DatabaseManager** (inner, connection.rs): actual connect/list/query logic per DB
- **DatabaseManager** (FFI, ffi.rs): `Arc<Mutex<InnerManager>>` — thread-safe uniffi handle
- **DbError**: `thiserror` + `uniffi::Error` — ConnectionError, QueryError, NotConnected
- **CellValue**: Null/Int/Float/Text/Blob — unified cell representation
- **ConnectionStore / QueryStore**: JSON-file persistence with atomic write (.tmp → rename)

## CONVENTIONS (module-level)

- Per-backend methods in separate `#[cfg(feature)] impl DatabaseManager` blocks
- Sync = rusqlite/odbc, Async = tokio runtime created per-connection
- `Arc<Self>` from constructors for uniffi Object pattern
- `conn.lock().unwrap()` — no poisoning recovery (intentional)
- Test file at `tests/integration_test.rs` covers SQLite path only

## ANTI-PATTERNS

- SQL Server columns → `col_{i}` (metadata not read from query result)
- DB2 `list_tables` → returns `Vec::new()` (not implemented)
- `build.rs` empty — uniffi scaffolding lives in `lib.rs`
