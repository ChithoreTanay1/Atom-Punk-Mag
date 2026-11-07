// Full-screen post: palette grade, vignette, grain, damage tint, then the
// PS1/PSX colour reduction with ordered dithering.
//
// PSX stage adapted from "PS1/PSX PostProcessing" by Grau
// https://godotshaders.com/shader/ps1-psx-postprocessing/  (CC0)
// Changes: reads the screen through hint_screen_texture (the original
// sampled TEXTURE, which renders grey on a ColorRect), optional low-res
// pixelation, MAXCOLORS raised to 32, merged into this single pass.
shader_type canvas_item;
render_mode unshaded;

#define MAXCOLORS 32

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float vignette = 0.32;
uniform float grain = 0.03;
uniform float saturation = 0.86;
uniform vec3 shadow_tint = vec3(0.14, 0.2, 0.21);
uniform float shadow_tint_amount = 0.08;
uniform float damage = 0.0;

// PSX
uniform bool psx_enabled = true;
uniform bool dithering = true;
uniform int colors : hint_range(1, 32) = 16;
uniform int dither_size : hint_range(1, 8) = 2;
// Vertical resolution to pixelate to; 0 keeps the native resolution.
uniform float pixel_lines = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float dithering_pattern(ivec2 fragcoord) {
	const float pattern[] = {
		0.00, 0.50, 0.10, 0.65,
		0.75, 0.25, 0.90, 0.35,
		0.20, 0.70, 0.05, 0.50,
		0.95, 0.40, 0.80, 0.30
	};
	int x = fragcoord.x % 4;
	int y = fragcoord.y % 4;
	return pattern[y * 4 + x];
}

float reduce_color(float raw, float dither, int depth) {
	float div = 1.0 / float(depth);
	float val = 0.0;
	int i = 0;
	while (i <= MAXCOLORS) {
		if (raw > div * (float(i + 1))) {
			i = i + 1;
			continue;
		}
		if (raw * float(depth) - float(i) <= dither * 0.999) {
			val = div * float(i);
		} else {
			val = div * float(i + 1);
		}
		return val;
	}
	return val;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 frag = FRAGCOORD.xy;
	if (psx_enabled && pixel_lines > 0.0) {
		vec2 res = vec2(pixel_lines * (1.0 / SCREEN_PIXEL_SIZE.x) * SCREEN_PIXEL_SIZE.y, pixel_lines);
		uv = (floor(uv * res) + 0.5) / res;
		frag = floor(uv * res);
	}
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = mix(c, c + shadow_tint * shadow_tint_amount, 1.0 - smoothstep(0.0, 0.5, l));
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * vignette * 2.2;
	c = mix(c, vec3(0.42, 0.13, 0.12), damage * smoothstep(0.15, 0.7, length(d)) * 0.7);
	c += (hash(uv * vec2(1931.0, 1097.0) + fract(TIME * 7.13)) - 0.5) * grain;
	if (psx_enabled) {
		ivec2 dc = ivec2(frag / (pixel_lines > 0.0 ? 1.0 : float(dither_size)));
		float dv = dithering ? dithering_pattern(dc) : 1.0;
		float th = (dv - 0.5) * dv + 0.5;
		c = clamp(c, 0.0, 1.0);
		c.r = reduce_color(c.r, th, colors - 1);
		c.g = reduce_color(c.g, th, colors - 1);
		c.b = reduce_color(c.b, th, colors - 1);
	}
	COLOR = vec4(c, 1.0);
}
