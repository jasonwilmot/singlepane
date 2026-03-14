# Velocity File Manager

> A blazing-fast, keyboard-first file manager for macOS.

## Features

- **Dual-pane browser** with unlimited tabs per panel
- **Lightning search** — indexed (FTS5) and raw filesystem modes
- **Embedded terminal** via SwiftTerm + PTY with drag-and-drop path insertion
- **Archive transparency** — browse ZIP, 7z, TAR, RAR, ISO as folders
- **Modular UI** — draggable, dockable panels you arrange into custom layouts

## Quick Start

```bash
# Clone the repo
git clone https://github.com/velocity-app/velocity.git
cd velocity

# Build and run (requires Xcode 16+)
xcodebuild -scheme Velocity -configuration Debug build
open build/Debug/Velocity.app
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `F3` | View file |
| `F4` | Edit file |
| `F5` | Copy |
| `F6` | Move |
| `F7` | Create folder |
| `F8` | Delete |
| `Cmd+Shift+P` | Command palette |
| `Cmd+Shift+F` | Global search |
| `Cmd+D` | Toggle dual pane |
| `Cmd+T` | Toggle terminal |

## Architecture

```
UI Layer (AppKit / SwiftUI)
    ↕
ViewModel Layer (@Observable, AsyncSequence)
    ↕
Service Layer (FileService, SearchService, TerminalService...)
    ↕
Foundation Layer (POSIX, SQLite, libarchive, FSEvents, PTY)
```

### Performance Targets

- Cold launch: **< 1 second**
- 100K file directory: **< 500ms** to first paint
- Search first result: **< 50ms** (indexed), **< 200ms** (raw)
- Terminal keystroke-to-echo: **< 8ms** (p95)
- File copy throughput: **> 90%** of disk bandwidth

## Project Structure

```
velocity/
├── Sources/
│   ├── App/              # App delegate, main window
│   ├── UI/               # Views, view controllers
│   ├── ViewModels/       # Observable view models
│   ├── Services/         # Business logic actors
│   ├── Foundation/       # POSIX wrappers, C interop
│   └── Extensions/       # Swift extensions
├── Tests/
│   ├── Unit/
│   ├── Integration/
│   └── Performance/
├── Resources/
│   ├── Assets.xcassets
│   └── Localizable.strings
└── Docs/
    ├── architecture.md
    └── contributing.md
```

## Building

### Requirements

- macOS 14.0+
- Xcode 16+
- Swift 6+

### Dependencies

| Library | Purpose |
|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulation |
| [libarchive](https://libarchive.org/) | Archive handling |
| [minizip-ng](https://github.com/zlib-ng/minizip-ng) | ZIP operations |
| [SQLite](https://sqlite.org/) | Search index (FTS5) |

### Running Tests

```bash
# Unit tests
xcodebuild test -scheme Velocity -only-testing:VelocityTests

# Performance tests (fail on regression > 10%)
xcodebuild test -scheme Velocity -only-testing:VelocityPerformanceTests
```

## Configuration

User settings live in `~/Library/Application Support/Velocity/config.json`. See [`config.json`](files/samples/config.json) for the full schema.

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/awesome`)
3. Write tests for your changes
4. Run the full test suite
5. Submit a pull request

Please read [CONTRIBUTING.md](docs/contributing.md) before submitting.

## License

MIT License. See [LICENSE](LICENSE) for details.

---

*Built with obsessive attention to performance.*
