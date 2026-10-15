// The fog of war as a soft cloud (#156): one flat layer over the region, thick where no ally has
// ever looked, a thin veil over what was seen before, clear where an ally sees now. How much fog
// lies on each tile comes from `fog_map`, one texel per tile in axial coordinates (FogCloud),
// sampled at each pixel's fractional tile so the edge of sight fades between tiles instead of
// stepping. A slowly drifting noise roughens it into cloud. Unlike the rest of the look it isn't
// cel-shaded (owner, #156): banded fog with ink edges was too busy. Cheap enough for mobile and the
// web: one plane, one material, three texture reads.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Fog per tile: 0 seen now, 1 never seen; texel (q, r) is tile (q, r) + `map_offset`.
uniform sampler2D fog_map : filter_linear, repeat_disable;
uniform vec2 map_offset;
uniform vec2 map_size;
// Hex size in world units (HexLayout.SIZE).
uniform float hex_size = 1.0;
uniform sampler2D cloud_noise : filter_linear, repeat_enable;
uniform vec4 cloud_light : source_color = vec4(0.86, 0.88, 0.93, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.70, 0.73, 0.82, 1.0);
// How fast the cloud drifts, in noise texture widths per second: barely moving (motion sickness).
uniform vec2 drift = vec2(0.004, 0.002);
// How many world units one noise texture width covers.
uniform float noise_scale = 40.0;
// The fog, roughened by the noise, fades in from `clear_below` to full cloud at `thick_above`. A
// tile seen before sits in between: a veil it can be read through.
uniform float clear_below = 0.35;
uniform float thick_above = 0.95;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// The fog at a world position, blended between the tiles around it.
float fog_at(vec2 xz) {
	float r = xz.y / (1.5 * hex_size);
	float q = xz.x / (sqrt(3.0) * hex_size) - r * 0.5;
	vec2 uv = (vec2(q, r) + map_offset + 0.5) / map_size;
	return texture(fog_map, uv).r;
}

void fragment() {
	vec2 at = world.xz / noise_scale;
	float noise = texture(cloud_noise, at + drift * TIME).r * 0.65;
	noise += texture(cloud_noise, at * 2.3 - drift * TIME * 1.7).r * 0.35;
	// The noise only roughens the fog: never enough to open a hole in thick cloud.
	float fog = fog_at(world.xz) + (noise - 0.5) * 0.25;
	ALBEDO = mix(cloud_shade.rgb, cloud_light.rgb, smoothstep(0.3, 0.7, noise));
	ALPHA = smoothstep(clear_below, thick_above, fog);
}
