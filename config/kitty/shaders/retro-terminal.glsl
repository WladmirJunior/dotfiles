// Original shader collected from: https://www.shadertoy.com/view/WsVSzV
// Licensed under Shadertoy's default since the original creator didn't provide any license. (CC BY NC SA 3.0)
// Slight modifications were made to give a green-ish effect.

float warp = 0.25; // simulate curvature of CRT monitor
float scan = 0.20; // simulate darkness between scanlines
float boost = 1.35; // overall brightness compensation

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // squared distance from center
    vec2 uv = fragCoord / iResolution.xy;
    vec2 dc = abs(0.5 - uv);
    dc *= dc;
    
    // warp the fragment coordinates
    uv.x -= 0.5; uv.x *= 1.0 + (dc.y * (0.3 * warp)); uv.x += 0.5;
    uv.y -= 0.5; uv.y *= 1.0 + (dc.x * (0.4 * warp)); uv.y += 0.5;

    // sample inside boundaries, otherwise set to black
    if (uv.y > 1.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0)
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    else
    {
        // determine if we are drawing in a scanline
        float apply = abs(sin(fragCoord.y) * 0.5 * scan);
        
        // sample the texture and apply a green phosphor tint
        vec3 color = texture(iChannel0, uv).rgb;
        vec3 greenTint = vec3(0.45, 1.0, 0.55); // keep red/blue partially so dim colors stay legible

        // mix the tinted color with black based on scanline intensity
        fragColor = vec4(mix(color * greenTint * boost, vec3(0.0), apply), 1.0);
    }
}
