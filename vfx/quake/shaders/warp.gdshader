// 炸裂 tier: bends what is behind the shockwave. Vertex colour r, g = screen offset
// direction (0.5 = none), a = strength.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float amount = 0.012;

void fragment() {
	vec2 push = (COLOR.rg - 0.5) * 2.0 * COLOR.a * amount;
	float shape = 1.0 - smoothstep(0.0, 1.0, abs(UV.y));
	COLOR = vec4(texture(screen, SCREEN_UV - push * shape).rgb, shape * COLOR.a);
}
