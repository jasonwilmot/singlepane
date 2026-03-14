# Ghostty Terminal Emulator: Theme File Format & Popular Theme Color Values

## 1. Ghostty Overview & Ecosystem Statistics

| Metric | Value |
|--------|-------|
| Ghostty GitHub Stars | 45,637 |
| Ghostty GitHub Forks | 1,815 |
| Built-in themes (sourced from iTerm2-Color-Schemes) | 463 |
| iTerm2-Color-Schemes repo stars | 26,547 |
| Platforms supported | macOS, Linux (no Windows) |
| Current stable version | 1.2.x (1.3.0 targeted March 2026) |

---

## 2. Theme File Format Specification

### File Location
- System built-in themes: Bundled with Ghostty (sourced from iTerm2-Color-Schemes, updated weekly)
- User custom themes: `$XDG_CONFIG_HOME/ghostty/themes/` or `~/.config/ghostty/themes/`
- Main config file: `~/.config/ghostty/config`

### Syntax
- Format: `key = value` (whitespace around `=` is optional)
- Keys are **case-sensitive**, always **lowercase**
- Values can be quoted or unquoted
- Colors specified as hex (`#RRGGBB` or `RRGGBB`) or X11 named colors
- A theme file is simply a Ghostty config file containing color keys
- Comments use `#` at the start of a line (but not after values)

### Activating a Theme
```
# In ~/.config/ghostty/config:
theme = Catppuccin Mocha

# Light/dark auto-switching:
theme = light:Rose Pine Dawn,dark:Rose Pine
```

---

## 3. All Color-Related Configuration Keys

### Core Color Keys (used in theme files)

| Key | Description | Accepts |
|-----|-------------|---------|
| `background` | Window background color | Hex (`#RRGGBB`/`RRGGBB`), X11 color name |
| `foreground` | Window text color | Hex, X11 color name |
| `cursor-color` | Cursor color | Hex, X11, `cell-foreground`, `cell-background` (v1.2.0+) |
| `cursor-text` | Text color under cursor | Hex, X11, `cell-foreground`, `cell-background` (v1.2.0+) |
| `selection-background` | Background of selected text | Hex, X11, `cell-foreground`, `cell-background` (v1.2.0+) |
| `selection-foreground` | Foreground of selected text | Hex, X11, `cell-foreground`, `cell-background` (v1.2.0+) |
| `palette` | 256-color palette entry | Format: `N=COLOR` where N is 0-255 |
| `split-divider-color` | Color of split pane dividers (v1.1.0+) | Hex, X11 color name |

### Additional Color-Adjacent Keys

| Key | Description | Accepts |
|-----|-------------|---------|
| `cursor-opacity` | Cursor transparency | 0 (transparent) to 1 (opaque) |
| `unfocused-split-fill` | Overlay color for inactive splits | Hex, X11 color name |
| `minimum-contrast` | Minimum contrast ratio (WCAG 2.0) | 1 to 21 |
| `window-colorspace` | Color space (macOS only) | `srgb`, `display-p3` |
| `alpha-blending` | Transparency blending mode | `native`, `linear`, `linear-corrected` |

### Palette Index Mapping (Colors 0-15)

| Index | Standard Name | Index | Standard Name |
|-------|--------------|-------|--------------|
| 0 | Black (normal) | 8 | Black (bright) |
| 1 | Red (normal) | 9 | Red (bright) |
| 2 | Green (normal) | 10 | Green (bright) |
| 3 | Yellow (normal) | 11 | Yellow (bright) |
| 4 | Blue (normal) | 12 | Blue (bright) |
| 5 | Magenta (normal) | 13 | Magenta (bright) |
| 6 | Cyan (normal) | 14 | Cyan (bright) |
| 7 | White (normal) | 15 | White (bright) |

Colors 16-255 are the extended 256-color palette (216 color cube + 24 grayscale).

---

## 4. Example Theme File Structure

```
# Example: Dracula theme for Ghostty
palette = 0=#21222c
palette = 1=#ff5555
palette = 2=#50fa7b
palette = 3=#f1fa8c
palette = 4=#bd93f9
palette = 5=#ff79c6
palette = 6=#8be9fd
palette = 7=#f8f8f2
palette = 8=#6272a4
palette = 9=#ff6e6e
palette = 10=#69ff94
palette = 11=#ffffa5
palette = 12=#d6acff
palette = 13=#ff92df
palette = 14=#a4ffff
palette = 15=#ffffff
background = #282a36
foreground = #f8f8f2
cursor-color = #f8f8f2
cursor-text = #282a36
selection-foreground = #f8f8f2
selection-background = #44475a
```

---

## 5. Popular Theme Sources

| Source | URL | Notes |
|--------|-----|-------|
| Ghostty built-in themes | Bundled with app | 463 themes, sourced from iTerm2-Color-Schemes |
| iTerm2-Color-Schemes (Ghostty port) | https://github.com/mbadolato/iTerm2-Color-Schemes | 26,547 stars, 463 Ghostty theme files |
| Catppuccin/ghostty | https://github.com/catppuccin/ghostty | Official Catppuccin port (4 flavors) |
| Dracula/ghostty | https://github.com/dracula/ghostty | Official Dracula port |
| Rose Pine/ghostty | https://github.com/rose-pine/ghostty | Official Rose Pine port |
| TerminalColors.com | https://terminalcolors.com/ghostty/ | Web-based theme browser with downloads |

---

## 6. Theme Popularity (GitHub Stars)

| Theme | GitHub Stars | Primary Repository |
|-------|-------------|-------------------|
| Dracula | 23,369 | dracula/dracula-theme |
| Catppuccin | 18,496 | catppuccin/catppuccin |
| Solarized | 15,973 | altercation/solarized |
| Gruvbox | 15,239 | morhetz/gruvbox |
| Nord | 6,764 | nordtheme/nord |
| Tokyo Night | 2,289 | enkia/tokyo-night-vscode-theme |
| One Dark Pro | 1,728 | Binaryify/OneDark-Pro |
| Rose Pine | 1,531 | rose-pine/rose-pine-theme |

---

## 7. Complete Theme Color Values

All values below are verified from official Ghostty theme files (iTerm2-Color-Schemes repo and official theme repos).

### 7.1 Catppuccin Mocha

Source: https://github.com/catppuccin/ghostty/blob/main/themes/catppuccin-mocha.conf

| Key | Value |
|-----|-------|
| `background` | `#1e1e2e` |
| `foreground` | `#cdd6f4` |
| `cursor-color` | `#f5e0dc` |
| `cursor-text` | `#11111b` |
| `selection-background` | `#353749` |
| `selection-foreground` | `#cdd6f4` |
| `split-divider-color` | `#313244` |
| `palette 0` (Black) | `#45475a` |
| `palette 1` (Red) | `#f38ba8` |
| `palette 2` (Green) | `#a6e3a1` |
| `palette 3` (Yellow) | `#f9e2af` |
| `palette 4` (Blue) | `#89b4fa` |
| `palette 5` (Magenta) | `#f5c2e7` |
| `palette 6` (Cyan) | `#94e2d5` |
| `palette 7` (White) | `#a6adc8` |
| `palette 8` (Bright Black) | `#585b70` |
| `palette 9` (Bright Red) | `#f38ba8` |
| `palette 10` (Bright Green) | `#a6e3a1` |
| `palette 11` (Bright Yellow) | `#f9e2af` |
| `palette 12` (Bright Blue) | `#89b4fa` |
| `palette 13` (Bright Magenta) | `#f5c2e7` |
| `palette 14` (Bright Cyan) | `#94e2d5` |
| `palette 15` (Bright White) | `#bac2de` |

Raw Ghostty config:
```
palette = 0=#45475a
palette = 1=#f38ba8
palette = 2=#a6e3a1
palette = 3=#f9e2af
palette = 4=#89b4fa
palette = 5=#f5c2e7
palette = 6=#94e2d5
palette = 7=#a6adc8
palette = 8=#585b70
palette = 9=#f38ba8
palette = 10=#a6e3a1
palette = 11=#f9e2af
palette = 12=#89b4fa
palette = 13=#f5c2e7
palette = 14=#94e2d5
palette = 15=#bac2de
background = 1e1e2e
foreground = cdd6f4
cursor-color = f5e0dc
cursor-text = 11111b
selection-background = 353749
selection-foreground = cdd6f4
split-divider-color = 313244
```

---

### 7.2 Dracula

Source: https://github.com/dracula/ghostty (raw file)

| Key | Value |
|-----|-------|
| `background` | `#282a36` |
| `foreground` | `#f8f8f2` |
| `cursor-color` | `#f8f8f2` |
| `cursor-text` | `#282a36` |
| `selection-background` | `#44475a` |
| `selection-foreground` | `#f8f8f2` |
| `palette 0` (Black) | `#21222c` |
| `palette 1` (Red) | `#ff5555` |
| `palette 2` (Green) | `#50fa7b` |
| `palette 3` (Yellow) | `#f1fa8c` |
| `palette 4` (Blue) | `#bd93f9` |
| `palette 5` (Magenta) | `#ff79c6` |
| `palette 6` (Cyan) | `#8be9fd` |
| `palette 7` (White) | `#f8f8f2` |
| `palette 8` (Bright Black) | `#6272a4` |
| `palette 9` (Bright Red) | `#ff6e6e` |
| `palette 10` (Bright Green) | `#69ff94` |
| `palette 11` (Bright Yellow) | `#ffffa5` |
| `palette 12` (Bright Blue) | `#d6acff` |
| `palette 13` (Bright Magenta) | `#ff92df` |
| `palette 14` (Bright Cyan) | `#a4ffff` |
| `palette 15` (Bright White) | `#ffffff` |

Raw Ghostty config:
```
palette = 0=#21222c
palette = 1=#ff5555
palette = 2=#50fa7b
palette = 3=#f1fa8c
palette = 4=#bd93f9
palette = 5=#ff79c6
palette = 6=#8be9fd
palette = 7=#f8f8f2
palette = 8=#6272a4
palette = 9=#ff6e6e
palette = 10=#69ff94
palette = 11=#ffffa5
palette = 12=#d6acff
palette = 13=#ff92df
palette = 14=#a4ffff
palette = 15=#ffffff
background = #282a36
foreground = #f8f8f2
cursor-color = #f8f8f2
cursor-text = #282a36
selection-foreground = #f8f8f2
selection-background = #44475a
```

---

### 7.3 Gruvbox Dark

Source: iTerm2-Color-Schemes/ghostty/Gruvbox Dark

| Key | Value |
|-----|-------|
| `background` | `#282828` |
| `foreground` | `#ebdbb2` |
| `cursor-color` | `#ebdbb2` |
| `cursor-text` | `#282828` |
| `selection-background` | `#665c54` |
| `selection-foreground` | `#ebdbb2` |
| `palette 0` (Black) | `#282828` |
| `palette 1` (Red) | `#cc241d` |
| `palette 2` (Green) | `#98971a` |
| `palette 3` (Yellow) | `#d79921` |
| `palette 4` (Blue) | `#458588` |
| `palette 5` (Magenta) | `#b16286` |
| `palette 6` (Cyan) | `#689d6a` |
| `palette 7` (White) | `#a89984` |
| `palette 8` (Bright Black) | `#928374` |
| `palette 9` (Bright Red) | `#fb4934` |
| `palette 10` (Bright Green) | `#b8bb26` |
| `palette 11` (Bright Yellow) | `#fabd2f` |
| `palette 12` (Bright Blue) | `#83a598` |
| `palette 13` (Bright Magenta) | `#d3869b` |
| `palette 14` (Bright Cyan) | `#8ec07c` |
| `palette 15` (Bright White) | `#ebdbb2` |

Raw Ghostty config:
```
palette = 0=#282828
palette = 1=#cc241d
palette = 2=#98971a
palette = 3=#d79921
palette = 4=#458588
palette = 5=#b16286
palette = 6=#689d6a
palette = 7=#a89984
palette = 8=#928374
palette = 9=#fb4934
palette = 10=#b8bb26
palette = 11=#fabd2f
palette = 12=#83a598
palette = 13=#d3869b
palette = 14=#8ec07c
palette = 15=#ebdbb2
background = #282828
foreground = #ebdbb2
cursor-color = #ebdbb2
cursor-text = #282828
selection-background = #665c54
selection-foreground = #ebdbb2
```

---

### 7.4 Nord

Source: iTerm2-Color-Schemes/ghostty/Nord

| Key | Value |
|-----|-------|
| `background` | `#2e3440` |
| `foreground` | `#d8dee9` |
| `cursor-color` | `#eceff4` |
| `cursor-text` | `#282828` |
| `selection-background` | `#eceff4` |
| `selection-foreground` | `#4c566a` |
| `palette 0` (Black) | `#3b4252` |
| `palette 1` (Red) | `#bf616a` |
| `palette 2` (Green) | `#a3be8c` |
| `palette 3` (Yellow) | `#ebcb8b` |
| `palette 4` (Blue) | `#81a1c1` |
| `palette 5` (Magenta) | `#b48ead` |
| `palette 6` (Cyan) | `#88c0d0` |
| `palette 7` (White) | `#e5e9f0` |
| `palette 8` (Bright Black) | `#596377` |
| `palette 9` (Bright Red) | `#bf616a` |
| `palette 10` (Bright Green) | `#a3be8c` |
| `palette 11` (Bright Yellow) | `#ebcb8b` |
| `palette 12` (Bright Blue) | `#81a1c1` |
| `palette 13` (Bright Magenta) | `#b48ead` |
| `palette 14` (Bright Cyan) | `#8fbcbb` |
| `palette 15` (Bright White) | `#eceff4` |

Raw Ghostty config:
```
palette = 0=#3b4252
palette = 1=#bf616a
palette = 2=#a3be8c
palette = 3=#ebcb8b
palette = 4=#81a1c1
palette = 5=#b48ead
palette = 6=#88c0d0
palette = 7=#e5e9f0
palette = 8=#596377
palette = 9=#bf616a
palette = 10=#a3be8c
palette = 11=#ebcb8b
palette = 12=#81a1c1
palette = 13=#b48ead
palette = 14=#8fbcbb
palette = 15=#eceff4
background = #2e3440
foreground = #d8dee9
cursor-color = #eceff4
cursor-text = #282828
selection-background = #eceff4
selection-foreground = #4c566a
```

---

### 7.5 Tokyo Night

Source: iTerm2-Color-Schemes/ghostty/TokyoNight

| Key | Value |
|-----|-------|
| `background` | `#1a1b26` |
| `foreground` | `#c0caf5` |
| `cursor-color` | `#c0caf5` |
| `cursor-text` | `#15161e` |
| `selection-background` | `#33467c` |
| `selection-foreground` | `#c0caf5` |
| `palette 0` (Black) | `#15161e` |
| `palette 1` (Red) | `#f7768e` |
| `palette 2` (Green) | `#9ece6a` |
| `palette 3` (Yellow) | `#e0af68` |
| `palette 4` (Blue) | `#7aa2f7` |
| `palette 5` (Magenta) | `#bb9af7` |
| `palette 6` (Cyan) | `#7dcfff` |
| `palette 7` (White) | `#a9b1d6` |
| `palette 8` (Bright Black) | `#414868` |
| `palette 9` (Bright Red) | `#f7768e` |
| `palette 10` (Bright Green) | `#9ece6a` |
| `palette 11` (Bright Yellow) | `#e0af68` |
| `palette 12` (Bright Blue) | `#7aa2f7` |
| `palette 13` (Bright Magenta) | `#bb9af7` |
| `palette 14` (Bright Cyan) | `#7dcfff` |
| `palette 15` (Bright White) | `#c0caf5` |

Raw Ghostty config:
```
palette = 0=#15161e
palette = 1=#f7768e
palette = 2=#9ece6a
palette = 3=#e0af68
palette = 4=#7aa2f7
palette = 5=#bb9af7
palette = 6=#7dcfff
palette = 7=#a9b1d6
palette = 8=#414868
palette = 9=#f7768e
palette = 10=#9ece6a
palette = 11=#e0af68
palette = 12=#7aa2f7
palette = 13=#bb9af7
palette = 14=#7dcfff
palette = 15=#c0caf5
background = #1a1b26
foreground = #c0caf5
cursor-color = #c0caf5
cursor-text = #15161e
selection-background = #33467c
selection-foreground = #c0caf5
```

---

### 7.6 Solarized Dark

Source: iTerm2-Color-Schemes/ghostty/iTerm2 Solarized Dark

| Key | Value |
|-----|-------|
| `background` | `#002b36` |
| `foreground` | `#839496` |
| `cursor-color` | `#839496` |
| `cursor-text` | `#073642` |
| `selection-background` | `#073642` |
| `selection-foreground` | `#93a1a1` |
| `palette 0` (Black) | `#073642` |
| `palette 1` (Red) | `#dc322f` |
| `palette 2` (Green) | `#859900` |
| `palette 3` (Yellow) | `#b58900` |
| `palette 4` (Blue) | `#268bd2` |
| `palette 5` (Magenta) | `#d33682` |
| `palette 6` (Cyan) | `#2aa198` |
| `palette 7` (White) | `#eee8d5` |
| `palette 8` (Bright Black) | `#335e69` |
| `palette 9` (Bright Red) | `#cb4b16` |
| `palette 10` (Bright Green) | `#586e75` |
| `palette 11` (Bright Yellow) | `#657b83` |
| `palette 12` (Bright Blue) | `#839496` |
| `palette 13` (Bright Magenta) | `#6c71c4` |
| `palette 14` (Bright Cyan) | `#93a1a1` |
| `palette 15` (Bright White) | `#fdf6e3` |

Raw Ghostty config:
```
palette = 0=#073642
palette = 1=#dc322f
palette = 2=#859900
palette = 3=#b58900
palette = 4=#268bd2
palette = 5=#d33682
palette = 6=#2aa198
palette = 7=#eee8d5
palette = 8=#335e69
palette = 9=#cb4b16
palette = 10=#586e75
palette = 11=#657b83
palette = 12=#839496
palette = 13=#6c71c4
palette = 14=#93a1a1
palette = 15=#fdf6e3
background = #002b36
foreground = #839496
cursor-color = #839496
cursor-text = #073642
selection-background = #073642
selection-foreground = #93a1a1
```

---

### 7.7 One Dark (Atom One Dark)

Source: iTerm2-Color-Schemes/ghostty/Atom One Dark

| Key | Value |
|-----|-------|
| `background` | `#21252b` |
| `foreground` | `#abb2bf` |
| `cursor-color` | `#abb2bf` |
| `cursor-text` | `#21252b` |
| `selection-background` | `#323844` |
| `selection-foreground` | `#abb2bf` |
| `palette 0` (Black) | `#21252b` |
| `palette 1` (Red) | `#e06c75` |
| `palette 2` (Green) | `#98c379` |
| `palette 3` (Yellow) | `#e5c07b` |
| `palette 4` (Blue) | `#61afef` |
| `palette 5` (Magenta) | `#c678dd` |
| `palette 6` (Cyan) | `#56b6c2` |
| `palette 7` (White) | `#abb2bf` |
| `palette 8` (Bright Black) | `#767676` |
| `palette 9` (Bright Red) | `#e06c75` |
| `palette 10` (Bright Green) | `#98c379` |
| `palette 11` (Bright Yellow) | `#e5c07b` |
| `palette 12` (Bright Blue) | `#61afef` |
| `palette 13` (Bright Magenta) | `#c678dd` |
| `palette 14` (Bright Cyan) | `#56b6c2` |
| `palette 15` (Bright White) | `#abb2bf` |

Raw Ghostty config:
```
palette = 0=#21252b
palette = 1=#e06c75
palette = 2=#98c379
palette = 3=#e5c07b
palette = 4=#61afef
palette = 5=#c678dd
palette = 6=#56b6c2
palette = 7=#abb2bf
palette = 8=#767676
palette = 9=#e06c75
palette = 10=#98c379
palette = 11=#e5c07b
palette = 12=#61afef
palette = 13=#c678dd
palette = 14=#56b6c2
palette = 15=#abb2bf
background = #21252b
foreground = #abb2bf
cursor-color = #abb2bf
cursor-text = #21252b
selection-background = #323844
selection-foreground = #abb2bf
```

---

### 7.8 Rose Pine

Source: iTerm2-Color-Schemes/ghostty/Rose Pine

| Key | Value |
|-----|-------|
| `background` | `#191724` |
| `foreground` | `#e0def4` |
| `cursor-color` | `#e0def4` |
| `cursor-text` | `#191724` |
| `selection-background` | `#403d52` |
| `selection-foreground` | `#e0def4` |
| `palette 0` (Black) | `#26233a` |
| `palette 1` (Red) | `#eb6f92` |
| `palette 2` (Green) | `#31748f` |
| `palette 3` (Yellow) | `#f6c177` |
| `palette 4` (Blue) | `#9ccfd8` |
| `palette 5` (Magenta) | `#c4a7e7` |
| `palette 6` (Cyan) | `#ebbcba` |
| `palette 7` (White) | `#e0def4` |
| `palette 8` (Bright Black) | `#6e6a86` |
| `palette 9` (Bright Red) | `#eb6f92` |
| `palette 10` (Bright Green) | `#31748f` |
| `palette 11` (Bright Yellow) | `#f6c177` |
| `palette 12` (Bright Blue) | `#9ccfd8` |
| `palette 13` (Bright Magenta) | `#c4a7e7` |
| `palette 14` (Bright Cyan) | `#ebbcba` |
| `palette 15` (Bright White) | `#e0def4` |

Raw Ghostty config:
```
palette = 0=#26233a
palette = 1=#eb6f92
palette = 2=#31748f
palette = 3=#f6c177
palette = 4=#9ccfd8
palette = 5=#c4a7e7
palette = 6=#ebbcba
palette = 7=#e0def4
palette = 8=#6e6a86
palette = 9=#eb6f92
palette = 10=#31748f
palette = 11=#f6c177
palette = 12=#9ccfd8
palette = 13=#c4a7e7
palette = 14=#ebbcba
palette = 15=#e0def4
background = #191724
foreground = #e0def4
cursor-color = #e0def4
cursor-text = #191724
selection-background = #403d52
selection-foreground = #e0def4
```

---

## 8. Quick Comparison: Background & Foreground Colors

| Theme | Background | Foreground | Cursor | Selection BG |
|-------|-----------|------------|--------|-------------|
| Catppuccin Mocha | `#1e1e2e` | `#cdd6f4` | `#f5e0dc` | `#353749` |
| Dracula | `#282a36` | `#f8f8f2` | `#f8f8f2` | `#44475a` |
| Gruvbox Dark | `#282828` | `#ebdbb2` | `#ebdbb2` | `#665c54` |
| Nord | `#2e3440` | `#d8dee9` | `#eceff4` | `#eceff4` |
| Tokyo Night | `#1a1b26` | `#c0caf5` | `#c0caf5` | `#33467c` |
| Solarized Dark | `#002b36` | `#839496` | `#839496` | `#073642` |
| One Dark | `#21252b` | `#abb2bf` | `#abb2bf` | `#323844` |
| Rose Pine | `#191724` | `#e0def4` | `#e0def4` | `#403d52` |

---

## 9. Quick Comparison: ANSI Colors (Normal 0-7)

| Index | Catppuccin Mocha | Dracula | Gruvbox Dark | Nord | Tokyo Night | Solarized Dark | One Dark | Rose Pine |
|-------|-----------------|---------|-------------|------|-------------|---------------|----------|-----------|
| 0 (Black) | `#45475a` | `#21222c` | `#282828` | `#3b4252` | `#15161e` | `#073642` | `#21252b` | `#26233a` |
| 1 (Red) | `#f38ba8` | `#ff5555` | `#cc241d` | `#bf616a` | `#f7768e` | `#dc322f` | `#e06c75` | `#eb6f92` |
| 2 (Green) | `#a6e3a1` | `#50fa7b` | `#98971a` | `#a3be8c` | `#9ece6a` | `#859900` | `#98c379` | `#31748f` |
| 3 (Yellow) | `#f9e2af` | `#f1fa8c` | `#d79921` | `#ebcb8b` | `#e0af68` | `#b58900` | `#e5c07b` | `#f6c177` |
| 4 (Blue) | `#89b4fa` | `#bd93f9` | `#458588` | `#81a1c1` | `#7aa2f7` | `#268bd2` | `#61afef` | `#9ccfd8` |
| 5 (Magenta) | `#f5c2e7` | `#ff79c6` | `#b16286` | `#b48ead` | `#bb9af7` | `#d33682` | `#c678dd` | `#c4a7e7` |
| 6 (Cyan) | `#94e2d5` | `#8be9fd` | `#689d6a` | `#88c0d0` | `#7dcfff` | `#2aa198` | `#56b6c2` | `#ebbcba` |
| 7 (White) | `#a6adc8` | `#f8f8f2` | `#a89984` | `#e5e9f0` | `#a9b1d6` | `#eee8d5` | `#abb2bf` | `#e0def4` |

---

## 10. Quick Comparison: ANSI Colors (Bright 8-15)

| Index | Catppuccin Mocha | Dracula | Gruvbox Dark | Nord | Tokyo Night | Solarized Dark | One Dark | Rose Pine |
|-------|-----------------|---------|-------------|------|-------------|---------------|----------|-----------|
| 8 (Bright Black) | `#585b70` | `#6272a4` | `#928374` | `#596377` | `#414868` | `#335e69` | `#767676` | `#6e6a86` |
| 9 (Bright Red) | `#f38ba8` | `#ff6e6e` | `#fb4934` | `#bf616a` | `#f7768e` | `#cb4b16` | `#e06c75` | `#eb6f92` |
| 10 (Bright Green) | `#a6e3a1` | `#69ff94` | `#b8bb26` | `#a3be8c` | `#9ece6a` | `#586e75` | `#98c379` | `#31748f` |
| 11 (Bright Yellow) | `#f9e2af` | `#ffffa5` | `#fabd2f` | `#ebcb8b` | `#e0af68` | `#657b83` | `#e5c07b` | `#f6c177` |
| 12 (Bright Blue) | `#89b4fa` | `#d6acff` | `#83a598` | `#81a1c1` | `#7aa2f7` | `#839496` | `#61afef` | `#9ccfd8` |
| 13 (Bright Magenta) | `#f5c2e7` | `#ff92df` | `#d3869b` | `#b48ead` | `#bb9af7` | `#6c71c4` | `#c678dd` | `#c4a7e7` |
| 14 (Bright Cyan) | `#94e2d5` | `#a4ffff` | `#8ec07c` | `#8fbcbb` | `#7dcfff` | `#93a1a1` | `#56b6c2` | `#ebbcba` |
| 15 (Bright White) | `#bac2de` | `#ffffff` | `#ebdbb2` | `#eceff4` | `#c0caf5` | `#fdf6e3` | `#abb2bf` | `#e0def4` |

---

## Sources

- Ghostty Official Documentation: https://ghostty.org/docs/config/reference
- Ghostty Color Theme Docs: https://ghostty.org/docs/features/theme
- Ghostty GitHub Repository: https://github.com/ghostty-org/ghostty
- iTerm2-Color-Schemes (Ghostty themes): https://github.com/mbadolato/iTerm2-Color-Schemes
- Catppuccin Ghostty Theme: https://github.com/catppuccin/ghostty
- Dracula Ghostty Theme: https://github.com/dracula/ghostty
- Rose Pine Ghostty Theme: https://github.com/rose-pine/ghostty
- Nord Theme: https://github.com/nordtheme/nord
- Ghostty Man Page (OpenSUSE): https://manpages.opensuse.org/Tumbleweed/ghostty/ghostty.5.en.html
- TerminalColors.com Ghostty Themes: https://terminalcolors.com/ghostty/
