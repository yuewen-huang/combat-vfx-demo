// Material-specific geometry, surface structure and light response. Formation stays shared.
uniform int piece_material = 0;
uniform float leaf_curl = 0.55;
uniform float leaf_sway = 1.0;
uniform float feather_bend = 0.65;
uniform float feather_split = 0.45;
uniform float sand_grain = 1.0;
uniform float sand_dust = 0.7;
uniform float sand_settle = 1.0;
varying vec3 v_seed;
varying float v_dust;

float inside(float distance) {
    float aa = max(fwidth(distance), 0.002);
    return smoothstep(-aa, aa, distance);
}

vec4 piece_surface(vec2 uv, vec3 normal, vec3 along, vec3 across, float material_opacity, float tone, vec3 seed, float dust) {
    float x = uv.x;
    float y = (uv.y - 0.5) * 2.0;
    vec3 view = vec3(0.0, 0.0, -1.0);
    vec3 n = normalize(normal);
    float facing = dot(n, view);
    float back = step(facing, 0.0);
    if (facing < 0.0) { n = -n; }
    vec3 key = normalize(KEY);
    vec3 color = col_body;
    float mask = 0.0;
    float alpha_scale = 1.0;
    if (piece_material == 0) {
        // Curled leaf, pointed tip, serrated edge, central vein and diagonal side veins.
        float envelope = pow(max(sin(3.14159 * clamp((x - 0.08) / 0.92, 0.0, 1.0)), 0.0), 0.72);
        envelope *= 0.87 + 0.07 * sin(x * 91.0 + seed.x * 8.0);
        float lobes = mix(1.0, 0.75 + 0.25 * cos(x * 23.0), step(0.65, seed.z));
        float edge = envelope * lobes - abs(y);
        float leaf = inside(min(x - 0.09, edge));
        float stem = inside(min(min(x - 0.005, 0.20 - x), 0.028 - abs(y + 0.12 * (0.15 - x))));
        mask = max(leaf, stem);
        vec3 curved = normalize(n + normalize(across) * y * leaf_curl * 1.8 + normalize(along) * sin(x * 3.14159) * leaf_curl);
        float diffuse = max(dot(curved, key), 0.0);
        float main_vein = exp(-abs(y) * 55.0);
        float branches = pow(max(0.0, cos((x - abs(y) * 0.18) * 48.0)), 28.0) * smoothstep(0.9, 0.15, abs(y));
        float transmit = abs(dot(n, normalize(BACK))) * (0.3 + 0.5 * back);
        float mottles = sin(x * 39.0 + seed.x * 20.0) * sin(y * 17.0 + seed.z * 12.0) * 0.10;
        color = mix(col_deep, col_body, 0.38 + diffuse * 0.48 + mottles);
        color = mix(color, col_light, (main_vein * 0.4 + branches * 0.19 + transmit * 0.20));
        color *= mix(1.0, 0.75, back);
        color = mix(color, col_deep, (1.0 - smoothstep(0.0, 0.08, edge)) * leaf * 0.28);
    } else if (piece_material == 1) {
        // Asymmetric vanes about an off-centre shaft; angled barbs break at the outer edge.
        float shaft_y = 0.12 * sin(x * 3.14159);
        float yy = y - shaft_y;
        float envelope = pow(max(sin(3.14159 * clamp((x - 0.25) / 0.75, 0.0, 1.0)), 0.0), 0.90);
        envelope *= yy < 0.0 ? 0.42 : 0.95;
        float barbs = 0.5 + 0.5 * sin((x - abs(yy) * 0.17) * 150.0);
        float split = feather_split * pow(abs(yy) / max(envelope, 0.1), 2.0) * 0.22 * barbs;
        float vane = inside(min(x - 0.25, envelope - abs(yy) - split));
        float shaft = inside(min(min(x - 0.015, 0.97 - x), 0.035 * (1.0 - x * 0.75) - abs(yy)));
        mask = max(vane * (0.78 + 0.22 * smoothstep(0.1, 0.45, barbs)), shaft);
        vec3 curved = normalize(n + normalize(across) * yy * 0.4 + normalize(along) * feather_bend * (x - 0.25));
        float diffuse = abs(dot(curved, key));
        float anisotropic = pow(max(dot(normalize(along), normalize(key + view)), 0.0), 6.0) * 0.22;
        color = mix(col_body * 0.6, col_light, 0.30 + diffuse * 0.45 + anisotropic);
        color *= 0.90 + 0.10 * barbs;
        color = mix(color, col_glint, shaft * 0.58);
        color += col_light * pow(1.0 - abs(facing), 2.0) * 0.12;
    } else {
        vec2 q = uv - 0.5;
        if (dust > 0.5) {
            // Soft density, not light emission: repeated darkened layers occlude the rear.
            float billow = exp(-dot(q, q) * 13.0);
            float noise = 0.68 + 0.18 * sin(q.x * 19.0 + time * 0.8 + seed.x * 20.0) * sin(q.y * 14.0 - time * 0.6);
            mask = billow * noise;
            alpha_scale = 0.045 + 0.045 * sand_dust;
            color = mix(col_body, col_light, 0.28 + tone * 0.22);
        } else {
            // Coarse grains have hard angular facets and a size-dependent settling path.
            float edge = 0.45 - max(abs(q.x + q.y * 0.22), abs(q.y - q.x * 0.15));
            mask = inside(edge);
            float facet = step(q.x * 0.6, q.y);
            color = mix(col_deep, col_light, 0.35 + 0.28 * facet + seed.z * 0.2);
            color += col_glint * step(0.96, seed.y) * 0.12;
        }
    }
    if (style == 1) { color = floor(color * 5.0 + 0.5) / 5.0; }
    float alpha = clamp(mask * material_opacity * alpha_scale, 0.0, 1.0);
    return vec4(color * alpha, alpha);
}
