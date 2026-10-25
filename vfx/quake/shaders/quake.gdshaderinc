// Shared by every ground-impact layer. Shapes do not carry colours: each vertex colour is
//   r = value (0 darkest … 1 white-hot), g = pattern / 8, b = pattern parameter, a = alpha
// and UV holds the pattern's own coordinates. The value is looked up in `ramp` (the
// material's colours, or any recolour), then shaped by the art style:
//   style 0 写实: smooth;  1 赛璐璐: hard value and alpha bands;  2 像素: value steps
//   (the pixel grain itself comes from rendering the layers small, see pixel.gdshader).
// mode 1 (dust): colour is `tint` shaded by r instead of the ramp.
uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform int style = 0;
uniform int mode = 0;
uniform float time = 0.0;
// 0–1: how many noise octaves patterns may use (the detail tier).
uniform float detail = 1.0;
// 兜底 (no graphics card): patterns keep their shapes but drop per-pixel noise.
uniform bool lite = false;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float total = noise(p) * 0.55;
	total += noise(p * 2.03 + 17.1) * 0.28;
	if (detail > 0.5) total += noise(p * 4.1 + 31.7) * 0.17;
	else total += 0.085;
	return total;
}

float bands(float x, float steps) {
	float b = x * steps;
	return (floor(b) + smoothstep(0.42, 0.58, fract(b))) / steps;
}

// Patterns modulate value and alpha from UV. 0 is flat.
//   3 energy filament (bolts, sparks): UV.x along, UV.y −1…1 across; b = flicker seed.
//   5 lava: UV = position in px (so touching blobs share one flowing surface);
//     b = heat (1 molten white-hot … 0 cooled into a dark crust with glowing seams).
//   6 stone: UV = position in px; chipped facets, grain and a few hairline cracks.
//     b = 1 shows a soil cross-section (layered strata) instead.
//   7 ice: UV = position in px; streaks frozen inside and bright hairline fractures.
// The cheap version of every pattern, for software rendering: same silhouettes, no noise.
void pattern_lite(int id, vec2 uv, float param, inout float value, inout float alpha) {
	if (id == 3) {
		float across = abs(uv.y);
		float core = exp(-across * across * 26.0);
		value = mix(value * 0.82, 1.0, core * 0.85);
		alpha *= clamp(exp(-across * across * 3.2) * 0.75 + core, 0.0, 1.0);
	} else if (id == 5) {
		float heat = clamp(param, 0.0, 1.0);
		float molten = mix(0.8, 1.0, noise(uv * 0.05 + vec2(0.0, time * 0.4)));
		float cover = smoothstep(heat * 1.1 - 0.12, heat * 1.1 - 0.02, noise(uv * 0.055 + 11.3));
		value = mix(molten, 0.15, cover);
	}
}

void pattern(int id, vec2 uv, float param, inout float value, inout float alpha) {
	if (lite) {
		pattern_lite(id, uv, param, value, alpha);
		return;
	}
	if (id == 3) {
		float across = abs(uv.y);
		float core = exp(-across * across * 26.0);
		float halo = exp(-across * across * 3.2);
		float grain = fbm(vec2(uv.x * 0.08 + param * 13.0, time * 9.0 + param * 7.0));
		value = mix(value * 0.82, 1.0, core * (0.75 + 0.25 * grain));
		alpha *= clamp(halo * (0.55 + 0.45 * grain) + core, 0.0, 1.0);
	} else if (id == 5) {
		float heat = clamp(param, 0.0, 1.0);
		float flow = fbm(uv * 0.035 + vec2(0.0, time * 0.9));
		float churn = fbm(uv * 0.08 + vec2(time * 0.35, -time * 0.2) + flow * 1.7);
		float molten = mix(0.76, 1.0, churn * mix(0.7, 1.15, heat));
		// Crust islands are fixed in place and spread as the lava cools.
		float islands = fbm(uv * 0.055 + 11.3);
		float cover = smoothstep(heat * 1.1 - 0.12, heat * 1.1 - 0.02, islands);
		float seam = 1.0 - smoothstep(0.0, 0.06, abs(islands - (heat * 1.1 - 0.07)));
		value = mix(molten, 0.12 + 0.12 * churn, cover);
		value = max(value, seam * mix(0.8, 0.9, heat) * step(0.02, heat));
	} else if (id == 6) {
		vec2 cellp = uv * 0.06;
		vec2 i = floor(cellp);
		vec2 f = fract(cellp);
		float near = 8.0;
		float second = 8.0;
		float cell = 0.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 g = vec2(float(x), float(y));
				vec2 r = g + vec2(hash(i + g), hash(i + g + 19.1)) - f;
				float d = dot(r, r);
				if (d < near) { second = near; near = d; cell = hash(i + g + 7.7); }
				else if (d < second) { second = d; }
			}
		}
		float edge = sqrt(second) - sqrt(near);
		float grain = noise(uv * 0.35);
		value += (cell - 0.5) * 0.09 + (grain - 0.5) * 0.07 * detail;
		float crack = (1.0 - smoothstep(0.0, 0.07, edge)) * step(0.6, cell) * step(0.5, detail);
		value *= 1.0 - crack * 0.4;
		if (param > 0.5) value *= 0.82 + 0.18 * sin(uv.y * 0.55 + noise(uv * 0.04) * 5.0);
	} else if (id == 7) {
		float streak = noise(vec2(uv.x * 0.09, uv.y * 0.018));
		float frost = noise(uv * 0.22);
		value += (streak - 0.5) * 0.18 + (frost - 0.5) * 0.06 * detail;
		vec2 cellp = uv * 0.045;
		vec2 i = floor(cellp);
		vec2 f = fract(cellp);
		float near = 8.0;
		float second = 8.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 g = vec2(float(x), float(y));
				vec2 r = g + vec2(hash(i + g), hash(i + g + 19.1)) - f;
				float d = dot(r, r);
				if (d < near) { second = near; near = d; }
				else if (d < second) { second = d; }
			}
		}
		float fracture = 1.0 - smoothstep(0.0, 0.05, sqrt(second) - sqrt(near));
		value = mix(value, 0.97, fracture * 0.6 * step(0.5, detail));
	}
}

void shade(inout vec4 colour, vec2 uv) {
	float value = colour.r;
	float alpha = colour.a;
	int id = int(round(colour.g * 8.0));
	float param = colour.b;
	float cut = 2.0;

	pattern(id, uv, param, value, alpha);
	if (cut <= 1.0) alpha *= 1.0 - smoothstep(cut - 0.02, cut, clamp(uv.x, 0.0, 1.0));
	if (style == 1) {
		value = bands(clamp(value, 0.0, 1.0), 4.0);
		// Two flat bands; faint washes (stains, wide halos) drop out instead of turning flat.
#ifdef ADDITIVE
		// Light: wide soft halos would turn into flat discs, so only strong light survives.
		alpha = smoothstep(0.36, 0.4, alpha) * 0.35 + smoothstep(0.66, 0.7, alpha) * 0.65;
#else
		alpha = smoothstep(0.2, 0.24, alpha) * 0.4 + smoothstep(0.55, 0.59, alpha) * 0.6;
#endif
	} else if (style == 2) {
		value = floor(clamp(value, 0.0, 1.0) * 5.0 + 0.5) / 5.0;
	}
	vec3 rgb = mode == 1 ? tint.rgb * value : texture(ramp, vec2(clamp(value, 0.003, 0.997), 0.5)).rgb;
	colour = vec4(rgb, alpha * (mode == 1 ? tint.a : 1.0));
}
