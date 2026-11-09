// The halo on a monster's eye (EyeGlow, #1008): a disc facing the camera, keeping its node's scale,
// brightest in its middle and fading out to nothing at its edge, added onto what is behind it. The
// Compatibility renderer has no bloom: this brightens the eye and the fur around it the way a bloom
// would. One shader for every halo, each glow's material setting its own colour and brightness.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0);
// How bright the halo is, 0 to 1, or above for a brighter core that saturates toward white.
uniform float strength = 1.0;
// How fast it fades from its middle to its edge: low is a round, full disc, high a sharp core.
uniform float fade = 2.5;


void vertex() {
	// Facing the camera, as a billboard that keeps its node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			MAIN_CAM_INV_VIEW_MATRIX[0],
			MAIN_CAM_INV_VIEW_MATRIX[1],
			MAIN_CAM_INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}


void fragment() {
	// 0 in the middle, 1 at the disc's edge: a bright core that falls off softly.
	float out_from_middle = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	ALBEDO = color.rgb * strength;
	ALPHA = pow(1.0 - out_from_middle, fade);
}
