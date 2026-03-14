"""
Velocity Search Engine — Index builder and query executor.

Uses SQLite FTS5 for full-text search with real-time updates
via FSEvents. Supports filename, content, and metadata search
with boolean operators and regex patterns.
"""

import os
import re
import sqlite3
import hashlib
import time
from dataclasses import dataclass, field
from enum import Enum, auto
from pathlib import Path
from typing import Generator


# ── Data Types ──────────────────────────────────────────────

class SearchMode(Enum):
    FILENAME = auto()
    CONTENT = auto()
    METADATA = auto()
    DUPLICATE = auto()


class SortOrder(Enum):
    RELEVANCE = "rank"
    NAME_ASC = "name ASC"
    NAME_DESC = "name DESC"
    SIZE_ASC = "size ASC"
    SIZE_DESC = "size DESC"
    MODIFIED_ASC = "modified ASC"
    MODIFIED_DESC = "modified DESC"


@dataclass
class SearchQuery:
    pattern: str
    mode: SearchMode = SearchMode.FILENAME
    scope: list[str] = field(default_factory=lambda: [str(Path.home())])
    recursive: bool = True
    case_sensitive: bool = False
    use_regex: bool = False
    include_hidden: bool = False
    min_size: int | None = None
    max_size: int | None = None
    file_types: list[str] = field(default_factory=list)
    sort: SortOrder = SortOrder.RELEVANCE
    limit: int = 10_000


@dataclass
class SearchResult:
    path: str
    name: str
    size: int
    modified: float
    score: float = 0.0
    snippet: str = ""
    match_positions: list[tuple[int, int]] = field(default_factory=list)

    @property
    def extension(self) -> str:
        return Path(self.path).suffix.lower()

    @property
    def is_directory(self) -> bool:
        return os.path.isdir(self.path)


# ── Index Manager ───────────────────────────────────────────

class SearchIndex:
    """Manages the SQLite FTS5 search index."""

    SCHEMA_VERSION = 3

    CREATE_TABLES = """
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY,
            path TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            extension TEXT,
            size INTEGER,
            modified REAL,
            content_hash TEXT,
            indexed_at REAL
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
            name,
            path,
            content='files',
            content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );

        CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
            INSERT INTO files_fts(rowid, name, path)
            VALUES (new.id, new.name, new.path);
        END;

        CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, name, path)
            VALUES ('delete', old.id, old.name, old.path);
        END;

        CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, name, path)
            VALUES ('delete', old.id, old.name, old.path);
            INSERT INTO files_fts(rowid, name, path)
            VALUES (new.id, new.name, new.path);
        END;

        CREATE INDEX IF NOT EXISTS idx_files_path ON files(path);
        CREATE INDEX IF NOT EXISTS idx_files_extension ON files(extension);
        CREATE INDEX IF NOT EXISTS idx_files_size ON files(size);
        CREATE INDEX IF NOT EXISTS idx_files_modified ON files(modified);
        CREATE INDEX IF NOT EXISTS idx_files_hash ON files(content_hash);
    """

    def __init__(self, db_path: str | None = None):
        if db_path is None:
            db_path = os.path.expanduser(
                "~/Library/Application Support/Velocity/search_index.db"
            )
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self.conn.execute("PRAGMA cache_size=-64000")  # 64MB
        self.conn.execute("PRAGMA mmap_size=268435456")  # 256MB
        self._init_schema()

    def _init_schema(self):
        self.conn.executescript(self.CREATE_TABLES)
        self.conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
            ("schema_version", str(self.SCHEMA_VERSION)),
        )
        self.conn.commit()

    def close(self):
        self.conn.close()

    def index_directory(
        self,
        root: str,
        *,
        exclude_patterns: list[str] | None = None,
        on_progress: callable = None,
    ) -> int:
        """Walk a directory tree and index all files. Returns count indexed."""
        root = os.path.expanduser(root)
        exclude = set(exclude_patterns or [".git", "node_modules", ".DS_Store"])
        count = 0
        batch = []
        batch_size = 500

        for dirpath, dirnames, filenames in os.walk(root):
            # Filter excluded directories in-place
            dirnames[:] = [
                d for d in dirnames
                if d not in exclude and not d.startswith(".")
            ]

            for filename in filenames:
                if filename in exclude:
                    continue

                filepath = os.path.join(dirpath, filename)
                try:
                    stat = os.stat(filepath)
                except OSError:
                    continue

                batch.append((
                    filepath,
                    filename,
                    Path(filename).suffix.lower(),
                    stat.st_size,
                    stat.st_mtime,
                    None,  # content_hash — computed lazily
                    time.time(),
                ))
                count += 1

                if len(batch) >= batch_size:
                    self._insert_batch(batch)
                    batch.clear()
                    if on_progress:
                        on_progress(count)

        if batch:
            self._insert_batch(batch)
            if on_progress:
                on_progress(count)

        return count

    def _insert_batch(self, batch: list[tuple]):
        self.conn.executemany(
            """
            INSERT OR REPLACE INTO files
                (path, name, extension, size, modified, content_hash, indexed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            batch,
        )
        self.conn.commit()

    def remove_path(self, path: str):
        self.conn.execute("DELETE FROM files WHERE path = ?", (path,))
        self.conn.commit()

    def remove_tree(self, root: str):
        self.conn.execute(
            "DELETE FROM files WHERE path LIKE ? || '%'",
            (root.rstrip("/") + "/",),
        )
        self.conn.commit()

    @property
    def file_count(self) -> int:
        row = self.conn.execute("SELECT COUNT(*) FROM files").fetchone()
        return row[0] if row else 0


# ── Query Engine ────────────────────────────────────────────

class SearchEngine:
    """Executes search queries against the index."""

    def __init__(self, index: SearchIndex):
        self.index = index

    def search(self, query: SearchQuery) -> Generator[SearchResult, None, None]:
        if query.mode == SearchMode.FILENAME:
            yield from self._search_filename(query)
        elif query.mode == SearchMode.DUPLICATE:
            yield from self._find_duplicates(query)
        else:
            yield from self._search_fts(query)

    def _search_filename(self, query: SearchQuery) -> Generator[SearchResult, None, None]:
        if query.use_regex:
            yield from self._search_filename_regex(query)
            return

        fts_query = self._build_fts_query(query.pattern)
        sql = """
            SELECT f.path, f.name, f.size, f.modified,
                   rank AS score
            FROM files_fts fts
            JOIN files f ON f.id = fts.rowid
            WHERE files_fts MATCH ?
        """
        params: list = [fts_query]

        sql += self._build_filters(query, params)
        sql += f" ORDER BY {query.sort.value}"
        sql += " LIMIT ?"
        params.append(query.limit)

        cursor = self.index.conn.execute(sql, params)
        for row in cursor:
            yield SearchResult(
                path=row["path"],
                name=row["name"],
                size=row["size"],
                modified=row["modified"],
                score=abs(row["score"]),
            )

    def _search_filename_regex(self, query: SearchQuery) -> Generator[SearchResult, None, None]:
        flags = 0 if query.case_sensitive else re.IGNORECASE
        try:
            pattern = re.compile(query.pattern, flags)
        except re.error:
            return

        sql = "SELECT path, name, size, modified FROM files"
        params: list = []
        conditions = []

        if query.file_types:
            placeholders = ",".join("?" for _ in query.file_types)
            conditions.append(f"extension IN ({placeholders})")
            params.extend(f".{t.lstrip('.')}" for t in query.file_types)

        if query.min_size is not None:
            conditions.append("size >= ?")
            params.append(query.min_size)

        if query.max_size is not None:
            conditions.append("size <= ?")
            params.append(query.max_size)

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)

        count = 0
        cursor = self.index.conn.execute(sql, params)
        for row in cursor:
            if count >= query.limit:
                break
            match = pattern.search(row["name"])
            if match:
                yield SearchResult(
                    path=row["path"],
                    name=row["name"],
                    size=row["size"],
                    modified=row["modified"],
                    score=1.0,
                    match_positions=[(match.start(), match.end())],
                )
                count += 1

    def _search_fts(self, query: SearchQuery) -> Generator[SearchResult, None, None]:
        fts_query = self._build_fts_query(query.pattern)
        sql = """
            SELECT f.path, f.name, f.size, f.modified,
                   rank AS score,
                   snippet(files_fts, 0, '<b>', '</b>', '...', 32) AS snippet
            FROM files_fts fts
            JOIN files f ON f.id = fts.rowid
            WHERE files_fts MATCH ?
        """
        params: list = [fts_query]
        sql += self._build_filters(query, params)
        sql += f" ORDER BY {query.sort.value} LIMIT ?"
        params.append(query.limit)

        cursor = self.index.conn.execute(sql, params)
        for row in cursor:
            yield SearchResult(
                path=row["path"],
                name=row["name"],
                size=row["size"],
                modified=row["modified"],
                score=abs(row["score"]),
                snippet=row["snippet"] or "",
            )

    def _find_duplicates(self, query: SearchQuery) -> Generator[SearchResult, None, None]:
        sql = """
            SELECT path, name, size, modified, content_hash
            FROM files
            WHERE size > 0
            ORDER BY size, content_hash
        """
        cursor = self.index.conn.execute(sql)
        prev_hash = None
        prev_results = []

        for row in cursor:
            file_hash = row["content_hash"]
            if file_hash and file_hash == prev_hash:
                if prev_results:
                    yield from prev_results
                    prev_results.clear()
                yield SearchResult(
                    path=row["path"],
                    name=row["name"],
                    size=row["size"],
                    modified=row["modified"],
                )
            else:
                prev_results = [
                    SearchResult(
                        path=row["path"],
                        name=row["name"],
                        size=row["size"],
                        modified=row["modified"],
                    )
                ]
            prev_hash = file_hash

    @staticmethod
    def _build_fts_query(pattern: str) -> str:
        tokens = pattern.strip().split()
        escaped = []
        for token in tokens:
            if token.upper() in ("AND", "OR", "NOT"):
                escaped.append(token.upper())
            else:
                clean = re.sub(r'[^\w*]', '', token)
                if clean:
                    escaped.append(f'"{clean}"' if "*" not in clean else clean)
        return " ".join(escaped) if escaped else '""'

    @staticmethod
    def _build_filters(query: SearchQuery, params: list) -> str:
        clauses = []

        if query.file_types:
            placeholders = ",".join("?" for _ in query.file_types)
            clauses.append(f"f.extension IN ({placeholders})")
            params.extend(f".{t.lstrip('.')}" for t in query.file_types)

        if query.min_size is not None:
            clauses.append("f.size >= ?")
            params.append(query.min_size)

        if query.max_size is not None:
            clauses.append("f.size <= ?")
            params.append(query.max_size)

        if not query.include_hidden:
            clauses.append("f.name NOT LIKE '.%'")

        return (" AND " + " AND ".join(clauses)) if clauses else ""


# ── Content Hasher ──────────────────────────────────────────

def compute_hash(filepath: str, algorithm: str = "sha256", chunk_size: int = 65536) -> str:
    h = hashlib.new(algorithm)
    with open(filepath, "rb") as f:
        while chunk := f.read(chunk_size):
            h.update(chunk)
    return h.hexdigest()


# ── CLI Entry Point ─────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Velocity Search Engine CLI")
    sub = parser.add_subparsers(dest="command")

    idx = sub.add_parser("index", help="Index a directory")
    idx.add_argument("path", help="Directory to index")
    idx.add_argument("--db", help="Database path", default=None)

    find = sub.add_parser("search", help="Search the index")
    find.add_argument("pattern", help="Search pattern")
    find.add_argument("--mode", choices=["filename", "content", "duplicate"], default="filename")
    find.add_argument("--regex", action="store_true")
    find.add_argument("--limit", type=int, default=50)
    find.add_argument("--db", help="Database path", default=None)

    stats = sub.add_parser("stats", help="Show index statistics")
    stats.add_argument("--db", help="Database path", default=None)

    args = parser.parse_args()

    if args.command == "index":
        index = SearchIndex(args.db)
        count = index.index_directory(
            args.path,
            on_progress=lambda c: print(f"\rIndexed {c:,} files...", end="", flush=True),
        )
        print(f"\nDone. Indexed {count:,} files.")
        index.close()

    elif args.command == "search":
        mode_map = {
            "filename": SearchMode.FILENAME,
            "content": SearchMode.CONTENT,
            "duplicate": SearchMode.DUPLICATE,
        }
        index = SearchIndex(args.db)
        engine = SearchEngine(index)
        query = SearchQuery(
            pattern=args.pattern,
            mode=mode_map[args.mode],
            use_regex=args.regex,
            limit=args.limit,
        )
        for result in engine.search(query):
            size_kb = result.size / 1024
            print(f"  {result.name:<40} {size_kb:>10.1f} KB  {result.path}")
        index.close()

    elif args.command == "stats":
        index = SearchIndex(args.db)
        print(f"Database: {index.db_path}")
        print(f"Files indexed: {index.file_count:,}")
        index.close()

    else:
        parser.print_help()
