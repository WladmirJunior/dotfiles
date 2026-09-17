// TokyoNight: Blink Shell theme
// Matches Neovim tokyonight-night palette

const black        = '#15161e';
const red          = '#f7768e';
const green        = '#9ece6a';
const yellow       = '#e0af68';
const blue         = '#7aa2f7';
const magenta      = '#bb9af7';
const cyan         = '#7dcfff';
const white        = '#a9b1d6';

const lightBlack   = '#414868';
const lightRed     = '#f7768e';
const lightGreen   = '#9ece6a';
const lightYellow  = '#e0af68';
const lightBlue    = '#7aa2f7';
const lightMagenta = '#bb9af7';
const lightCyan    = '#7dcfff';
const lightWhite   = '#c0caf5';

t.prefs_.set('color-palette-overrides', [
  black, red, green, yellow,
  blue, magenta, cyan, white,
  lightBlack, lightRed, lightGreen, lightYellow,
  lightBlue, lightMagenta, lightCyan, lightWhite
]);

t.prefs_.set('background-color', '#1a1b26');
t.prefs_.set('foreground-color', '#c0caf5');
t.prefs_.set('cursor-color', '#c0caf5');
t.prefs_.set('cursor-blink', true);
