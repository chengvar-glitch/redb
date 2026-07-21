# PROJECT KNOWLEDGE BASE

**Generated:** 2026-07-21
**Stack:** Rust → uniffi FFI → SwiftUI (macOS)

## OVERVIEW

Multi-architecture database GUI client. Rust core (redb-core) provides multi-backend SQL query + schema browsing via uniffi-generated FFI bindings. SwiftUI app delivers the macOS frontend.

## DESIGN PRINCIPLES

- **macOS native application**: 严格遵循 Apple Human Interface Guidelines (HIG)。不使用 iOS/跨平台 UI 模式。任何 UI 变更必须以 macOS 原生 App（Finder、Xcode、Mail、Safari）为参考基准。
- **SF Symbols first**: 优先使用系统图标，语义正确（folder=文件浏览，chevron=展开折叠，play=运行执行）。
- **System colors only**: 禁止硬编码 RGB 颜色。使用语义色（`.green`/`.red`/`.orange`/`.accentColor`/`.secondary`/`.tertiary`）确保暗黑模式和无障碍适配。
- **Native controls**: 使用 SwiftUI 原生控件，避免自定义外观偏离 macOS 标准。`.cornerRadius` 用于 iOS，macOS 用平面高亮。
- **Tooltip mandatory**: 所有纯图标按钮必须有 tooltip。Toolbar 和 `.borderless` 按钮使用原生 `NSView.toolTip`（见 `View+Tooltip.swift`）。
- **Animation restraint**: 布局切换用 `.easeInOut(duration: 0.2)`，结果面板用 `.transition(.opacity)`。不过度动画。

## STRUCTURE

```
redb/
├── rust-core/       # DB engine: SQLite|PG|MySQL|SQLServer|DB2, feature-gated
├── swift-ui/        # macOS SwiftUI client (three-column: sidebar/table-browser/query)
├── gen-bindings/    # uniffi-bindgen wrapper to regenerate Swift stubs
└── scripts/         # build-rust.sh: cargo build + uniffi bindgen
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add a new DB backend | `rust-core/src/db/connection.rs` | Add variant to `DbConnection` enum + impl per-backend helpers |
| Add new FFI-exported API | `rust-core/src/ffi.rs` + types in `types/mod.rs` | Must be `#[uniffi::export]` |
| Persist connection configs | `rust-core/src/store/mod.rs` | `ConnectionStore` / `QueryStore` (JSON-file) |
| SQL parsing / classification | `rust-core/src/sql/parser.rs` | Wraps sqlparser crate, classifies DML/DDL |
| Swift view / new screen | `swift-ui/RedB/Views/` | Pattern: SidebarView → TableBrowserView → SQLQueryView |
| Swift-Rust bridge | `swift-ui/RedB/Services/RustBridge.swift` | Dispatches FFI to background queue |
| Regenerate Swift bindings | `scripts/build-rust.sh` | Builds staticlib + runs gen-bindings |
| Shared data types | `rust-core/src/types/mod.rs` | `DatabaseConfig`, `QueryResult`, `CellValue`, `TableInfo` |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `DatabaseManager` (FFI) | struct | `rust-core/src/ffi.rs` | Thread-safe FFI handle |
| `DatabaseManager` (inner) | struct | `rust-core/src/db/connection.rs` | Actual DB logic |
| `DbConnection` | enum | `rust-core/src/db/connection.rs` | Per-backend variant |
| `ConnectionStore` | struct | `rust-core/src/store/mod.rs` | Saved connections JSON |
| `QueryStore` | struct | `rust-core/src/store/mod.rs` | Saved queries + usage |
| `classify_sql` | fn | `rust-core/src/sql/parser.rs` | Query type detection |
| `RustBridge` | class | `swift-ui/RedB/Services/RustBridge.swift` | Swift FFI wrapper |
| `DatabaseViewModel` | class | `swift-ui/RedB/Models/DatabaseViewModel.swift` | Central app state |

## CONVENTIONS

- **All FFI exports** go through `ffi.rs` — never expose inner types directly via uniffi.
- **Feature gates** for each DB backend (`#[cfg(feature = "postgres")]`). Add new backends by adding feature + cfg blocks.
- **Thread safety**: inner state wrapped in `std::sync::Mutex` (not tokio). Tokio runtimes created per-backend for async drivers.
- **uniffi 0.28**: `#[derive(uniffi::Object)]` + `#[uniffi::export] impl` for exported classes. Use `Arc<Self>` from constructors.
- **Swift side**: all FFI calls go through `ffiQueue.async` + `withCheckedThrowingContinuation`. Never call uniffi directly from main thread.
- **Error pattern**: `thiserror` + `#[derive(uniffi::Error)]` for `DbError` enum with named fields.
- **JSON stores** use atomic write (write to `.tmp` then `rename`).

## ANTI-PATTERNS

- `conn.lock().unwrap()` everywhere — no poisoning recovery. Panics on poisoned mutex.
- SQL Server column names default to `col_{i}` — metadata not read from query results.
- DB2 `list_tables` returns empty vec — not implemented.
- `build.rs` is empty — uniffi scaffolding is in lib.rs.

## COMMANDS

```bash
cargo build -p redb-core                        # Debug build
cargo build --release -p redb-core               # Release build
cargo build -p redb-core --features all-dbs      # All backends
cargo test -p redb-core                          # Run tests
./scripts/build-rust.sh release                  # Build + gen Swift bindings
cargo run --release -p gen-bindings -- <lib> <out> # Manual binding gen
```

## NOTES

- No CI, no formatter/lint configs exist.
- DB2 feature (`db2`) is excluded from `all-dbs`.
- UniFFI-generated Swift bindings in `swift-ui/RedB/Generated/` are gitignored.
