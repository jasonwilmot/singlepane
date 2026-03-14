# Ghostty Terminal Emulator - Popular Fonts Research

## Ghostty Font Configuration Reference

### Primary Config Key
The main configuration key is `font-family`. Values can be quoted or unquoted:

```
font-family = JetBrains Mono
font-family = "JetBrains Mono"
```

Both forms are equivalent.

### All Font-Related Config Keys

| Key | Purpose |
|-----|---------|
| `font-family` | Primary font family (default: JetBrains Mono, which is embedded in Ghostty) |
| `font-family-bold` | Bold variant override (optional, auto-detected from font-family if not set) |
| `font-family-italic` | Italic variant override (optional, auto-detected from font-family if not set) |
| `font-family-bold-italic` | Bold-italic variant override (optional, auto-detected from font-family if not set) |
| `font-size` | Font size in points (supports non-integer values) |
| `font-thicken` | Boolean; renders fonts thicker on macOS (commonly set to `true`) |
| `font-feature` | Enable/disable OpenType features (e.g., `font-feature = -liga` to disable ligatures) |

### Fallback Font Support
The `font-family` key can be repeated multiple times to specify fallback fonts for missing codepoints:
```
font-family = JetBrains Mono
font-family = Noto Sans Mono
```

### Built-in Nerd Fonts
Ghostty ships with built-in Nerd Font symbols, so tools like Starship prompt and icon-heavy CLI apps work out of the box without installing a separate Nerd Font.

### Listing Available Fonts
Run `ghostty +list-fonts` to see all fonts available on the system. Run `ghostty +show-config --default --docs` for full configuration reference.

---

## Top 5 Most Popular Fonts in the Ghostty Community

Based on analysis of Ghostty GitHub discussions, community dotfiles repositories, the naydenoff/ghostty-config configuration system, blog posts, and shared configurations:

### 1. JetBrains Mono

- **Ghostty config name:** `JetBrains Mono`
- **Pre-installed on macOS:** No -- must be downloaded
- **Install via Homebrew:** `brew install --cask font-jetbrains-mono`
- **Nerd Font variant:** `JetBrainsMono Nerd Font` (install: `brew install --cask font-jetbrains-mono-nerd-font`)
- **Why #1:** This is Ghostty's embedded default font. If you do not set `font-family` at all, Ghostty uses JetBrains Mono. It was designed specifically for developers by JetBrains, with a tall x-height, generous character proportions, and 138+ programming ligatures. Ranked as the #1 coding font in multiple 2025-2026 developer surveys.
- **Key features:** Programming ligatures, increased letter height for readability at small sizes, free and open source.
- **Example config:**
  ```
  font-family = JetBrains Mono
  font-size = 14
  font-thicken = true
  ```

### 2. Fira Code

- **Ghostty config name:** `Fira Code`
- **Pre-installed on macOS:** No -- must be downloaded
- **Install via Homebrew:** `brew install --cask font-fira-code`
- **Nerd Font variant:** `FiraCode Nerd Font` (install: `brew install --cask font-fira-code-nerd-font`)
- **Why #2:** Fira Code popularized programming ligatures and remains one of the most widely used coding fonts globally. It extends Mozilla's Fira Mono with the largest ligature set among coding fonts: over 200 programming ligatures covering operators like `!=`, `>=`, `->`, `===`, and `|>`. Frequently appears in Ghostty GitHub discussions and dotfiles. The naydenoff/ghostty-config preset system includes Fira Code as one of its four default font presets.
- **Key features:** 200+ ligatures (largest set), retina-ready, free and open source, excellent cross-platform support.
- **Note:** Some users reported ligature issues in early Ghostty versions with `FiraCode Nerd Font`; using the standard `Fira Code` family generally works without issues.
- **Example config:**
  ```
  font-family = Fira Code
  font-size = 14
  ```

### 3. Cascadia Code

- **Ghostty config name:** `Cascadia Code`
- **Pre-installed on macOS:** No -- must be downloaded (ships with Windows Terminal)
- **Install via Homebrew:** `brew install --cask font-cascadia-code`
- **Nerd Font variant:** `CaskaydiaCove Nerd Font` (install: `brew install --cask font-caskaydia-cove-nerd-font`)
- **Powerline variant:** `Cascadia Code PL` or `Cascadia Mono PL` (without ligatures: `Cascadia Mono`)
- **Why #3:** Microsoft's modern terminal and editor font. Designed specifically for terminal environments with Powerline glyph support built in. Confirmed to work well with ligatures in Ghostty. Appears in the naydenoff/ghostty-config preset system and in multiple community dotfiles. Users who had ligature issues with Fira Code in Ghostty reported success switching to Cascadia Code.
- **Key features:** Programming ligatures, Powerline glyphs, variable font support, designed for terminal use, free and open source.
- **Example config:**
  ```
  font-family = Cascadia Code
  font-size = 14
  ```

### 4. Iosevka

- **Ghostty config name:** `Iosevka` (or specific style like `Iosevka Heavy`)
- **Pre-installed on macOS:** No -- must be downloaded
- **Install via Homebrew:** `brew install --cask font-iosevka`
- **Nerd Font variant:** `Iosevka Nerd Font` (install: `brew install --cask font-iosevka-nerd-font`)
- **Why #4:** Referenced directly in Ghostty's official configuration documentation as an example font (with examples showing `Iosevka Heavy`). Highly customizable -- the font can be built from source with hundreds of stylistic variants. Popular among power users who want narrow, space-efficient characters. Appears in the naydenoff/ghostty-config preset system.
- **Key features:** Extremely narrow by default (fits more columns), highly customizable build system, many weight variants, free and open source.
- **Example config:**
  ```
  font-family = Iosevka
  font-size = 14
  ```

### 5. Berkeley Mono

- **Ghostty config name:** `Berkeley Mono` (or `Berkeley Mono Variable` for the variable font)
- **Pre-installed on macOS:** No -- must be purchased ($75 personal license)
- **Install:** Manual download from berkeleygraphics.com after purchase
- **Nerd Font variant:** `BerkeleyMono Nerd Font` (requires manual patching or community patch)
- **Why #5:** A premium, paid font that has developed a strong following in the Ghostty community. Multiple GitHub issues and discussions specifically address Berkeley Mono configuration in Ghostty (e.g., ghostty-org/ghostty#2140 on bold variant detection). Dedicated blog posts exist for configuring Berkeley Mono with Ghostty. Popular among developers willing to pay for a premium coding font.
- **Key features:** Balanced proportions, excellent readability, variable font support, premium design. Not free -- requires purchase.
- **Example config:**
  ```
  font-family = Berkeley Mono
  font-size = 16
  font-thicken = true
  ```

---

## Honorable Mentions

These fonts also appear frequently in Ghostty configurations but did not make the top 5:

| Font | Ghostty Config Name | Pre-installed on macOS | Notes |
|------|---------------------|----------------------|-------|
| MonoLisa | `MonoLisa` or `MonoLisa Variable` | No (paid, ~$59+) | Featured in multiple blog posts about Ghostty configs; often used with `font-thicken = true` |
| Hack | `Hack` | No (free) | Classic coding font; `brew install --cask font-hack` |
| Monaspace (GitHub) | `Monaspace Argon` / `Monaspace Neon` / etc. | No (free) | GitHub's font family with multiple styles; confirmed working in Ghostty |
| MesloLGM Nerd Font | `MesloLGM Nerd Font` | No (free) | Popular for Powerlevel10k/Starship users |
| SF Mono | `SF Mono` | Partially (bundled with Terminal.app and Xcode but not user-accessible by default) | Apple's system monospace font |
| Menlo | `Menlo` | Yes | Pre-installed macOS monospace font since 10.6 Snow Leopard |
| Monaco | `Monaco` | Yes | Pre-installed macOS monospace font since the original Macintosh (1984) |

---

## macOS Pre-installed vs. Downloadable Summary

| Font | Pre-installed on macOS? | How to Install |
|------|------------------------|----------------|
| JetBrains Mono | No (but embedded in Ghostty itself) | `brew install --cask font-jetbrains-mono` |
| Fira Code | No | `brew install --cask font-fira-code` |
| Cascadia Code | No (ships with Windows) | `brew install --cask font-cascadia-code` |
| Iosevka | No | `brew install --cask font-iosevka` |
| Berkeley Mono | No (paid, $75) | Manual download after purchase |
| Menlo | Yes | Pre-installed |
| Monaco | Yes | Pre-installed |
| SF Mono | Partially (in Terminal.app/Xcode) | Open Terminal.app or Xcode, then available system-wide |
| Courier New | Yes | Pre-installed |

---

## Community Configuration Patterns

### Common font-related settings seen in Ghostty configs:

```
# Most common minimal font setup
font-family = JetBrains Mono
font-size = 14
font-thicken = true

# Disabling ligatures (some users prefer this)
font-feature = -liga
font-feature = -calt

# Using a Nerd Font variant for icon support
font-family = JetBrainsMono Nerd Font

# Variable font with weight control
font-family = Berkeley Mono Variable
```

### naydenoff/ghostty-config Preset System
The community-maintained ghostty-config repository (github.com/naydenoff/ghostty-config) includes 4 font presets:
1. `jetbrains-mono`
2. `fira-code`
3. `cascadia-code`
4. `iosevka`

Users can switch between them using `./switch-config.sh`.

---

## Key Statistics

- JetBrains Mono has 138+ programming ligatures
- Fira Code has 200+ programming ligatures (largest set among coding fonts)
- Ghostty's default font (JetBrains Mono) requires zero configuration
- Ghostty ships with built-in Nerd Font glyphs, eliminating the need for patched Nerd Font variants in many cases
- Berkeley Mono costs $75 for a personal license
- MonoLisa starts at approximately $59 for a personal license
- Cascadia Code includes built-in Powerline glyphs
- Iosevka supports hundreds of stylistic variants via its custom build system
- Ghostty's `font-thicken = true` is one of the most commonly added font-related settings in macOS configurations
- SF Mono became macOS's default monospace font in OS X 10.11 El Capitan (2015), replacing Menlo
- Menlo replaced Monaco as macOS's default monospace font in OS X 10.6 Snow Leopard (2009)
- Monaco has shipped with every Mac since the original Macintosh in 1984

---

## Sources

- Ghostty Official Configuration Reference: https://ghostty.org/docs/config/reference
- Ghostty Official Configuration Guide: https://ghostty.org/docs/config
- Ghostty GitHub Repository: https://github.com/ghostty-org/ghostty
- naydenoff/ghostty-config (font presets): https://github.com/naydenoff/ghostty-config
- zerebos/ghostty-config (config generator): https://github.com/zerebos/ghostty-config
- Ghostty Font Discussion #4586 (Fira Code ligatures): https://github.com/ghostty-org/ghostty/discussions/4586
- Ghostty Issue #2140 (Berkeley Mono bold variant): https://github.com/ghostty-org/ghostty/issues/2140
- Ghostty Discussion #3492 (font-thicken on macOS): https://github.com/ghostty-org/ghostty/discussions/3492
- Ghostty Discussion #5948 (font rendering thickness): https://github.com/ghostty-org/ghostty/discussions/5948
- Berkeley Mono Ghostty Configuration Guide: https://michaelbommarito.com/wiki/programming/tools/ghostty-berkeley-font-configuration/
- My lil' Ghostty terminal config (birchtree.me): https://birchtree.me/blog/my-lil-ghosty-terminal-config-2/
- My minimal Ghostty config (ryangjchandler.co.uk): https://ryangjchandler.co.uk/posts/my-minimal-ghostty-config
- Minimal Ghostty Config (samuellawrentz.com): https://samuellawrentz.com/blog/minimal-ghostty-config/
- JetBrains Mono Official: https://www.jetbrains.com/lp/mono/
- Fira Code Repository: https://github.com/tonsky/FiraCode
- Homebrew font-jetbrains-mono: https://formulae.brew.sh/cask/font-jetbrains-mono
- Homebrew font-fira-code: https://formulae.brew.sh/cask/font-fira-code
- Best Coding Fonts 2026 (lexingtonthemes.com): https://lexingtonthemes.com/blog/best-coding-fonts-2026
- macOS System Monospace Fonts (ianyepan.github.io): https://ianyepan.github.io/posts/system-default-monospace-fonts-pt2/
