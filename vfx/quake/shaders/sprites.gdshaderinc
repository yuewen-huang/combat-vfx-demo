// Particles that only need the clock (see vfx/quake/gpu_layers.gd Sprites): dust billows and
// skirts, rising motes and embers, ballistic sparks and embers, ground stains.
#include "res://vfx/quake/shaders/quake.gdshaderinc"

uniform float perspective = 0.3;
uniform float life = 2.0;
uniform float gravity = 1800.0;
uniform float dust_height = 90.0;
uniform float dust_spread = 80.0;
// Texture tiles across (the dust atlas has three billow variants).
uniform float tiles = 1.0;

varying vec2 world;
varying float fade;
varying vec2 shape_uv;

vec2 thrown(vec2 start, vec2 drift, float up, float t) {
	float air = clamp(t, 0.0, 2.0 * up / gravity);
	return start + drift * air - vec2(0.0, max(up * air - 0.5 * gravity * air * air, 0.0));
}

void vertex() {
	float t = time - CUSTOM0.x;
	float span = CUSTOM0.y;
	float size = CUSTOM0.z;
	int kind = int(floor(CUSTOM0.w + 0.001));
	float heading = fract(CUSTOM0.w + 0.0001) * 6.2831 / 0.99;
	vec2 corner = UV - 0.5;
	vec2 center = VERTEX;
	vec2 scale = vec2(0.0);
	float spin = 0.0;
	float a = 0.0;
	float variant = 0.0;
	if (kind <= 1) {
		variant = floor(fract(CUSTOM1.w * 0.618) * tiles);
		if (t > 0.0 && t < span) {
			float s = size * (0.35 + 0.95 * (1.0 - exp(-t * 4.5)));
			bool skirt = kind == 1;
			center += CUSTOM1.xy * dust_spread * (1.0 - exp(-t * 3.2)) * (skirt ? 1.3 : 0.6);
			center.y -= dust_height * CUSTOM1.z * (1.0 - exp(-t * 2.0)) + s * (skirt ? 0.12 : 0.35);
			a = smoothstep(0.0, 0.06, t) * pow(1.0 - t / span, 1.4);
			scale = skirt ? vec2(s * 2.2, s * 0.6) : vec2(s, s * 0.85);
			spin = (fract(CUSTOM1.w * 0.37) - 0.5) * 0.6 + t * 0.3 * sign(CUSTOM1.x);
		}
	} else if (kind <= 3) {
		if (t > 0.0 && t < span) {
			center += CUSTOM1.xy * t + vec2(sin(CUSTOM1.w + t * 6.0) * COLOR.b * 40.0, -CUSTOM1.z * t);
			a = sin(3.14159 * t / span);
			scale = vec2(size);
		}
	} else if (kind <= 5) {
		if (t > 0.0 && t < span) {
			vec2 p = thrown(center, CUSTOM1.xy, CUSTOM1.z, t);
			a = 1.0 - smoothstep(span * 0.45, span, t);
			if (kind == 4) {
				vec2 q = thrown(center, CUSTOM1.xy, CUSTOM1.z, max(t - CUSTOM1.w, 0.0));
				vec2 d = p - q;
				float len = length(d);
				center = (p + q) * 0.5;
				scale = vec2(len + size, size * 0.6);
				spin = len > 0.001 ? atan(d.y, d.x) : 0.0;
			} else {
				center = p;
				scale = vec2(size);
			}
		}
	} else {
		a = step(0.0, t);
		scale = vec2(size, size * CUSTOM1.x) * clamp(t * 10.0, 0.0, 1.0);
	}
	fade = a * (1.0 - smoothstep(life - 0.5, life, time));
	shape_uv = corner;
	vec2 off = corner * scale;
	float c = cos(spin);
	float s = sin(spin);
	VERTEX = center + vec2(off.x * c - off.y * s, off.x * s + off.y * c);
	UV = (UV + vec2(variant, 0.0)) / vec2(tiles, 1.0);
	world = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	c.a *= fade;

	shade(c, world);
	COLOR = c;
}
