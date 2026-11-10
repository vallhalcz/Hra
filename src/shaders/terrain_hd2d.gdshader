// Terén HD-2D: 4 vrstvy (G0..G3) + útes. Váhy vrstev jdou z vertex color (R,G,B,A),
// které MapBuilder vytvoří z materiálů G0..G3 v Blenderu (nebo z vertex paintu).
// Přechody jsou měkké: vyhlazené váhy + šumové narušení hrany + makro variace barvy.
shader_type spatial;
render_mode specular_disabled;

group_uniforms layers;
uniform sampler2D tex0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex3 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cliff : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint0 : source_color = vec4(0.42, 0.62, 0.24, 1.0);
uniform vec4 tint1 : source_color = vec4(0.52, 0.70, 0.30, 1.0);
uniform vec4 tint2 : source_color = vec4(0.62, 0.52, 0.34, 1.0);
uniform vec4 tint3 : source_color = vec4(0.34, 0.50, 0.22, 1.0);
uniform vec4 tint_cliff : source_color = vec4(0.45, 0.40, 0.36, 1.0);
uniform float tiles_per_meter = 0.25;  // 1 / velikost dlaždice v metrech (4 m => 0.25)
uniform vec4 tiles = vec4(0.25);       // dlaždice na metr pro vrstvy G0..G3 (návrhář map je nastavuje)
uniform bool pixel_filter = false;     // true = pixel-art textura (ostré texely, bez vyhlazení)

group_uniforms splat;
uniform sampler2D splat_tex : filter_linear, repeat_disable;  // váhy vrstev z návrháře map (RGBA = G0..G3)
uniform bool use_splat = false;
uniform vec2 map_origin = vec2(-16.0, -14.0);
uniform vec2 map_size = vec2(32.0, 28.0);

group_uniforms blending;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.28;
uniform float edge_noise : hint_range(0.0, 1.0) = 0.45;
uniform float edge_noise_scale = 0.9;
uniform float slope_cliff_start : hint_range(0.0, 1.0) = 0.35;
uniform float slope_cliff_end : hint_range(0.0, 1.0) = 0.6;

group_uniforms macro;
uniform float macro_scale = 0.07;
uniform float macro_strength : hint_range(0.0, 0.5) = 0.18;
uniform float detail_scale = 1.7;
uniform float detail_strength : hint_range(0.0, 0.5) = 0.08;

varying vec3 wpos;
varying vec3 wnrm;

vec3 samp(sampler2D t, vec2 uv) {
	if (pixel_filter) {
		vec2 sz = vec2(textureSize(t, 0));
		return textureLod(t, (floor(uv * sz) + 0.5) / sz, 0.0).rgb;
	}
	return texture(t, uv).rgb;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = fbm(wpos.xz * edge_noise_scale);

	// měkké váhy: vyhlazené vertex váhy + šum + smoothstep
	vec4 raw = COLOR;
	if (use_splat) {
		vec2 ts = vec2(textureSize(splat_tex, 0));
		raw = texture(splat_tex, ((wpos.xz - map_origin) / map_size * (ts - 1.0) + 0.5) / ts);
	}
	vec4 w = clamp(raw, 0.0, 1.0) + (n - 0.5) * edge_noise;
	w = smoothstep(vec4(0.5 - edge_softness), vec4(0.5 + edge_softness), w);
	float sum = w.r + w.g + w.b + w.a;
	float cliff_w = clamp(1.0 - sum, 0.0, 1.0);
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	cliff_w = max(cliff_w, smoothstep(slope_cliff_start, slope_cliff_end, slope));

	vec3 c = samp(tex0, wpos.xz * tiles.x) * tint0.rgb * w.r
		+ samp(tex1, wpos.xz * tiles.y * 1.13) * tint1.rgb * w.g
		+ samp(tex2, wpos.xz * tiles.z * 0.93) * tint2.rgb * w.b
		+ samp(tex3, wpos.xz * tiles.w * 1.21) * tint3.rgb * w.a;
	c /= max(sum, 0.001);

	// útes: dvě roviny podle normály (bez natažení textury na svahu)
	vec3 an = abs(wnrm);
	vec3 cl = samp(tex_cliff, wpos.xy * tiles_per_meter) * an.z
		+ samp(tex_cliff, wpos.zy * tiles_per_meter) * an.x
		+ samp(tex_cliff, wpos.xz * tiles_per_meter) * an.y;
	cl = cl / max(an.x + an.y + an.z, 0.001) * tint_cliff.rgb;
	c = mix(c, cl, cliff_w);

	// makro + jemný detail variace barvy (proti "strohému" vzhledu)
	c *= 1.0 + (fbm(wpos.xz * macro_scale) - 0.5) * 2.0 * macro_strength;
	c *= 1.0 + (vnoise(wpos.xz * detail_scale) - 0.5) * 2.0 * detail_strength;

	ALBEDO = c;
	ROUGHNESS = 0.95;
}
