// A crazed windshield. The first hit spiders the whole pane: every shard bends
// what is behind it a different way and the laminate goes milky, so the road is
// hard to read. The next hit removes the glass (windshield.gd hides this mesh).
// `q` is the position on the pane in metres, so shards are not stretched.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 impact = vec2(0.0, 0.45);
uniform float seed = 1.0;

varying vec2 q;

float h1(float x) {
	return fract(sin(x * 91.17 + seed * 7.3) * 43758.5453);
}

void vertex() {
	q = vec2(VERTEX.x, VERTEX.y * 2.0);
}

void fragment() {
	vec2 d = q - impact;
	float r = max(length(d), 0.0005);
	float a = atan(d.y, d.x) / 6.28318 + 0.5;
	// Rings get wider going out, and each ring is cut into its own sectors.
	float rr = log(1.0 + r * 16.0) * 2.4;
	float ring = floor(rr);
	float n = 9.0 + ring * 4.0;
	float sa = a * n + h1(ring) * 3.0 + sin(r * 17.0 + seed) * 0.16;
	float sector = floor(sa);
	float id = ring * 37.0 + mod(sector, n);
	// Distance to the shard's edges, in metres.
	float e_s = min(fract(sa), 1.0 - fract(sa)) * 6.28318 * r / n;
	float rf = fract(rr + sin(a * 40.0 + ring) * 0.05 + (h1(mod(sector, n) + ring * 13.0) - 0.5) * 0.42);
	float e_r = min(rf, 1.0 - rf) / 2.4 * (1.0 + r * 16.0) / 16.0;
	float edge = min(e_s, e_r);
	float line = smoothstep(0.0017, 0.0004, edge) * (0.55 + 0.45 * h1(id + 2.0));
	float bevel = smoothstep(0.012, 0.0, edge);
	// Each shard refracts by its own offset: this is what spoils the view.
	vec2 off = vec2(h1(id) - 0.5, h1(id + 3.1) - 0.5) * 0.085;
	off += (d / r) * 0.012 * h1(id + 9.0);
	vec3 scene = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 tap = vec2(cos(fi * 1.57 + id), sin(fi * 1.57 + id)) * 0.006;
		scene += texture(screen_tex, clamp(SCREEN_UV + off + tap, 0.0, 1.0)).rgb;
	}
	scene *= 0.25;
	// Milky laminate, brighter near the strike; bright lines at every break.
	float milk = 0.24 + 0.34 * exp(-r * 3.2) + h1(id + 5.0) * 0.1;
	vec3 c = mix(scene * 0.82, vec3(0.62, 0.66, 0.66), milk);
	c += vec3(0.5) * bevel * 0.35;
	c = mix(c, vec3(0.86, 0.9, 0.9), line * 0.85);
	// The crushed spot where it was struck.
	c = mix(c, vec3(0.92), smoothstep(0.035, 0.012, r));
	ALBEDO = c;
}
