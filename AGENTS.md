# PROJECT KNOWLEDGE BASE

**Generated:** 2026-07-21
**Stack:** Rust → uniffi FFI → SwiftUI (macOS)

## OVERVIEW

Multi-architecture database GUI client. Rust core (redb-core) provides multi-backend SQL query + schema browsing via uniffi-generated FFI bindings. SwiftUI app delivers the macOS frontend.

## DESIGN PRINCIPLES

### macOS Native
- **macOS native application**: 严格遵循 Apple Human Interface Guidelines (HIG)。不使用 iOS/跨平台 UI 模式。任何 UI 变更必须以 macOS 原生 App（Finder、Xcode、Mail、Safari）为参考基准。
- **SF Symbols first**: 优先使用系统图标，语义正确（folder=文件浏览，chevron=展开折叠，play=运行执行）。
- **System colors only**: 禁止硬编码 RGB 颜色。使用语义色（`.green`/`.red`/`.orange`/`.accentColor`/`.secondary`/`.tertiary`）确保暗黑模式和无障碍适配。
- **Native controls**: 使用 SwiftUI 原生控件，避免自定义外观偏离 macOS 标准。`.cornerRadius` 用于 iOS，macOS 用平面高亮。
- **Tooltip mandatory**: 所有纯图标按钮必须有 tooltip。Toolbar 和 `.borderless` 按钮使用原生 `NSView.toolTip`（见 `View+Tooltip.swift`）。
- **Animation restraint**: 布局切换用 `.easeInOut(duration: 0.2)`，结果面板用 `.transition(.opacity)`。不过度动画。

### Architecture — Core/UI Separation (HIGHEST PRIORITY)

```
┌──────────────────────────────────────────────────┐
│  Core (Rust)                                      │
│  ├── 数据库连接/查询/元数据                       │
│  ├── SQL解析（sqlparser）                          │
│  ├── SQL格式化/上下文分析                         │
│  ├── 连接配置持久化（ConnectionStore/QueryStore） │
│  └── 所有业务逻辑                                  │
├── uniffi FFI ─────────────────────────────────────┤
│  UI Layer                                         │
│  ├── 只负责渲染和用户交互                          │
│  ├── 核心数据库操作都通过 FFI 调用                 │
│  └── 不包含任何数据库逻辑/SQL字符串/SQL解析        │
└──────────────────────────────────────────────────┘
```

**Rust Core — ALL business logic:**
- 数据库连接管理、查询执行、元数据获取
- SQL 解析、分类、格式化、上下文分析
- 自动补全上下文分析（`analyze_sql_context`）
- 控制语句识别（SET/USE/BEGIN/COMMIT/ROLLBACK）
- 连接配置持久化
- 多后端差异封装（各数据库 SQL 方言在 core 内部处理）

**UI Layer — ONLY presentation:**
- 只调用 FFI 接口，不手写 SQL 字符串
- 不包含任何数据库逻辑判断
- 所有数据库操作结果从 FFI 获取后直接展示
- 自动补全列表过滤可做基础 string.contains（毫秒级），
  但上下文判断必须通过 core 的 `analyze_sql_context`

**Rule: UI MUST NOT contain:**
- ❌ 手写 SQL 字符串（SELECT/INSERT/UPDATE 等）
- ❌ 数据库方言判断（MySQL vs PostgreSQL vs SQLite）
- ❌ 端口号/默认值等数据库参数
- ❌ SQL 解析、分词、格式化逻辑
- ❌ 连接状态管理逻辑

**Rule: UI MAY contain:**
- ✅ 渲染布局、动画、过渡
- ✅ 纯 UI 状态管理（LoadState, QueryTab）
- ✅ 静态关键词列表（语法高亮/自动补全过滤——无业务逻辑的数据）
- ✅ 快捷键映射、窗口管理
- ✅ 用户交互事件处理

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
