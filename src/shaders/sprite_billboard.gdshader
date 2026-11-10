// Svislý billboard (Y) pro scatter sprity (tráva, kameny...) s lehkým vlněním ve větru.
// Sprity jsou vždy kolmo k zemi (jako v Octopath), natočené čelem ke kameře.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform float wind_strength = 0.05;
uniform float wind_speed = 1.6;

void vertex() {
	vec3 z = normalize(vec3(INV_VIEW_MATRIX[2].x, 0.0, INV_VIEW_MATRIX[2].z));
	vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	// vlnění: nahoře (UV.y = 0) víc, u země nic
	VERTEX.x += sin(TIME * wind_speed + origin.x * 0.7 + origin.z * 0.5) * wind_strength * (1.0 - UV.y);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * sx, 0.0), vec4(0.0, sy, 0.0, 0.0), vec4(z * sx, 0.0), vec4(origin, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	// osvětlení ze směru nahoru, ať sprity nejsou při ostrém slunci černé
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}
