// Molten and frozen ground patches (see vfx/quake/gpu_layers.gd Patches): spread from their
// centres after the front passes. kind 0 灼地: char rim, then a pool that heats, melts and
// crusts over; kind 1 冰封: dark rim, then a glassy sheet that fades.
shader_type canvas_item;
#include "res://vfx/quake/shaders/quake.gdshaderinc"

uniform float perspective = 0.3;
uniform float life = 2.0;
uniform int kind = 0;
// 灼地: body + crack time; 冰封: body time.
uniform float hold = 2.0;

varying vec2 world;
varying float fade;
varying float heat;
varying float pool;

void vertex() {
	float t = time - CUSTOM0.z;
	float grow = t < 0.0 ? 0.0 : 1.0 - exp(-t * (kind == 0 ? 6.0 : 9.0));
	VERTEX += CUSTOM0.xy * grow;
	pool = CUSTOM0.w;
	heat = smoothstep(0.1, 0.55, t) * (1.0 - 0.9 * smoothstep(hold * 0.25, hold * 0.8, t));
	float ending = 1.0 - smoothstep(life - 0.5, life, time);
	fade = step(0.0, t) * ending * (kind == 1 ? (1.0 - smoothstep(hold * 0.7, hold, t)) * step(t, hold) : 1.0);
	world = VERTEX;
}

void fragment() {
	vec4 c;
	if (kind == 0) c = pool > 0.5 ? vec4(0.9, 5.0 / 8.0, heat, fade) : vec4(0.06, 0.0, 0.0, 0.9 * fade);
	else c = pool > 0.5 ? vec4(0.42, 7.0 / 8.0, 0.0, 0.75 * fade) : vec4(0.06, 0.0, 0.0, 0.55 * fade);
	shade(c, world);
	COLOR = c;
}
