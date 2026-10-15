// The ink outline as one full-screen pass (#166): ink wherever the depth jumps, so every mesh gets
// it, open or closed, thin or not (a cape, hair, leaves), at the same width on screen.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 ink : source_color = vec4(0.08, 0.07, 0.09, 1.0);
// How wide the ink is, in pixels.
uniform float width = 2.0;
// How sharply the depth must bend, relative to its distance, to draw ink. It compares each pixel
// with the average of its neighbours across it (a second difference), so an even slope like the
// tilted ground draws nothing however steep, and the small step from an arm to the body still does.
uniform float threshold = 0.02;

void vertex() {
	// A quad covering the whole screen, whatever the camera does.
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inverse_projection) {
	float raw = texture(depth_texture, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 step_size = width / VIEWPORT_SIZE;
	vec2 across = vec2(step_size.x, 0.0);
	vec2 down = vec2(0.0, step_size.y);
	float here = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float left = linear_depth(SCREEN_UV - across, INV_PROJECTION_MATRIX);
	float right = linear_depth(SCREEN_UV + across, INV_PROJECTION_MATRIX);
	float up = linear_depth(SCREEN_UV - down, INV_PROJECTION_MATRIX);
	float below = linear_depth(SCREEN_UV + down, INV_PROJECTION_MATRIX);
	float bend = max(abs(left + right - 2.0 * here), abs(up + below - 2.0 * here));
	ALBEDO = ink.rgb;
	ALPHA = bend / here > threshold ? ink.a : 0.0;
}
