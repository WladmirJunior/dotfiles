// Phosphor Archive — Blink Shell theme
// Inspired by dim late-1970s/early-1980s CRT terminals:
// green phosphor, deep green-black glass, muted industrial ANSI accents.

const black        = '#06110D';
const red          = '#8F493D';
const green        = '#3F8A68';
const yellow       = '#9B8755';
const blue         = '#456C68';
const magenta      = '#725D63';
const cyan         = '#5D9D82';
const white        = '#B6C5AF';

const lightBlack   = '#1D322A';
const lightRed     = '#C06A56';
const lightGreen   = '#67C79C';
const lightYellow  = '#D0B873';
const lightBlue    = '#729B91';
const lightMagenta = '#9A7D82';
const lightCyan    = '#8ACDAE';
const lightWhite   = '#D7F0DD';

t.prefs_.set('color-palette-overrides', [
  black, red, green, yellow,
  blue, magenta, cyan, white,
  lightBlack, lightRed, lightGreen, lightYellow,
  lightBlue, lightMagenta, lightCyan, lightWhite
]);

// Sampled toward the darkest green-black and phosphor highlights
// visible in the reference CRT photographs.
t.prefs_.set('background-color', '#06110D');
t.prefs_.set('foreground-color', '#A8E6C7');
t.prefs_.set('cursor-color', 'rgba(143, 224, 184, 0.78)');
t.prefs_.set('cursor-blink', true);
