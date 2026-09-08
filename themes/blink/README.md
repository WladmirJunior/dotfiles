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

A theme file sets colors only: `t.prefs_.set` has no font-install capability,
and iOS will not take a font from a JS file. The font is its own import.

The Ghostty CRT profile uses **Terminess Nerd Font** (the TERMINESS_SCALED
setting in cool-retro-term). On macOS it comes from the Brewfile step
(`steps/apps/macos/development.sh`), but iOS needs its own copy:

`config` > Appearance > Fonts > `+` > paste the URL of a `.woff2` or `.otf`.

Blink wants a single web-font file, not the multi-file release zip that
Nerd Fonts ships, so point it at one file from the release rather than the
archive. Then set it under Appearance > Font.

Nerd Fonts releases: https://github.com/ryanoasis/nerd-fonts/releases

## Why the two are not merged

`phosphor-archive` remaps all 16 ANSI slots to greens, which is what
cool-retro-term does at `chromaColor 0`. `phosphor-crt` corresponds to
`chromaColor 1`: the tube tints the phosphor, but the terminal still emits real
colors. Keeping both documents the difference instead of losing it in a diff.
