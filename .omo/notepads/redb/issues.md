## 2026-07-21 [ULW Init] Known issues from AGENTS.md
- SQL Server: column names default to col_{i} — metadata not read from query results
- DB2: list_tables returns empty vec — not implemented
- conn.lock().unwrap() everywhere — no poisoning recovery, panics on poisoned mutex
- SwiftUI: bridge.connect() called from onChange(of: selectedConnection) — potential infinite loop if profile changes during connection
