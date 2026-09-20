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

// 3. Efeitos CRT calibrados (sem bordas/cantos marcados e com texto 100% legivel)
const crtCss = `
  /* Phosphor Bloom calibrado: núcleo vívido com halo controlado */
  x-row, span {
    text-shadow: 0 0 1px #59ff8e, 0 0 3.5px rgba(89, 255, 142, 0.45);
  }

  /* Scanlines CRT contínuas em tela cheia (sem cortar caracteres nem cantos marcados) */
  x-scrollport::before {
    content: " ";
    display: block;
    position: absolute;
    top: 0; left: 0; right: 0; bottom: 0;
    background: linear-gradient(
      rgba(0, 0, 0, 0) 50%,
      rgba(0, 0, 0, 0.22) 50%
    );
    background-size: 100% 3px;
    pointer-events: none;
    z-index: 10;
  }
`;

t.prefs_.set('user-css-text', crtCss);
