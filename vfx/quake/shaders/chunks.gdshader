// Flying chunks of a ground impact (see vfx/quake/chunks.gd): thrown on a ballistic arc,
// tumbling, resting where they land and fading, all from the event clock.
shader_type canvas_item;
#include "res://vfx/quake/shaders/quake.gdshaderinc"

uniform float perspective = 0.3;
uniform float gravity = 1800.0;
uniform vec3 light = vec3(-0.5, 0.35, 0.8);
// Look of each kind: value bias and pattern (stone 6, ice 7).
uniform float stone_value = 0.15;
uniform float ice_value = 0.35;

varying vec2 world;
varying float shading;
varying float shown;
varying float pattern_id;
varying float heat;

vec3 turn(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void vertex() {
	float t = time - CUSTOM0.w;
	float rise = CUSTOM1.z;
	float flight = 2.0 * rise / gravity;
	float air = clamp(t, 0.0, flight);
	vec3 axis = normalize(vec3(sin(CUSTOM0.w * 37.0), cos(CUSTOM0.w * 53.0), 0.6));
	float spin = CUSTOM1.w * air;
	vec3 p = turn(CUSTOM0.xyz, axis, spin);
	vec3 n = turn(COLOR.rgb * 2.0 - 1.0, axis, spin);
	vec2 drift = CUSTOM1.xy * air;
	float z = max(rise * air - 0.5 * gravity * air * air, 0.0);
	float ice = step(0.75, COLOR.a);
	vec3 view = normalize(vec3(0.0, 1.0, perspective));
	float alive = step(0.0, t) * (1.0 - smoothstep(flight + 0.1, flight + 0.45, t));
	shown = alive * step(0.0001, dot(n, view));
	float facing = clamp(dot(n, view), 0.0, 1.0);
	float diffuse = max(dot(n, normalize(light)), 0.0);
	shading = ice > 0.5 ? ice_value + 0.4 * diffuse + 0.3 * (1.0 - facing) : stone_value + 0.55 * diffuse;
	pattern_id = ice > 0.5 ? 7.0 : 6.0;
	heat = 0.0;

	VERTEX += drift * vec2(1.0, perspective) + vec2(p.x, p.y * perspective - p.z - z);
	world = VERTEX;
}

void fragment() {
	if (shown < 0.01) discard;
	vec4 c = vec4(shading, pattern_id / 8.0, heat, shown);
	shade(c, world);
	COLOR = c;
}
