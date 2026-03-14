-- Velocity File Manager — Database Schema
-- Stores user preferences, bookmarks, operation history, and search index metadata.

PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA cache_size = -64000;  -- 64MB

-- ── User Preferences ───────────────────────────────────────

CREATE TABLE IF NOT EXISTS preferences (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  REAL NOT NULL DEFAULT (julianday('now'))
);

INSERT OR IGNORE INTO preferences (key, value) VALUES
    ('theme', 'catppuccin-mocha'),
    ('font_size', '13'),
    ('font_family', 'SF Mono'),
    ('show_hidden_files', 'false'),
    ('confirm_delete', 'true'),
    ('default_view_mode', 'list'),
    ('date_format', 'relative'),
    ('size_format', 'human'),
    ('terminal_shell', '/bin/zsh'),
    ('dual_pane_default', 'false');

-- ── Bookmarks ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS bookmarks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    label       TEXT NOT NULL,
    path        TEXT NOT NULL UNIQUE,
    icon        TEXT DEFAULT 'folder.fill',
    shortcut    TEXT,
    sort_order  INTEGER DEFAULT 0,
    created_at  REAL NOT NULL DEFAULT (julianday('now'))
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_sort ON bookmarks(sort_order);

INSERT OR IGNORE INTO bookmarks (label, path, icon, shortcut, sort_order) VALUES
    ('Home',         '~',              'house.fill',          'Cmd+1', 0),
    ('Desktop',      '~/Desktop',      'desktopcomputer',     'Cmd+2', 1),
    ('Documents',    '~/Documents',    'doc.fill',            'Cmd+3', 2),
    ('Downloads',    '~/Downloads',    'arrow.down.circle',   'Cmd+4', 3),
    ('Applications', '/Applications',  'app.fill',            'Cmd+5', 4),
    ('Projects',     '~/Projects',     'hammer.fill',         NULL,    5);

-- ── Tags ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tags (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    name    TEXT NOT NULL UNIQUE,
    color   TEXT NOT NULL DEFAULT '#89b4fa'
);

CREATE TABLE IF NOT EXISTS file_tags (
    file_path   TEXT NOT NULL,
    tag_id      INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    tagged_at   REAL NOT NULL DEFAULT (julianday('now')),
    PRIMARY KEY (file_path, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_file_tags_path ON file_tags(file_path);
CREATE INDEX IF NOT EXISTS idx_file_tags_tag ON file_tags(tag_id);

INSERT OR IGNORE INTO tags (name, color) VALUES
    ('Red',    '#f38ba8'),
    ('Orange', '#fab387'),
    ('Yellow', '#f9e2af'),
    ('Green',  '#a6e3a1'),
    ('Blue',   '#89b4fa'),
    ('Purple', '#cba6f7'),
    ('Gray',   '#6c7086');

-- ── Operation History ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS operations (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    type            TEXT NOT NULL CHECK (type IN ('copy', 'move', 'delete', 'rename', 'compress', 'extract')),
    source_path     TEXT NOT NULL,
    dest_path       TEXT,
    file_count      INTEGER DEFAULT 1,
    total_bytes     INTEGER DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'failed', 'cancelled', 'undone')),
    error_message   TEXT,
    duration_ms     INTEGER,
    started_at      REAL NOT NULL DEFAULT (julianday('now')),
    completed_at    REAL
);

CREATE INDEX IF NOT EXISTS idx_operations_type ON operations(type);
CREATE INDEX IF NOT EXISTS idx_operations_status ON operations(status);
CREATE INDEX IF NOT EXISTS idx_operations_started ON operations(started_at DESC);

-- ── Saved Searches ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS saved_searches (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    query       TEXT NOT NULL,
    scope       TEXT DEFAULT '~',
    mode        TEXT DEFAULT 'filename' CHECK (mode IN ('filename', 'content', 'metadata', 'duplicate')),
    options     TEXT DEFAULT '{}',  -- JSON blob for additional filters
    use_count   INTEGER DEFAULT 0,
    created_at  REAL NOT NULL DEFAULT (julianday('now')),
    last_used   REAL
);

CREATE INDEX IF NOT EXISTS idx_saved_searches_use ON saved_searches(use_count DESC);

-- ── Workspace Layouts ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS layouts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    config      TEXT NOT NULL,  -- JSON blob of full layout state
    is_default  INTEGER DEFAULT 0,
    created_at  REAL NOT NULL DEFAULT (julianday('now')),
    updated_at  REAL NOT NULL DEFAULT (julianday('now'))
);

-- ── Recent Paths ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS recent_paths (
    path        TEXT PRIMARY KEY,
    visit_count INTEGER DEFAULT 1,
    last_visit  REAL NOT NULL DEFAULT (julianday('now'))
);

CREATE INDEX IF NOT EXISTS idx_recent_paths_visit ON recent_paths(last_visit DESC);

-- ── Cleanup trigger: keep only last 500 operations ─────────

CREATE TRIGGER IF NOT EXISTS trim_operations
AFTER INSERT ON operations
WHEN (SELECT COUNT(*) FROM operations) > 500
BEGIN
    DELETE FROM operations
    WHERE id IN (
        SELECT id FROM operations
        ORDER BY started_at ASC
        LIMIT (SELECT COUNT(*) - 500 FROM operations)
    );
END;

-- ── Cleanup trigger: keep only last 100 recent paths ───────

CREATE TRIGGER IF NOT EXISTS trim_recent_paths
AFTER INSERT ON recent_paths
WHEN (SELECT COUNT(*) FROM recent_paths) > 100
BEGIN
    DELETE FROM recent_paths
    WHERE path IN (
        SELECT path FROM recent_paths
        ORDER BY last_visit ASC
        LIMIT (SELECT COUNT(*) - 100 FROM recent_paths)
    );
END;
