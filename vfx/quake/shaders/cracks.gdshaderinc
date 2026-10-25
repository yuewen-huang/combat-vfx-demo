// Crack strips (see vfx/quake/gpu_layers.gd Strips): each point opens when the front
// reaches it; layer_pass 0 is the dark gap, 1 the glowing core (heats then cools), 2 the thin lip
// that catches the light just above the gap.
#include "res://vfx/quake/shaders/quake.gdshaderinc"

uniform float perspective = 0.3;
uniform float life = 2.0;
uniform int layer_pass = 0;
uniform float width_scale = 1.0;
uniform float value = 0.06;
uniform float gain = 1.0;
// Heat: share that never cools, how long the body stands, how long the crack lingers after.
uniform float keep = 0.0;
uniform float hold = 0.8;
uniform float linger = 0.6;

varying vec2 world;
varying float strength;

void vertex() {
	float t = time - CUSTOM0.w;
	float open = t < 0.0 ? 0.0 : 1.0 - exp(-t * 30.0);
	float w = CUSTOM0.z * open;
	if (layer_pass == 2) VERTEX += vec2(0.0, -(w * 0.55 + 0.6)) + CUSTOM0.xy * CUSTOM1.x * 0.5 * step(0.0, t);
	else VERTEX += CUSTOM0.xy * CUSTOM1.x * w * width_scale * 0.5;
	float heat = (exp(-t * 3.0) * (1.0 - keep) + keep) * (1.0 - smoothstep(hold, hold + linger, t));
	float ending = 1.0 - smoothstep(life - 0.5, life, time);
	strength = (layer_pass == 1 ? gain * heat : gain) * ending * step(0.0, t);
	world = VERTEX;
}

void fragment() {
	vec4 c = vec4(value, 0.0, 0.0, strength);
	shade(c, world);
	COLOR = c;
}
