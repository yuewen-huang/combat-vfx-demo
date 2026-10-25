shader_type canvas_item;
// 冲击帧: over the whole frame. invert: a stark negative (luma thresholded, dark on white,
// tinted); otherwise a wash towards `tint`. `amount` 0..1 blends it in.
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform bool invert = true;
uniform vec4 tint : source_color = vec4(1.0, 0.94, 0.97, 1.0);
uniform float amount = 1.0;

void fragment() {
	vec3 base = texture(screen, SCREEN_UV).rgb;
	vec3 result;
	if (invert) {
		float luma = dot(base, vec3(0.299, 0.587, 0.114));
		result = vec3(1.0 - smoothstep(0.08, 0.45, luma)) * tint.rgb;
	} else {
		result = mix(base, tint.rgb, 0.85);
	}
	COLOR = vec4(mix(base, result, clamp(amount, 0.0, 1.0)), 1.0);
}
