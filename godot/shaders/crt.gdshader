// In-world CRT screens ONLY (instructions.md: one optional CRT shader,
// used on in-world screens). Green phosphor, scanlines, a slow roll bar,
// fake readout text blocks. Unshaded and cheap.
shader_type spatial;
render_mode unshaded;

uniform vec4 phosphor : source_color = vec4(0.5, 0.81, 0.54, 1.0);
uniform float brightness = 1.4;
uniform float seed = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	float bulge = 1.0 - dot(c, c) * 1.6;
	// Kit boxes have no UVs: lay the text out in world space instead.
	if (UV == vec2(0.0)) {
		uv = fract(vec2(wpos.x + wpos.z, -wpos.y) * 1.3);
		bulge = 1.0;
	}
	// Text-like rows of blocks that scroll every few seconds.
	float row = floor(uv.y * 14.0);
	float col = floor(uv.x * 28.0);
	float page = floor(TIME * 0.35 + seed);
	float on = step(0.45, hash(vec2(col, row + page * 17.0))) * step(hash(vec2(row, page)) * 26.0, col);
	on *= step(0.15, fract(uv.y * 14.0)) * step(0.1, fract(uv.x * 28.0));
	float cursor = step(0.5, fract(TIME * 1.5)) * step(abs(row - 12.0), 0.1) * step(col, 1.5);
	float scan = 0.75 + 0.25 * sin(uv.y * 400.0);
	float roll = 0.9 + 0.1 * smoothstep(0.0, 0.05, abs(fract(uv.y - TIME * 0.12) - 0.5));
	float glow = 0.12 + (on + cursor) * 0.85;
	vec3 colr = phosphor.rgb * glow * scan * roll * bulge * brightness;
	ALBEDO = colr;
}
