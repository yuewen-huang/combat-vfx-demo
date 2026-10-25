shader_type canvas_item;
render_mode blend_premul_alpha;
// GPU instances interpolate between two independent formations.
uniform int form_a = 0;
uniform vec3 at_a = vec3(640.0, 400.0, 0.0);
uniform vec3 size_a = vec3(200.0, 120.0, 200.0);
uniform vec2 path_a[12];
uniform int path_n_a = 2;
uniform float head_a = 1.0;
uniform float since_a = 0.0;
uniform int form_b = -1;
uniform vec3 at_b = vec3(640.0, 400.0, 0.0);
uniform vec3 size_b = vec3(200.0, 120.0, 200.0);
uniform vec2 path_b[12];
uniform int path_n_b = 2;
uniform float head_b = 1.0;
uniform float since_b = 0.0;
uniform float blend = 0.0;
uniform float blend_rate = 0.0;
uniform float blend_spread = 0.6;
uniform float blend_arc = 90.0;

uniform float time = 0.0;
// 画风: 0 写实, 1 赛璐璐, 2 像素 (pixel grain in `grain`).
uniform int style = 0;
uniform float grain = 3.0;
uniform float count_fraction = 1.0;
uniform float size_scale = 1.0;
uniform float swirl = 2.0;
uniform float turbulence = 20.0;
uniform float tumble = 0.35;
uniform float stream_length = 0.3;
uniform float stream_width = 34.0;
uniform float opacity = 1.0;


uniform vec3 col_deep : source_color = vec3(0.15, 0.12, 0.08);
uniform vec3 col_body : source_color = vec3(0.6, 0.4, 0.2);
uniform vec3 col_light : source_color = vec3(0.95, 0.8, 0.55);
uniform vec3 col_glint : source_color = vec3(1.0);
uniform float glow = 0.0;

const vec3 KEY = vec3(-0.45, -0.7, -0.55);
const vec3 BACK = vec3(0.2, -0.3, 0.93);
const float FOCAL = 1400.0;

varying vec2 p_uv;
varying vec3 v_n;
varying vec3 v_a;
varying vec3 v_b;
varying float v_alpha;
varying float v_tone;

vec3 rotate_axis(vec3 v, vec3 k, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

vec3 hash3(float n) {
	return fract(sin(vec3(n * 12.9898, n * 78.233, n * 37.719)) * 43758.5453);
}

vec3 swirl_noise(vec3 p, float t) {
	return vec3(
		sin(p.y * 0.011 + t * 1.3) + sin(p.z * 0.017 - t * 0.7),
		sin(p.z * 0.013 + t * 1.1) + sin(p.x * 0.009 + t * 0.9),
		sin(p.x * 0.012 - t * 1.2) + sin(p.y * 0.015 + t * 0.6)) * 0.5;
}

#include "res://vfx/swarm/piece_materials.gdshaderinc"

vec2 path_point(bool b, int i) {
	return b ? path_b[i] : path_a[i];
}

vec3 spline(bool b, int n, float s) {
	float seg = clamp(s, 0.0, 0.9999) * float(n - 1);
	int i = int(floor(seg));
	float f = seg - float(i);
	vec2 p0 = path_point(b, max(i - 1, 0));
	vec2 p1 = path_point(b, i);
	vec2 p2 = path_point(b, min(i + 1, n - 1));
	vec2 p3 = path_point(b, min(i + 2, n - 1));
	float f2 = f * f;
	float f3 = f2 * f;
	vec2 p = 0.5 * (2.0 * p1 + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f3);
	return vec3(p, 0.0);
}

// Where a piece sits in a form at time t (`since` is seconds since the form began).
void place(bool b, int f, vec3 at, vec3 ext, int n, float head, float since, vec4 c, vec3 r, float t, out vec3 pos, out vec3 heading, out float alive) {
	alive = 1.0;
	heading = normalize(r - 0.5 + vec3(0.001));
	pos = at;
	if (f == 0) {
		// A soft ellipsoid, denser at the core.
		float z = c.x * 2.0 - 1.0;
		float a = c.y * 6.2832;
		vec3 dir = vec3(sqrt(1.0 - z * z) * cos(a), z, sqrt(1.0 - z * z) * sin(a));
		pos = at + dir * ext * pow(c.z, 0.7);
		pos += swirl_noise(pos, t + c.w * 9.0) * turbulence;
		heading = normalize(vec3(1.0, 0.3, 0.2) + (r - 0.5) * 1.6);
	} else if (f == 1) {
		float u = pow(c.x, 1.5);
		float s = head - u * stream_length;
		alive = smoothstep(-0.03, 0.02, s) * (1.0 - smoothstep(0.75, 1.0, c.x));
		vec3 centre = spline(b, n, s);
		vec3 tangent = normalize(spline(b, n, s + 0.01) - spline(b, n, s - 0.01) + vec3(0.0001, 0.0, 0.0));
		vec3 side = normalize(cross(tangent, vec3(0.0, 0.0, 1.0)));
		vec3 depth = vec3(0.0, 0.0, 1.0);
		float radius = stream_width * (0.3 + 0.7 * smoothstep(0.0, 0.1, u)) * (1.0 + u * 1.4) * pow(c.y, 0.7);
		float theta = c.z * 6.2832 + t * swirl * (1.0 - 0.4 * u) + s * 9.0;
		vec3 ring = side * cos(theta) + depth * sin(theta);
		pos = centre + ring * radius;
		pos += swirl_noise(pos + r * 300.0, t) * turbulence * (0.25 + u * 1.5);
		heading = normalize(tangent * 2.0 + cross(tangent, ring) * swirl * 0.25);
	} else if (f == 2) {
		// A hollow funnel standing on `at`, wide at the top, with three spiral arms.
		float lift = c.y;
		float h = -lift * ext.y;
		float radius = ext.x * (0.12 + 0.88 * pow(lift, 1.8)) * (0.82 + 0.18 * c.z);
		float angle = c.x * 6.2832 + t * swirl * ext.x / radius;
		float arm = 0.5 + 0.5 * sin(angle * 3.0 + lift * 9.0 - t * 4.0);
		alive = smoothstep(0.25, 0.75, arm + (r.x - 0.5) * 0.5);
		pos = at + vec3(cos(angle) * radius, h, sin(angle) * radius * ext.z / ext.x);
		pos += swirl_noise(pos, t) * turbulence * 0.4;
		heading = normalize(vec3(-sin(angle), -0.35, cos(angle)));
	} else if (f == 3) {
		float z = c.x * 2.0 - 1.0;
		float a = c.y * 6.2832;
		vec3 dir = vec3(sqrt(1.0 - z * z) * cos(a), z, sqrt(1.0 - z * z) * sin(a));
		float shell = floor(c.w * 3.0);
		vec3 axis = normalize(vec3(0.3, 1.0, 0.2) + (hash3(shell + 7.0) - 0.5));
		dir = rotate_axis(dir, axis, t * swirl * (shell - 0.5));
		float band = 0.5 + 0.5 * sin(asin(clamp(dir.y, -1.0, 1.0)) * 9.0 + shell * 2.1);
		alive = smoothstep(0.62, 0.9, band + (r.x - 0.5) * 0.15);
		pos = at + dir * ext.x * (0.86 + 0.14 * c.z + shell * 0.1);
		heading = normalize(cross(axis, dir) * sign(shell - 0.5) + vec3(0.0001));
	} else if (f == 4) {
		float z = c.x * 2.0 - 1.0;
		float a = c.y * 6.2832;
		vec3 dir = vec3(sqrt(1.0 - z * z) * cos(a), z * 0.7, sqrt(1.0 - z * z) * sin(a) * 0.6);
		float reach = ext.x * (0.15 + 0.85 * pow(c.z, 0.7)) * (1.0 - exp(-since * 3.2));
		pos = at + dir * reach + vec3(0.0, 40.0 * since * since, 0.0);
		pos += swirl_noise(pos, t) * turbulence * since;
		heading = dir;
	} else if (f == 5) {
		float fall_speed = 0.025 + 0.03 * r.y;
		if (piece_material == 0) { fall_speed = 0.065 + 0.08 * r.y; }
		if (piece_material == 1) { fall_speed = 0.025 + 0.025 * r.y; }
		if (piece_material == 2) { fall_speed = (0.10 + 0.12 * r.y) * sand_settle; }
		float fall = fract(c.y + t * fall_speed);
		pos = at + vec3((c.x - 0.5) * 2.0 * ext.x, (fall - 0.5) * 2.0 * ext.y, (c.z - 0.5) * 2.0 * ext.z);
		pos.x += sin(t * (0.8 + r.x) + c.w * 6.0) * 30.0;
		pos += swirl_noise(pos, t) * turbulence * 0.5;
		alive = smoothstep(0.0, 0.12, fall) * (1.0 - smoothstep(0.85, 1.0, fall));
		heading = normalize(vec3(sin(t + c.w * 6.0), 0.6, cos(t * 0.7 + c.x * 6.0)));
	} else {
		alive = 0.0;
	}
}

void place_mixed(vec4 c, vec3 r, float t, float bl, float dt, out vec3 pos, out vec3 heading, out float alive) {
	place(false, form_a, at_a, size_a, path_n_a, head_a - dt * 0.0, since_a - dt, c, r, t, pos, heading, alive);
	if (form_b < 0) { return; }
	vec3 pos_b;
	vec3 heading_b;
	float alive_b;
	place(true, form_b, at_b, size_b, path_n_b, head_b, since_b - dt, c, r, t, pos_b, heading_b, alive_b);
	float k = smoothstep(0.0, 1.0, clamp(bl * (1.0 + blend_spread) - r.x * blend_spread, 0.0, 1.0));
	float arc = sin(k * 3.14159);
	pos = mix(pos, pos_b, k) + (swirl_noise(pos * 0.7 + r * 500.0, t) + vec3(0.0, -0.6, 0.0)) * blend_arc * arc;
	heading = normalize(mix(heading, heading_b, k) + (pos_b - pos) * arc * 0.004 + vec3(0.0001));
	alive = mix(alive, alive_b, k);
}

vec2 to_screen(vec3 p) {
	return vec2(640.0, 360.0) + (p.xy - vec2(640.0, 360.0)) * FOCAL / (FOCAL + p.z);
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	vec3 r = hash3(float(INSTANCE_ID) + 1.0);
	float hidden = step(count_fraction, r.z * 0.999);
	vec3 pos;
	vec3 heading;
	float alive;
	place_mixed(c, r, time, blend, 0.0, pos, heading, alive);
	bool dust = piece_material == 2 && r.x < sand_dust * 0.35;
	if (piece_material == 0) {
		pos += vec3(sin(time * (1.1 + r.x) + c.w * 10.0) * 30.0, cos(time * 1.6 + c.w * 9.0) * 8.0, sin(time + c.x * 9.0) * 14.0) * leaf_sway;
	} else if (piece_material == 1) {
		pos += vec3(sin(time * (0.6 + r.x * 0.4) + c.w * 8.0) * 42.0, sin(time * 1.0 + c.w * 9.0) * 7.0, 0.0) * feather_bend;
	} else if (piece_material == 2) {
		float mass = dust ? 0.12 : (0.3 + c.w * 0.7) * sand_grain;
		float settling = (1.0 - exp(-max(time, 0.0) * 0.7)) * (dust ? 14.0 : 88.0) * mass * sand_settle;
		pos.y += settling;
		if (dust) { pos.x += sin(time * 0.7 + c.w * 10.0) * 25.0; }
		else { pos.y = min(pos.y, 519.0 - abs(sin(time * (4.0 + r.y * 7.0) + c.w * 9.0)) * 8.0 / max(mass, 0.3)); }
	}

	// Point first along the heading, rolling about it; `tumble` tilts it off course.
	vec3 tumble_axis = normalize(hash3(float(INSTANCE_ID) * 1.7 + 3.0) - 0.5);
	vec3 a = normalize(mix(heading, rotate_axis(heading, tumble_axis, time * (2.0 + 5.0 * r.y) + r.x * 6.0), tumble));
	vec3 n0 = normalize(cross(a, abs(a.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 n = rotate_axis(n0, a, time * (3.0 + 7.0 * r.x) + c.w * 6.2832);
	vec3 b = cross(n, a);
	if (piece_material == 0) {
		a = normalize(vec3(cos(time * (1.4 + r.x) + c.w * 6.0), 0.5 + sin(time * 2.0 + c.x * 6.0) * 0.5, sin(time + c.z * 6.0) * 0.35));
		n = rotate_axis(vec3(0.0, 0.0, -1.0), a, sin(time * (2.0 + r.y) + c.w * 7.0) * (0.5 + leaf_curl));
		b = normalize(cross(n, a));
	} else if (piece_material == 1) {
		a = normalize(vec3(1.0, sin(time * (0.7 + r.x * 0.5) + c.w * 6.0) * 0.7, 0.1));
		n = rotate_axis(vec3(0.0, 0.0, -1.0), a, sin(time * 0.9 + c.w * 8.0) * 0.6);
		b = normalize(cross(n, a));
	} else if (piece_material == 2) {
		a = normalize(vec3(1.0, sin(c.w * 16.0 + time) * 0.2, 0.0));
		n = vec3(0.0, 0.0, -1.0);
		b = normalize(cross(n, a));
	}

	float len = 1.0;
	float wid = 1.0;
	if (piece_material == 0) { len = 26.0 * (0.65 + c.w * 0.7) * size_scale; wid = len * 0.64; }
	if (piece_material == 1) { len = 37.0 * (0.6 + c.w * 0.8) * size_scale; wid = len * 0.38; }
	if (piece_material == 2) { len = (dust ? 45.0 + c.w * 50.0 : (1.2 + c.w * c.w * 4.0) * sand_grain) * size_scale; wid = len * (dust ? 0.7 : 0.85); }
	vec2 q = UV - vec2(0.5);
	vec2 centre = to_screen(pos);
	vec3 local = a * q.x * len + b * q.y * wid;
	if (piece_material == 0) {
		local += n * (q.y * q.y * len * leaf_curl * 0.65 + sin(q.x * 3.14159) * len * leaf_curl * 0.08);
	} else if (piece_material == 1) {
		float flex = pow(q.x + 0.5, 2.0) * feather_bend;
		local += b * sin(time * (1.4 + r.x) + q.x * 3.0 + c.w * 9.0) * flex * len * 0.20;
		local += n * flex * len * 0.24;
	}
	vec2 screen = to_screen(pos + local);
	float scale = FOCAL / (FOCAL + pos.z);


	if (style == 2) { screen = floor(screen / grain + 0.5) * grain; }
	VERTEX = screen;
	p_uv = UV;
	v_n = n;
	v_a = a;
	v_b = b;
	float far = smoothstep(-200.0, 400.0, pos.z);
	v_alpha = alive * (1.0 - hidden) * opacity * mix(1.0, 0.7, far);
	v_tone = r.y * (1.0 - 0.35 * far);
	v_seed = r;
	v_dust = dust ? 1.0 : 0.0;
}


void fragment() {
	COLOR = piece_surface(p_uv, v_n, v_a, v_b, v_alpha, v_tone, v_seed, v_dust);
}
