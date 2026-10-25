// Normal-blended ground-impact layer (see quake.gdshaderinc).
shader_type canvas_item;
#include "res://vfx/quake/shaders/quake.gdshaderinc"

void fragment() {
	vec4 c = COLOR;
	shade(c, UV);
	COLOR = c;
}
