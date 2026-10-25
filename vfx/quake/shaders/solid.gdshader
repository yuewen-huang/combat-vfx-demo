// Solid bodies of a ground impact (see vfx/quake/solid.gd): every body is raised, tilted,
// rolled and sunk here from the event clock, lit, and its faces turned away culled. Parts
// below the ground are cut away per pixel, so bodies grow out of the ground cleanly.
shader_type canvas_item;
#include "res://vfx/quake/shaders/quake.gdshaderinc"

uniform float perspective = 0.3;
uniform float span = 0.8;
// Light from the upper left, a little towards the viewer (ground frame: x right, y viewer, z up).
uniform vec3 light = vec3(-0.5, 0.35, 0.8);
uniform float lit = 0.55;

varying vec2 world;
varying float height;
varying float shading;
varying float shown;

float back_out(float x) {
	x = clamp(x, 0.0, 1.0) - 1.0;
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x;
}

vec3 turn(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void vertex() {
	vec3 p = CUSTOM0.xyz;
	float t = time - CUSTOM0.w;
	vec3 n = CUSTOM1.xyz;
	vec3 axis = vec3(cos(CUSTOM1.w), sin(CUSTOM1.w), 0.0);
	int kind = int(UV.x + 0.5);
	float size = UV.y;
	float alive = step(0.0, t) * step(t, span);
	vec3 view = normalize(vec3(0.0, 1.0, perspective));
	if (kind == 0) {
		// Spike: grows out of the ground with an overshoot, sinks back at the end.
		float grow = back_out(t / 0.09) * (1.0 - smoothstep(span * 0.62, span, t));
		p.z *= grow;
	} else if (kind == 1) {
		// Slab: tips up on its back edge, falls flat again, then sinks.
		float tilt = size * back_out(t / 0.12) * (1.0 - smoothstep(span * 0.45, span * 0.6, t));
		p = turn(p, axis, -tilt);
		n = turn(n, axis, -tilt);
		p.z -= smoothstep(span * 0.6, span * 0.8, t) * 90.0;
	} else if (kind == 2) {
		// Boulder: shoulders up out of the ground rolling forwards, then sinks.
		float roll = t * 2.6;
		p = turn(p, axis, roll);
		n = turn(n, axis, roll);
		p.z += mix(-size * 1.3, size * 0.15, back_out(t / 0.16)) - smoothstep(span * 0.6, span, t) * size * 1.6;
	} else if (kind == 4) {
		// Crystal: sprouts from its base, then bursts, every facet flying off along its normal.
		float grow = back_out(t / 0.07);
		float burst = smoothstep(span * 0.66, span * 0.78, t);
		p *= grow;
		p += n * burst * size * 0.45;
		p.z -= burst * burst * size * 0.35;
		alive *= 1.0 - smoothstep(span * 0.7, span * 0.82, t);
	} else {
		// Surge: the ground swells as the front passes under it (steep front, long back).
		float rise = t < 0.0 ? exp(-pow(t / 0.035, 2.0)) : exp(-pow(t / 0.13, 2.0));
		float slope = t < 0.0 ? -2.0 * t / (0.035 * 0.035) : -2.0 * t / (0.13 * 0.13);
		p.z = size * rise;
		vec2 dz = -size * rise * slope * CUSTOM1.xy;
		n = normalize(vec3(-dz.x, -dz.y, 1.0));
		alive = smoothstep(0.6, 4.0, p.z);
	}
	shading = COLOR.r + lit * max(dot(n, normalize(light)), 0.0) + 0.06 * max(n.z, 0.0);
	float facing = clamp(dot(n, view), 0.0, 1.0);
	if (kind == 4) {
		// Ice: brighter towards its silhouette, a hard glint where the light reflects at you.
		float glint = pow(max(dot(reflect(-normalize(light), n), view), 0.0), 14.0);
		shading = COLOR.r + 0.45 * max(dot(n, normalize(light)), 0.0) + 0.35 * (1.0 - facing) + 0.55 * glint;
		alive *= 0.72 + 0.28 * (1.0 - facing);
	}
	shown = alive * (kind == 3 ? 1.0 : step(0.0001, dot(n, view)));
	height = p.z;
	VERTEX += vec2(p.x, p.y * perspective - p.z);
	world = VERTEX;
}

void fragment() {
	if (shown < 0.01 || height < -0.5) discard;
	vec4 c = vec4(shading, COLOR.g, COLOR.b, COLOR.a * shown);
	shade(c, world);
	COLOR = c;
}
