// Festival crowd impostor. The MultiMesh carries the robe colour per instance;
// head and hair come from height, so one mesh serves everyone. A small sway
// and step keep the mass from looking frozen (the sim moves them along lanes).
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

varying float body_y;
varying vec3 robe;

void vertex() {
	body_y = VERTEX.y;
	robe = COLOR.rgb;
	float ph = float(INSTANCE_ID) * 1.73;
	float w = TIME * 5.0 + ph;
	float up = smoothstep(0.1, 1.2, VERTEX.y);
	VERTEX.x += sin(w * 0.5) * 0.035 * up;
	VERTEX.z += cos(w * 0.5) * 0.02 * up;
	VERTEX.y += abs(sin(w)) * 0.03 * step(0.05, VERTEX.y);
}

void fragment() {
	vec3 c = robe;
	if (body_y > 1.68) {
		c = vec3(0.03, 0.03, 0.035);
	} else if (body_y > 1.43) {
		c = vec3(0.3, 0.19, 0.13);
	}
	ALBEDO = c;
	ROUGHNESS = 0.88;
}
