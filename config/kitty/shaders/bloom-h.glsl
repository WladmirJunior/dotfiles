// Multi-pass Bloom for Ghostty CRT - Pass 1 (Horizontal Gaussian)
// 20 bilinear pairs covering 41 physical pixels radius (83px diameter)
// with mathematically verified monotonic falloff (zero ripples, zero gaps).

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

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    ivec2 iCoord = ivec2(fragCoord.xy);
    vec4 centerTexel = texelFetch(iChannel0, iCoord, 0);

    float centerLuma = dot(centerTexel.rgb, vec3(0.21, 0.72, 0.04));

    vec2 uv = fragCoord.xy / iResolution.xy;
    float dx = 1.0 / iResolution.x;

    float blurH = centerLuma * w_center;
    for (int i = 0; i < 20; i++) {
        float off = offsets[i] * dx;
        float w = weights[i];
        vec4 s1 = texture(iChannel0, vec2(uv.x + off, uv.y));
        vec4 s2 = texture(iChannel0, vec2(uv.x - off, uv.y));
        float l1 = dot(s1.rgb, vec3(0.21, 0.72, 0.04));
        float l2 = dot(s2.rgb, vec3(0.21, 0.72, 0.04));
        blurH += (l1 + l2) * w;
    }

    // Output:
    // R = original crisp luminance
    // G = horizontally blurred luminance
    fragColor = vec4(centerLuma, blurH, 0.0, 1.0);
}
