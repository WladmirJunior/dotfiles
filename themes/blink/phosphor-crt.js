// Phosphor CRT — Blink Shell theme
// Ported from the Ghostty `config-retro-crt` profile, which itself came from
// the cool-retro-term export "Ghostty Retro.json".
//
// The distinction from phosphor-archive.js: chromaColor 1 in cool-retro-term
// means NO monochrome remap. The ANSI palette keeps real hue separation, and
// only the default foreground is phosphor green. phosphor-archive flattened
// every ANSI slot to a green tone, which is why app colors read as muddy.
//
// Pair with Terminess Nerd Font (cool-retro-term's TERMINESS_SCALED). Blink
// cannot install fonts from this file: add the font separately, see
// themes/blink/README.md.

const black        = '#0a120a';
const red          = '#c65f5f';
const green        = '#3cff7a';
const yellow       = '#d0b873';
const blue         = '#5f8fc6';
const magenta      = '#b06fb0';
const cyan         = '#5fc6c6';
const white        = '#c8ffc8';

const lightBlack   = '#1a3a1a';
const lightRed     = '#e07f7f';
const lightGreen   = '#7fffa8';
const lightYellow  = '#e8d89f';
const lightBlue    = '#7fafe0';
const lightMagenta = '#c88fc8';
const lightCyan    = '#8fe0e0';
const lightWhite   = '#e8ffe8';

t.prefs_.set('color-palette-overrides', [
  black, red, green, yellow,
  blue, magenta, cyan, white,
  lightBlack, lightRed, lightGreen, lightYellow,
  lightBlue, lightMagenta, lightCyan, lightWhite
]);

// Background is lifted off pure black to emulate cool-retro-term's
// ambientLight 0.1988 tube glow.
t.prefs_.set('background-color', '#0a120a');
t.prefs_.set('foreground-color', '#3cff7a');
t.prefs_.set('cursor-color', '#3cff7a');
t.prefs_.set('cursor-blink', true);
