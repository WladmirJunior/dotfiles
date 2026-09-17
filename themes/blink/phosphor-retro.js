// Phosphor Retro: Blink Shell CRT theme
// Ported from Ghostty retro profile / Cool Retro Term calibration
// Green phosphor with calibrated dark green glass background.

const black        = '#0e1611';
const red          = '#649a75';
const green        = '#80cb98';
const yellow       = '#9ed8ac';
const blue         = '#5c987c';
const magenta      = '#79b48d';
const cyan         = '#83c9a8';
const white        = '#8fe6ab';

const lightBlack   = '#426c50';
const lightRed     = '#8ac59b';
const lightGreen   = '#9cecb5';
const lightYellow  = '#b5f4c9';
const lightBlue    = '#85c8a4';
const lightMagenta = '#a0d8b1';
const lightCyan    = '#a2e8c2';
const lightWhite   = '#c5f7d5';

t.prefs_.set('color-palette-overrides', [
  black, red, green, yellow,
  blue, magenta, cyan, white,
  lightBlack, lightRed, lightGreen, lightYellow,
  lightBlue, lightMagenta, lightCyan, lightWhite
]);

t.prefs_.set('background-color', '#0e1611');
t.prefs_.set('foreground-color', '#8fe6ab');
t.prefs_.set('cursor-color', '#8fe6ab');
t.prefs_.set('cursor-blink', true);
