// The ink outline as one full-screen pass (#166): ink wherever the depth jumps, so every mesh gets
// it, open or closed, thin or not (a cape, hair, leaves), at the same width on screen.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 ink : source_color = vec4(0.08, 0.07, 0.09, 1.0);
// How wide the ink is, in pixels.
uniform float width = 4.0;
// How sharply the depth must bend, relative to its distance, to draw ink. It compares each pixel
// with the average of its neighbours across it (a second difference), so an even slope like the
// tilted ground draws nothing however steep, and the small step from an arm to the body still does.
// Only a pixel farther than that average gets ink: the line lies around a thing, on what's behind
// it, so a thin sheet seen edge-on (a hanging cape) keeps its color instead of turning to ink.
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

// 1.0 where `uv` lies just behind an edge, 0.0 where it doesn't.
float ink_at(vec2 uv, vec2 step_size, mat4 inverse_projection) {
	vec2 across = vec2(step_size.x, 0.0);
	vec2 down = vec2(0.0, step_size.y);
	float here = linear_depth(uv, inverse_projection);
	float left = linear_depth(uv - across, inverse_projection);
	float right = linear_depth(uv + across, inverse_projection);
	float up = linear_depth(uv - down, inverse_projection);
	float below = linear_depth(uv + down, inverse_projection);
	float bend = max(2.0 * here - left - right, 2.0 * here - up - below);
	return bend / here > threshold ? 1.0 : 0.0;
}

void fragment() {
	vec2 pixel = 1.0 / VIEWPORT_SIZE;
	vec2 step_size = width * pixel;
	// The ink of this pixel and its neighbours right, below and diagonally, averaged: MSAA smooths
	// only the edges of meshes, this pass draws inside one quad, and the Compatibility renderer has
	// no screen-space AA. Averaging fades each stair step of a line over a pixel.
	float coverage = ink_at(SCREEN_UV, step_size, INV_PROJECTION_MATRIX);
	coverage += ink_at(SCREEN_UV + vec2(pixel.x, 0.0), step_size, INV_PROJECTION_MATRIX);
	coverage += ink_at(SCREEN_UV + vec2(0.0, pixel.y), step_size, INV_PROJECTION_MATRIX);
	coverage += ink_at(SCREEN_UV + pixel, step_size, INV_PROJECTION_MATRIX);
	ALBEDO = ink.rgb;
	ALPHA = ink.a * coverage * 0.25;
}
