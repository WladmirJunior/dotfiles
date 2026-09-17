// Phosphor Amber: Blink Shell CRT theme
// Ported from Ghostty amber profile
// Warm amber phosphor with dark amber-tinted CRT background.

const black        = '#18120b';
const red          = '#a57845';
const green        = '#c49a5f';
const yellow       = '#e0b472';
const blue         = '#9e8056';
const magenta      = '#b58c58';
const cyan         = '#c6a275';
const white        = '#e9b56e';

const lightBlack   = '#745535';
const lightRed     = '#cf9b60';
const lightGreen   = '#e7bc7e';
const lightYellow  = '#f5d4a0';
const lightBlue    = '#caa77b';
const lightMagenta = '#ddb887';
const lightCyan    = '#edd0a4';
const lightWhite   = '#f8dfb8';

t.prefs_.set('color-palette-overrides', [
  black, red, green, yellow,
  blue, magenta, cyan, white,
  lightBlack, lightRed, lightGreen, lightYellow,
  lightBlue, lightMagenta, lightCyan, lightWhite
]);

t.prefs_.set('background-color', '#18120b');
t.prefs_.set('foreground-color', '#e9b56e');
t.prefs_.set('cursor-color', '#e9b56e');
t.prefs_.set('cursor-blink', true);
