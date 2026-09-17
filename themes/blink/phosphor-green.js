// Phosphor Green: Blink Shell CRT theme
// Ported from Ghostty green profile
// Cooler, deep monochrome green phosphor terminal.

const black        = '#08160f';
const red          = '#4c9c6f';
const green        = '#5dc98b';
const yellow       = '#87d9a4';
const blue         = '#458e6c';
const magenta      = '#60b082';
const cyan         = '#65bda0';
const white        = '#65d998';

const lightBlack   = '#386b4c';
const lightRed     = '#75c294';
const lightGreen   = '#85e9af';
const lightYellow  = '#a0edbf';
const lightBlue    = '#71c6a3';
const lightMagenta = '#8ed4ab';
const lightCyan    = '#8de4bd';
const lightWhite   = '#b6f5d0';

t.prefs_.set('color-palette-overrides', [
  black, red, green, yellow,
  blue, magenta, cyan, white,
  lightBlack, lightRed, lightGreen, lightYellow,
  lightBlue, lightMagenta, lightCyan, lightWhite
]);

t.prefs_.set('background-color', '#08160f');
t.prefs_.set('foreground-color', '#65d998');
t.prefs_.set('cursor-color', '#65d998');
t.prefs_.set('cursor-blink', true);
