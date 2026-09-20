// Ghost CRT: Blink Shell Theme
// Ported from Ghostty ghost profile + Bloom/CRT shaders
// Green phosphor (#59ff8e) with CSS-emulated Bloom, Scanlines & Ambient Tube Glass.

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

// 1. Paleta ANSI calibrada (16 tons de verde CRT)
t.prefs_.set('color-palette-overrides', [
  black, red, green, yellow,
  blue, magenta, cyan, white,
  lightBlack, lightRed, lightGreen, lightYellow,
  lightBlue, lightMagenta, lightCyan, lightWhite
]);

// 2. Cores base do perfil ghost
t.prefs_.set('background-color', '#000000');
t.prefs_.set('foreground-color', '#59ff8e');
t.prefs_.set('cursor-color', '#59ff8e');
t.prefs_.set('cursor-blink', true);

// 3. Remove os efeitos CSS invasivos (vinheta nos cantos da janela, scanlines e blur)
// Em telas Retina mobile, o contraste nativo do painel OLED (#59ff8e sobre #000000)
// entrega a estetica CRT com nitidez total e sem artefatos de borda.
t.prefs_.set('user-css-text', '');
