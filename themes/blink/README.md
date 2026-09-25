# Blink Shell themes

Phosphor CRT themes for [Blink Shell](https://blink.sh) (iOS), kept in sync
with the Ghostty retro profiles in `.dotfiles-private/config/ghostty/`.

| Theme | Ported from | Character |
|---|---|---|
| `phosphor-retro.js` | `retro` profile | Green phosphor (#8fe6ab / #0e1611) calibrated to Cool Retro Term CRT. |
| `phosphor-amber.js` | `amber` profile | Amber phosphor (#e9b56e / #18120b) warm phosphor display. |
| `phosphor-green.js` | `green` profile | Deep green phosphor (#65d998 / #08160f) monochrome terminal. |
| `phosphor-crt.js` | `retro` profile | Alias matching default retro CRT. |
| `phosphor-archive.js` | (standalone) | Monochrome vintage green. Every ANSI slot flattened to a green tone. |
| `tokyonight.js` | TokyoNight | TokyoNight Night modern palette. |
| `ambar.js` | Ghost CRT Live Studio | Amber phosphor, calibrated bloom/scanlines matched to real Blink hterm (`x-screen`). |

## Installing a theme

Blink imports themes by URL, not by file copy. In the app:

`config` > Appearance > Themes > `+` > paste the raw URL, then select the theme.

CRT profiles:
- Phosphor Retro:
  `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/phosphor-retro.js`
- Phosphor Amber:
  `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/phosphor-amber.js`
- Phosphor Green:
  `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/phosphor-green.js`

Additional themes:
- TokyoNight:
  `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/tokyonight.js`
- Phosphor Archive:
  `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/phosphor-archive.js`
- Ambar:
  `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/ambar.js`

The URL tracks `main`, so a re-import picks up any later edit. Pin a commit SHA
in place of `main` to freeze it.

## Installing the font (separate step)

A theme file sets colors only, so the font is its own import. Blink assigns
font families through a CSS stylesheet, not by taking a font file directly:
the "CSS FONT-FAMILY STYLESHEET" field wants the URL of a CSS file whose
`@font-face` rules point at the actual font files.

`terminess.css` in this directory is that file, and `fonts/` holds the four
woff2 faces it references.

In the app: `config` > Appearance > Fonts > `+`, then fill BOTH fields:

| Field | Value |
|---|---|
| Font-Family Name | `Terminess Pixel 24 Nerd Font Mono` |
| CSS FONT-FAMILY STYLESHEET | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/terminess-pixel.css` |

Tap Import, then Save, then pick the font under Appearance > Font.

The family name must match the `font-family` declared in the CSS character for
character. You can also use `Terminess Pixel Nerd Font Mono` as an alias.

### Terminess Nerd Font Mono (Standard smoothed outline)

| Field | Value |
|---|---|
| Font-Family Name | `Terminess Nerd Font Mono` |
| CSS FONT-FAMILY STYLESHEET | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/terminess.css` |

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

### Terminus (bitmap-style alternative)

`terminus.css` is a second, separate font stylesheet for the plain Terminus
TTF (not the Nerd Font patched variant above), served directly as `.ttf`
(no woff2 step, faces are already small).

| Field | Value |
|---|---|
| Font-Family Name | `Terminus` |
| CSS FONT-FAMILY STYLESHEET | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/terminus.css` |

### Nerd Fonts (Mono variants)

One stylesheet per family in `nerd/`. The faces are loaded straight from
`ryanoasis/nerd-fonts` pinned at tag `v3.5.1`, so no font binaries live in this
repo (DepartureMono is the exception: it is not in the nerd-fonts git tree, so
its single `.otf` is in `fonts/`). Only the `Mono` variant is used: it keeps the
icons one cell wide, which is what a terminal grid needs.

Blink > Appearance > Fonts > `+`: paste the stylesheet URL and type the
Font-Family Name exactly as below.

| Font-Family Name | Faces | CSS FONT-FAMILY STYLESHEET |
|---|---|---|
| `3270 Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/3270.css` |
| `AnonymicePro Nerd Font Mono` | Bold, BoldItalic, Italic, Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/anonymicepro.css` |
| `BigBlueTerm437 Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/bigblueterm437.css` |
| `BigBlueTermPlus Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/bigbluetermplus.css` |
| `BlexMono Nerd Font Mono` | Bold, BoldItalic, Italic, Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/blexmono.css` |
| `DepartureMono Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/departuremono.css` |
| `EnvyCodeR Nerd Font Mono` | Bold, Italic, Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/envycoder.css` |
| `GohuFont11 Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/gohufont11.css` |
| `GohuFont14 Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/gohufont14.css` |
| `GohuFontuni11 Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/gohufontuni11.css` |
| `GohuFontuni14 Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/gohufontuni14.css` |
| `Hack Nerd Font Mono` | Bold, BoldItalic, Italic, Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/hack.css` |
| `InconsolataGo Nerd Font Mono` | Bold, Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/inconsolatago.css` |
| `IosevkaTerm Nerd Font Mono` | Bold, BoldItalic, Italic, Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/iosevkaterm.css` |
| `Mononoki Nerd Font Mono` | Bold, BoldItalic, Italic, Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/mononoki.css` |
| `ProggyClean Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/proggyclean.css` |
| `ProggyCleanCE Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/proggycleance.css` |
| `ProggyCleanSZ Nerd Font Mono` | Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/proggycleansz.css` |
| `Terminess Nerd Font Mono` | Bold, BoldItalic, Italic, Regular | `https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/themes/blink/nerd/terminess.css` |

Not included: Monaspice (Ar/Kr/Ne/Rn/Xe) and IosevkaTermSlab. They exist only in
the release zips, not in the nerd-fonts git tree, and their faces add up to
~110 MB, too heavy to vendor here.

## Why the variations are separate

`phosphor-archive` remaps all 16 ANSI slots to greens, which is what
cool-retro-term does at `chromaColor 0`. The CRT profiles (`retro`, `amber`,
`green`) correspond to the calibrated phosphor CRT monitors matching Ghostty.
Keeping all variations available gives full flexibility on iPad.
