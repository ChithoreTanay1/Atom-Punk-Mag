// Shared world material. All surface detail is procedural in world space,
// so the whole kit needs no texture files and shares one shader.
// pattern: 0 plain, 1 concrete (formwork panels, streaks), 2 walnut,
// 3 marble, 4 geometric carpet, 5 brushed steel panels, 6 foliage,
// 7 road / paving (wet), 8 fabric, 9 lit windows (facade glass grid)
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.55, 0.56, 0.57, 1.0);
uniform vec4 accent : source_color = vec4(0.4, 0.22, 0.27, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform int pattern = 0;
uniform float scale = 1.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// 0 dry .. 1 soaked: darkens and adds puddle gloss (exteriors).
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 planar(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y > a.x && a.y > a.z) {
		return p.xz;
	}
	if (a.x > a.z) {
		return vec2(p.z, p.y);
	}
	return p.xy;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = planar(wpos, wnrm) * scale;
	vec3 col = albedo.rgb;
	float rough = roughness;
	float metal = metallic;
	vec3 emis = emission_color.rgb * emission_energy;
	bool up_facing = wnrm.y > 0.6;

	if (pattern == 1) {
		float n = vnoise(uv * 2.3) * 0.55 + vnoise(uv * 9.0) * 0.3 + vnoise(uv * 31.0) * 0.15;
		vec2 g = abs(fract(uv / vec2(2.4, 1.2)) - 0.5);
		float seam = smoothstep(0.484, 0.5, max(g.x, g.y));
		float tie = step(length(fract(uv / vec2(0.6, 0.6)) - 0.5), 0.035) * (1.0 - float(up_facing));
		float streak = 0.0;
		if (!up_facing) {
			streak = vnoise(vec2(uv.x * 5.0, wpos.y * 0.15)) * smoothstep(3.0, 0.0, fract(wpos.y / 4.5) * 4.5) * 0.25;
		}
		col *= 0.84 + n * 0.3;
		col *= 1.0 - seam * 0.28 - tie * 0.25 - streak;
		rough = clamp(rough + (n - 0.5) * 0.2, 0.0, 1.0);
	} else if (pattern == 2) {
		float grain = vnoise(vec2(uv.x * 2.0, uv.y * 38.0)) * 0.6 + vnoise(vec2(uv.x * 9.0, uv.y * 120.0)) * 0.4;
		float rings = sin((uv.y + vnoise(uv * 1.5) * 1.2) * 26.0) * 0.5 + 0.5;
		col *= 0.78 + grain * 0.3 + rings * 0.12;
		rough = 0.45 + grain * 0.15;
	} else if (pattern == 3) {
		float v = vnoise(uv * 1.6 + vnoise(uv * 4.0) * 2.0);
		float vein = smoothstep(0.03, 0.0, abs(v - 0.5));
		vec2 g = abs(fract(uv / 1.2) - 0.5);
		float seam = smoothstep(0.492, 0.5, max(g.x, g.y));
		col = mix(col, accent.rgb, vein * 0.55);
		col *= 1.0 - seam * 0.3;
		rough = 0.18 + vein * 0.2;
	} else if (pattern == 4) {
		vec2 c = fract(uv / 1.6) - 0.5;
		float diamond = step(abs(c.x) + abs(c.y), 0.32) - step(abs(c.x) + abs(c.y), 0.22);
		float border = step(0.46, max(abs(c.x), abs(c.y)));
		col = mix(col, accent.rgb, clamp(diamond + border, 0.0, 1.0));
		col *= 0.92 + vnoise(uv * 60.0) * 0.1;
		rough = 0.95;
	} else if (pattern == 5) {
		float brush = vnoise(vec2(uv.x * 200.0, uv.y * 3.0));
		vec2 g = abs(fract(uv / vec2(1.5, 0.75)) - 0.5);
		float seam = smoothstep(0.485, 0.5, max(g.x, g.y));
		col *= 0.9 + brush * 0.12;
		col *= 1.0 - seam * 0.4;
		rough = 0.35 + brush * 0.15;
	} else if (pattern == 6) {
		float n = vnoise(uv * 6.0) * 0.6 + vnoise(uv * 23.0) * 0.4;
		col = mix(col * 0.7, accent.rgb, n);
		rough = 0.8;
	} else if (pattern == 7) {
		float n = vnoise(uv * 0.9) * 0.5 + vnoise(uv * 7.0) * 0.3 + vnoise(uv * 40.0) * 0.2;
		vec2 g = abs(fract(uv / vec2(4.0, 4.0)) - 0.5);
		float seam = smoothstep(0.49, 0.5, max(g.x, g.y));
		col *= 0.85 + n * 0.28;
		col *= 1.0 - seam * 0.3;
		rough = 0.8;
	} else if (pattern == 8) {
		float weave = (sin(uv.x * 220.0) * sin(uv.y * 220.0)) * 0.5 + 0.5;
		col *= 0.88 + weave * 0.1 + vnoise(uv * 4.0) * 0.08;
		rough = 0.95;
	} else if (pattern == 9) {
		// Facade glazing grid; some panes lit warm, the rest smoked.
		vec2 cell = floor(uv / vec2(1.8, 2.25));
		vec2 f = fract(uv / vec2(1.8, 2.25));
		float frame = step(0.88, max(abs(f.x - 0.5), abs(f.y - 0.5)) * 2.0);
		float lit = step(0.72, hash(cell + floor(wpos.xz * 0.01)));
		col = mix(col, vec3(0.08, 0.1, 0.11), frame);
		emis = mix(emis * lit, vec3(0.0), frame);
		rough = 0.15;
		metal = 0.2;
	}

	// Wet exteriors: darken, gloss in puddles on upward faces.
	if (wetness > 0.0) {
		float puddle = up_facing ? smoothstep(0.55, 0.7, vnoise(wpos.xz * 0.35)) : 0.0;
		col *= 1.0 - wetness * (0.18 + puddle * 0.3);
		rough = mix(rough, 0.08, wetness * puddle);
		rough = mix(rough, rough * 0.7, wetness);
	}

	float ao = COLOR.r;
	ALBEDO = col * ao;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
}
