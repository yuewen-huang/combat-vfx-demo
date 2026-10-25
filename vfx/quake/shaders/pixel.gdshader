// 像素 style: the effect's layers rendered small, shown at pixel grain with the strength of
// each pixel in flat steps (glows become stepped rings). Hue and coverage ratio are kept.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform float levels = 6.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float strength = max(max(c.r, max(c.g, c.b)), c.a);
	if (strength < 1.2 / levels) discard;
	float stepped = floor(strength * levels + 0.5) / levels;
	COLOR = c * (stepped / strength);
}
