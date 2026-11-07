// Restrained full-screen grade: lift/gamma toward the palette, mild
// vignette, light film grain. One pass, toggled in settings.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette = 0.32;
uniform float grain = 0.035;
uniform float saturation = 0.86;
uniform vec3 shadow_tint = vec3(0.14, 0.2, 0.21);
uniform float shadow_tint_amount = 0.08;
uniform float damage = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = mix(c, c + shadow_tint * shadow_tint_amount, 1.0 - smoothstep(0.0, 0.5, l));
	vec2 d = SCREEN_UV - 0.5;
	float v = 1.0 - dot(d, d) * vignette * 2.2;
	c *= v;
	c = mix(c, vec3(0.42, 0.13, 0.12), damage * smoothstep(0.15, 0.7, length(d)) * 0.7);
	float g = hash(SCREEN_UV * vec2(1931.0, 1097.0) + fract(TIME * 7.13)) - 0.5;
	c += g * grain;
	COLOR = vec4(c, 1.0);
}
