// Additive (light) ground-impact layer (see quake.gdshaderinc).
shader_type canvas_item;
render_mode blend_add;
#define ADDITIVE
#include "res://vfx/quake/shaders/quake.gdshaderinc"

void fragment() {
	vec4 c = COLOR;
	shade(c, UV);
	COLOR = c;
}
