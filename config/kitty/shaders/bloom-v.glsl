// Multi-pass Bloom + Ambient Light + Static Noise + Glow Line for Ghostty CRT - Pass 2
// Reads Pass 1 output:
//   R: 100% crisp original glyph luminance
//   G: Horizontally blurred luminance
// Computes 2D Gaussian bloom,
// simulates CRT curved glass Ambient Light (Cool Retro Term 20%),
// generates animated Static Noise, and adds the rolling electron Glow Line.

// ============================================================================
// CRT Retro Parameters - Ajuste livremente estes parâmetros:
// ============================================================================
#define BLOOM_STRENGTH   0.50   // Intensidade do Bloom (0.50 = 50% Cool Retro Term)
#define AMBIENT_LIGHT    0.20   // Reflexo ambiente no tubo de vidro (0.20 = 20%)
#define TUBE_FLOOR       0.018  // Fundo do tubo (0.00 = preto puro, 0.018 = verde escuro suave CRT)
#define STATIC_NOISE     0.025  // Estática animada de TV (0.025 = suave)
#define GLOW_LINE        0.05   // Linha de varredura descendo (0.05 = 5%)
#define BRIGHTNESS       0.92   // Brilho global (1.00 = normal, 0.92 = suave)
#define CONTRAST         1.00   // Contraste global
// ============================================================================

const float w_center = 0.025220;
const float offsets[20] = float[20](
    1.49854, 3.49658, 5.49463, 7.49268, 9.49072,
    11.48877, 13.48682, 15.48487, 17.48292, 19.48097,
    21.47902, 23.47707, 25.47512, 27.47317, 29.47122,
    31.46928, 33.46733, 35.46539, 37.46344, 39.46150
);
const float weights[20] = float[20](
    0.050195, 0.049225, 0.047526, 0.045175, 0.042275,
    0.038949, 0.035329, 0.031548, 0.027736, 0.024007,
    0.020458, 0.017163, 0.014176, 0.011527, 0.009228,
    0.007273, 0.005644, 0.004311, 0.003243, 0.002401
);

// Cool Retro Term smooth noise generator (procedural version of allNoise512.png)
float crt_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = fract(sin(dot(i,                  vec2(12.9898, 78.233))) * 43758.5453);
    float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
    float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
    float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Cool Retro Term random noise generator for fine spatial dithering
float rand2(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    ivec2 iCoord = ivec2(fragCoord.xy);
    vec4 p1 = texelFetch(iChannel0, iCoord, 0);

    float baseLuma = p1.r;

    // Filter G vertically to complete continuous 2D Gaussian bloom
    vec2 uv = fragCoord.xy / iResolution.xy;
    float dy = 1.0 / iResolution.y;

    float blur2D = p1.g * w_center;
    for (int i = 0; i < 20; i++) {
        float off = offsets[i] * dy;
        float w = weights[i];
        float s1 = texture(iChannel0, vec2(uv.x, uv.y + off)).g;
        float s2 = texture(iChannel0, vec2(uv.x, uv.y - off)).g;
        blur2D += (s1 + s2) * w;
    }

    // 1. Bloom halo:
    float bloomGlow = clamp(blur2D * (BLOOM_STRENGTH * 2.5), 0.0, 0.45);

    // Combine base text + diffuse bloom atmospheric halo
    float finalLuma = (baseLuma + bloomGlow) * BRIGHTNESS;

    // 2. Ambient Light (curved glass dome reflection) & Tube Floor:
    float dome = clamp(pow(uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y) * 25.0, 0.5), 0.0, 1.25);
    float glass = (AMBIENT_LIGHT * 0.28) * dome;
    finalLuma = max(finalLuma, TUBE_FLOOR + glass);

    // 3. Static Noise (animated CRT snow):
    if (STATIC_NOISE > 0.0) {
        vec2 cc = vec2(0.5) - uv;
        float distance = length(cc);
        float vignette = clamp(1.0 - distance * 1.3, 0.0, 1.0);

        vec2 animOffset = vec2(fract(iTime / 0.051), fract(iTime / 0.237));
        vec2 noiseUV = uv * (iResolution.xy * 0.4 / 256.0) + animOffset;
        float snow = crt_noise(noiseUV * 256.0);

        finalLuma += snow * STATIC_NOISE * vignette;
    }

    // 4. Glow Line (rolling electron beam scanning from top to bottom):
    if (GLOW_LINE > 0.0) {
        float linePos = (iResolution.y + 160.0) * fract(iTime * 0.15) - 80.0;
        float dist = linePos - fragCoord.y;
        if (dist > 0.0 && dist < 140.0) {
            float beam = smoothstep(140.0, 0.0, dist);
            finalLuma += beam * (GLOW_LINE * 0.35);
        }
    }

    // 5. Authentic Cool Retro Term phosphor grain (spatial dithering):
    float noise = rand2(uv) - 0.5;
    float grainWeight = smoothstep(0.005, 0.030, finalLuma);
    float grainAmp = mix(0.015, 0.035, clamp(finalLuma * 1.5, 0.0, 1.0));
    finalLuma = clamp(finalLuma + noise * grainAmp * grainWeight, 0.0, 1.0);

    // Output monochrome grayscale.
    // The native Metal pass (crt_chroma + crt_scanlines) applies scanlines and phosphor tint.
    fragColor = vec4(vec3(finalLuma), 1.0);
}
