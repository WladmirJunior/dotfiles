# Blink Shell themes

Green-phosphor themes for [Blink Shell](https://blink.sh) (iOS), kept in sync
with the Ghostty retro profiles in `.dotfiles-private/config/ghostty/`.

| Theme | Ported from | Character |
|---|---|---|
| `phosphor-crt.js` | `config-retro-crt` | Full chroma. ANSI keeps real hues, only the default foreground is phosphor green. Matches the cool-retro-term look. |
| `phosphor-archive.js` | (standalone) | Monochrome. Every ANSI slot flattened to a green tone, so app colors lose separation. |

`phosphor-crt` is the one that matches the Ghostty setup in daily use.

## Installing a theme

Blink imports themes by URL, not by file copy. In the app:

`config` > Appearance > Themes > `+` > paste the raw URL, then select the theme.

```
https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/phosphor-crt.js
```

The URL tracks `main`, so a re-import picks up any later edit. Pin a commit SHA
in place of `main` to freeze it.

## Installing the font (separate step)

A theme file sets colors only, so the font is its own import. Blink assigns
font families **through a CSS stylesheet**, not by taking a font file directly:
the "CSS FONT-FAMILY STYLESHEET" field wants the URL of a CSS file whose
`@font-face` rules point at the actual font files.

`terminess.css` in this directory is that file, and `fonts/` holds the four
woff2 faces it references.

In the app: `config` > Appearance > Fonts > `+`, then fill BOTH fields:

| Field | Value |
|---|---|
| Font-Family Name | `Terminess Nerd Font Mono` |
| CSS FONT-FAMILY STYLESHEET | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/terminess.css` |

Tap Import, then Save, then pick the font under Appearance > Font.

The family name must match the `font-family` declared in the CSS character for
character. It is the name embedded in the font (name ID 1), verified against
the source TTF, not a label chosen here.

### Where the woff2 files came from

macOS gets this font from the Brewfile step
(`steps/apps/macos/development.sh`: `font-terminess-ttf-nerd-font`), which
installs `.ttf` files of about 2.1 MB each. Those were converted to woff2 with
`woff2_compress` (brew formula `woff2`), roughly halving each one to ~1 MB, so
iOS pulls a web-font format over HTTP instead of a desktop font.

To regenerate after a font upgrade:

```sh
brew install woff2
cd "$(mktemp -d)"
cp ~/Library/Fonts/TerminessNerdFontMono-Regular.ttf .
woff2_compress TerminessNerdFontMono-Regular.ttf
# repeat for Bold, Italic, BoldItalic, then move the .woff2 into themes/blink/fonts/
```

## Why the two are not merged

`phosphor-archive` remaps all 16 ANSI slots to greens, which is what
cool-retro-term does at `chromaColor 0`. `phosphor-crt` corresponds to
`chromaColor 1`: the tube tints the phosphor, but the terminal still emits real
colors. Keeping both documents the difference instead of losing it in a diff.
