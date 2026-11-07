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
// How strongly this material reacts to weather (exteriors only):
// wetness scales the global weather_wet, exposed gates the snow layer.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float exposed : hint_range(0.0, 1.0) = 0.0;
// Weathering grime on vertical faces (base dirt, streaks under sills).
uniform float grime : hint_range(0.0, 1.0) = 0.0;

global uniform float weather_wet;
global uniform float weather_snow;
global uniform float weather_rain;

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

	// Grime: dirt creeping up from the ground, darker under ledges.
	if (grime > 0.0 && !up_facing) {
		float gn = vnoise(vec2(uv.x * 1.3, wpos.y * 0.7));
		float base_dirt = smoothstep(1.4, 0.0, wpos.y - floor(wpos.y / 60.0) * 60.0) * (0.6 + gn * 0.4);
		float drip = smoothstep(0.55, 0.85, vnoise(vec2(uv.x * 3.0, 0.0))) * smoothstep(0.0, 2.5, fract(wpos.y / 3.6) * 3.6) * (1.0 - fract(wpos.y / 3.6)) * 0.6;
		col *= 1.0 - grime * (base_dirt * 0.35 + drip * 0.25 + (1.0 - gn) * 0.08);
	}

	// Wet exteriors: darken, gloss in puddles, ripples while raining.
	float w = wetness * weather_wet;
	float puddle = 0.0;
	if (w > 0.0) {
		puddle = up_facing ? smoothstep(0.52, 0.68, vnoise(wpos.xz * 0.35) + vnoise(wpos.xz * 1.7) * 0.12) : 0.0;
		col *= 1.0 - w * (0.2 + puddle * 0.32);
		rough = mix(rough, 0.04, clamp(w * 1.4, 0.0, 1.0) * puddle);
		rough = mix(rough, rough * 0.55, w);
		metal = mix(metal, 0.25, w * puddle);
		if (!up_facing) {
			// Water sheeting down walls: streaky darker gloss.
			float sheet = smoothstep(0.4, 0.8, vnoise(vec2(wpos.x * 2.0 + wpos.z * 2.0, wpos.y * 0.3 - TIME * 0.4)));
			col *= 1.0 - w * sheet * 0.12;
			rough = mix(rough, 0.2, w * sheet * 0.6);
		}
		if (weather_rain > 0.0 && puddle > 0.05) {
			// Expanding ripple rings in a grid of jittered cells.
			vec2 rp = wpos.xz * 2.2;
			vec2 cell = floor(rp);
			vec2 off = vec2(0.0);
			for (int k = 0; k < 2; k++) {
				vec2 c = cell + vec2(float(k), 0.0) * 0.0;
				float h = hash(c + float(k) * 7.31);
				vec2 ctr = c + 0.5 + (vec2(hash(c + 3.1), hash(c + 5.7)) - 0.5) * 0.6;
				float ph = fract(TIME * (0.8 + h * 0.6) + h * 9.0 + float(k) * 0.5);
				vec2 dv = rp - ctr;
				float dist = length(dv);
				float ring = sin((dist - ph * 0.45) * 40.0) * smoothstep(0.45, 0.0, abs(dist - ph * 0.45) * 6.0) * (1.0 - ph);
				off += normalize(dv + 1e-4) * ring;
			}
			vec3 wo = vec3(off.x, 0.0, off.y) * 0.25 * weather_rain * puddle;
			NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(wo, 0.0)).xyz);
		}
	}

	// Snow layer on upward faces of exposed materials, thinning at edges.
	if (exposed > 0.0 && weather_snow > 0.0) {
		float up_k = smoothstep(0.45, 0.9, wnrm.y);
		float n = vnoise(wpos.xz * 0.55) * 0.55 + vnoise(wpos.xz * 2.7) * 0.3 + vnoise(wpos.xz * 11.0) * 0.15;
		float edge = 1.0 - weather_snow;
		float cover = up_k * smoothstep(edge * 1.1 - 0.05, edge * 1.1 + 0.2, n * 0.7 + 0.3 * up_k);
		// Wheel ruts on roads stay slushier.
		if (pattern == 7) {
			float rut = smoothstep(0.35, 0.0, abs(fract(wpos.x / 3.5) - 0.5) - 0.25);
			cover *= 1.0 - rut * 0.55;
		}
		// Side faces get a dusting at their top edge.
		cover += (1.0 - up_k) * step(0.95, fract(wpos.y / 4.5)) * weather_snow * 0.5 * float(!up_facing);
		cover = clamp(cover * exposed, 0.0, 1.0);
		vec3 snow_col = vec3(0.84, 0.86, 0.89) * (0.93 + vnoise(wpos.xz * 23.0) * 0.07);
		col = mix(col, snow_col, cover);
		rough = mix(rough, 0.55, cover);
		metal = mix(metal, 0.0, cover);
		emis = mix(emis, emis * 0.2, cover * float(pattern == 9));
		// Glints.
		float glint = step(0.996, hash(floor(wpos.xz * 90.0) + floor(TIME * 0.0)));
		emis += vec3(0.9) * glint * cover * 0.25;
	}

	float ao = COLOR.r;
	ALBEDO = col * ao;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
}
