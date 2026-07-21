# RedB — AGENTS.md

## Build

```bash
# Rust core (default: sqlite only)
cargo build -p redb-core
cargo build -p redb-core --features all-dbs

# Tests
cargo test -p redb-core

# Full build + Swift bindings
./scripts/build-rust.sh         # release
./scripts/build-rust.sh debug
```

`build-rust.sh` runs `gen-bindings` crate after the Rust build, but **`gen-bindings/` does not exist on disk** and is gitignored. The script will fail until that crate is created. The Xcode project expects `target/release/libredb_core.a`.

## Architecture

- **macOS app** (SwiftUI, macOS 13+, Swift 5.9) in `swift-ui/`. Entry: `RedBApp.swift` → `NavigationSplitView` (Sidebar | TableBrowser | SQLQueryView).
- **Rust core** (`redb-core`) in `rust-core/`. Exposes `DatabaseManager` via UniFFI 0.28. Supports SQLite (default), PostgreSQL, MySQL, SQL Server, DB2 — each behind a Cargo feature.
- **XcodeGen** project spec at `swift-ui/project.yml`. Xcode project is pre-generated.
- **Swift FFI bridge** (`RustBridge.swift`) dispatches all calls to `com.redb.ffi` background queue.
- **UniFFI-generated Swift bindings** live in `swift-ui/RedB/Generated/` (gitignored).

## Cargo features

`all-dbs` does **not** include `db2` — it only enables: `sqlite`, `postgres`, `mysql`, `sqlserver`.

## Tests

Integration tests in `rust-core/tests/integration_test.rs` test SQLite connect/disconnect/query lifecycle. Unit tests in `rust-core/src/store/mod.rs` test ConnectionStore serialization. All run with `cargo test -p redb-core`.

## Project structure

| Path | Purpose |
|------|---------|
| `rust-core/src/ffi.rs` | UniFFI-exported `DatabaseManager` (Arc<Mutex<InnerManager>>), free function `create_database_manager` |
| `rust-core/src/db/connection.rs` | Internal `DbConnection` enum, one variant per DB backend with feature gates |
| `rust-core/src/store/mod.rs` | `ConnectionStore` + `QueryStore` persisted to JSON, uses atomic tmp+rename writes |
| `rust-core/src/sql/parser.rs` | SQL classification (`sqlparser`) — `QueryType` enum, table extraction from FROM clauses |
| `swift-ui/RedB/Models/DatabaseViewModel.swift` | Central ViewModel: connection profiles, query tabs (max 15), auto-complete, caching |

## Gotchas

- No CI, no formatter/lint configs exist.
- `gen-bindings` workspace member is declared but **not yet created**.
- DB2 feature (`db2`) is excluded from `all-dbs`.
