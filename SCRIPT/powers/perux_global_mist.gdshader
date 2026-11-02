shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float blur_pixels = 12.0;
uniform float fog_opacity = 0.84;
uniform vec3 fog_tint : source_color = vec3(0.70, 0.75, 0.72);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += vec2(dot(p, p + vec2(45.32)));
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fog_noise(vec2 p) {
	float n = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		n += noise2(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return n;
}

void fragment() {
	float overlay_alpha = COLOR.a;
	vec2 uv = SCREEN_UV;
	vec2 field = uv * vec2(7.0, 4.4);
	vec2 drift = vec2(TIME * 0.34, -TIME * 0.23);
	float warp_x = fog_noise(field * 0.52 + drift);
	float warp_y = fog_noise(field * 0.52 + drift + vec2(8.3, 3.7));
	vec2 flow = field + (vec2(warp_x, warp_y) - 0.5) * 4.2;
	float billows = fog_noise(flow * 0.82 + drift * 0.72);
	float wisps = fog_noise(flow * 1.9 - drift * 1.25 + vec2(4.6, 1.9));
	float curl = 0.5 + 0.5 * sin(flow.x * 1.35 + flow.y * 0.72 + TIME * 0.42 + billows * 4.0);
	float cloud_shape = smoothstep(0.2, 0.82, billows * 0.78 + curl * 0.22);

	// La sfocatura respira con le masse di nebbia invece di restare uniforme.
	float blur_radius = blur_pixels * (0.68 + cloud_shape * 0.78);
	vec2 refraction = (vec2(warp_x, warp_y) - 0.5) * SCREEN_PIXEL_SIZE * blur_radius * 1.2;
	uv += refraction;
	vec2 d = SCREEN_PIXEL_SIZE * blur_radius;
	vec3 blurred = texture(screen_texture, uv).rgb * 0.20;
	blurred += texture(screen_texture, uv + vec2(d.x, 0.0)).rgb * 0.12;
	blurred += texture(screen_texture, uv - vec2(d.x, 0.0)).rgb * 0.12;
	blurred += texture(screen_texture, uv + vec2(0.0, d.y)).rgb * 0.12;
	blurred += texture(screen_texture, uv - vec2(0.0, d.y)).rgb * 0.12;
	blurred += texture(screen_texture, uv + d).rgb * 0.08;
	blurred += texture(screen_texture, uv - d).rgb * 0.08;
	blurred += texture(screen_texture, uv + vec2(d.x, -d.y)).rgb * 0.08;
	blurred += texture(screen_texture, uv + vec2(-d.x, d.y)).rgb * 0.08;

	float density = clamp(fog_opacity + (cloud_shape - 0.45) * 0.22 + (wisps - 0.5) * 0.07, 0.76, 0.97);
	vec3 fog = fog_tint * mix(0.82, 1.12, wisps);
	COLOR = vec4(mix(blurred, fog, density), overlay_alpha);
}
