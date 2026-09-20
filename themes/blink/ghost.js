// Ghost CRT: Blink Shell Theme
// Ported from Ghostty ghost profile + Calibrated WebKit CRT Shaders
// Green phosphor (#59ff8e) with Bloom & Scanlines, calibrated for mobile Retina.

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

// 3. Efeitos CRT calibrados
const crtCss = `
x-row { text-shadow: 0 0 1.5px rgba(89,255,142,0.85); }
`;

t.prefs_.set('user-css-text', crtCss);
