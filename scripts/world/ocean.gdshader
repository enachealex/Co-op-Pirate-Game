shader_type canvas_item;
// World-space animated ocean. Drawn once into the shared World2D canvas and
// rendered by both split-screen cameras. screen_space = true is used by the menus.
uniform vec2 world_size = vec2(7200.0, 7200.0);
uniform vec4 deep : source_color = vec4(0.06, 0.24, 0.40, 1.0);
uniform vec4 shallow : source_color = vec4(0.10, 0.36, 0.54, 1.0);
uniform vec4 storm : source_color = vec4(0.10, 0.13, 0.17, 1.0);
uniform float edge_band = 420.0;
uniform bool screen_space = false;
varying vec2 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.6 + vnoise(p * 2.03 + 17.0) * 0.28 + vnoise(p * 4.1 + 41.0) * 0.12; }
void fragment() {
	vec2 p = screen_space ? FRAGCOORD.xy : wpos;
	float t = TIME;
	float big = fbm(p * 0.0007 + vec2(t * 0.004, 0.0));
	vec3 col = mix(deep.rgb, shallow.rgb, smoothstep(0.25, 0.85, big));
	vec2 wind = normalize(vec2(1.0, 0.35));
	vec2 side = vec2(-wind.y, wind.x);
	float warp = fbm(p * 0.0035 + vec2(0.0, t * 0.04)) * 7.0;
	float along = dot(p, wind);
	float band = sin(along * 0.03 + warp + t * 1.1);
	float band2 = sin(dot(p, side) * 0.011 - along * 0.018 + warp * 0.6 - t * 0.7);
	col += vec3(0.018, 0.03, 0.04) * (band * 0.7 + band2 * 0.5);
	// Crest lines: thin bright ridges on the swell
	float crest = smoothstep(0.93, 0.995, band) * smoothstep(0.35, 0.75, vnoise(p * 0.012 + vec2(t * 0.15, 0.0)));
	col = mix(col, vec3(0.62, 0.8, 0.9), crest * 0.18);
	// Sun glints: sparse, tiny, twinkling
	vec2 gp = p * 0.11 + vec2(t * 0.7, t * 0.35);
	float g = vnoise(gp) * vnoise(gp * 1.7 + vec2(3.1, 7.7) - t * 0.5);
	float glint = smoothstep(0.66, 0.84, g);
	col = mix(col, vec3(0.9, 0.97, 1.0), glint * 0.24);
	if (!screen_space) {
		vec2 outside = max(-p, p - world_size);
		float o = max(outside.x, outside.y);
		float s = smoothstep(-edge_band, edge_band * 0.5, o);
		float fog = fbm(p * 0.004 + vec2(t * 0.05, t * 0.03));
		col = mix(col, storm.rgb + fog * 0.08, clamp(s * (0.75 + fog * 0.4), 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
