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

// 3. Emulação dos Shaders CRT via WebKit CSS (Bloom, Scanlines & Vidro Curvo)
const crtCss = `
  /* Bloom / Phosphor Glow: halo suave de fósforo */
  x-row, span {
    text-shadow: 0 0 2px #59ff8e, 0 0 8px rgba(89, 255, 142, 0.45);
  }

  /* Scanlines CRT: linhas horizontais alternadas de 1px */
  x-screen::before {
    content: " ";
    display: block;
    position: absolute;
    top: 0; left: 0; right: 0; bottom: 0;
    background: repeating-linear-gradient(
      0deg,
      rgba(0, 0, 0, 0.22) 0px,
      rgba(0, 0, 0, 0.22) 1px,
      transparent 1px,
      transparent 2px
    );
    pointer-events: none;
    z-index: 100;
  }

  /* Vidro Curvo / Vinheta / Luz ambiente CRT */
  x-screen::after {
    content: " ";
    display: block;
    position: absolute;
    top: 0; left: 0; right: 0; bottom: 0;
    background: radial-gradient(circle at center, transparent 65%, rgba(0, 15, 6, 0.45) 100%);
    box-shadow: inset 0 0 25px rgba(0, 40, 15, 0.6);
    pointer-events: none;
    z-index: 101;
  }
`;

t.prefs_.set('user-css-text', crtCss);
