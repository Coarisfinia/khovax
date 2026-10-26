// The fog of war as a soft cloud (#156): one flat layer over the region. Where no ally has ever
// looked lies thick cloud, hiding the ground. Over ground seen before lies light fog (#175): low,
// thin wisps drifting along, through which the ground stays readable. It's told apart from the
// cloud by its shape, not only its brightness (#68). Clear where an ally sees now. How much of each
// lies on a tile comes from `fog_texture`, one texel per tile in axial coordinates (FogCloud),
// sampled at each pixel's fractional tile so the edges fade between tiles instead of stepping. Not
// cel-shaded (owner, #156): banded fog with ink edges was too busy. Cheap enough for mobile and the
// web: one plane, one material, four texture reads.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Fog per tile, red the thick cloud and green the light fog, each 0 to 1; texel (q, r) is tile
// (q, r) + `texel_offset`.
uniform sampler2D fog_texture : filter_linear, repeat_disable;
uniform vec2 texel_offset;
uniform vec2 texture_size;
// Hex size in world units (HexLayout.SIZE).
uniform float hex_size = 1.0;
uniform sampler2D cloud_noise : filter_linear, repeat_enable;
uniform vec4 cloud_light : source_color = vec4(0.86, 0.88, 0.93, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.70, 0.73, 0.82, 1.0);
// The light the cloud is seen in (Daylight, #1360): it's drawn unshaded, so it dims with the night
// by this tint instead of by the scene's lights. White leaves it as it is.
uniform vec4 daylight : source_color = vec4(1.0);
// How fast the cloud drifts, in noise texture widths per second: barely moving (motion sickness).
uniform vec2 drift = vec2(0.004, 0.002);
// How many world units one noise texture width covers.
uniform float noise_scale = 40.0;
// The thick cloud, roughened by the noise, fades in from `clear_below` to full at `thick_above`.
uniform float clear_below = 0.3;
uniform float thick_above = 0.9;
// The light fog's wisps: stretched along x, thinnest and thickest alpha.
uniform vec2 wisp_scale = vec2(18.0, 5.0);
uniform float wisp_thin = 0.3;
uniform float wisp_thick = 0.6;

varying vec3 world;
// The position within the instance, whose coordinates the fog texture is in: the views of the
// current instance stand at its place in the world (#189), so the world position is off by that
// place.
varying vec3 in_instance;
// The cloud's own transform within the instance.
uniform mat4 to_instance;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	in_instance = (to_instance * vec4(VERTEX, 1.0)).xyz;
}

// The fog at a world position, blended between the tiles around it: x thick, y light.
vec2 fog_at(vec2 xz) {
	float r = xz.y / (1.5 * hex_size);
	float q = xz.x / (sqrt(3.0) * hex_size) - r * 0.5;
	vec2 uv = (vec2(q, r) + texel_offset + 0.5) / texture_size;
	return texture(fog_texture, uv).rg;
}

void fragment() {
	vec2 at = world.xz / noise_scale;
	float noise = texture(cloud_noise, at + drift * TIME).r * 0.65;
	noise += texture(cloud_noise, at * 2.3 - drift * TIME * 1.7).r * 0.35;
	// The noise stays in the world, so the cloud doesn't jump when crossing into the next instance.
	vec2 fog = fog_at(in_instance.xz);
	// The noise only roughens the cloud: never enough to open a hole in it.
	float thick = smoothstep(clear_below, thick_above, fog.x + (noise - 0.5) * 0.25);
	float wisps = texture(cloud_noise, world.xz / wisp_scale + drift * TIME * 2.0).r;
	// Fading out as the cloud thickens, so wisps don't bleed into the cloud's edge.
	float light = fog.y * (1.0 - thick) * mix(wisp_thin, wisp_thick, smoothstep(0.35, 0.75, wisps));
	vec3 cloud = mix(cloud_shade.rgb, cloud_light.rgb, smoothstep(0.3, 0.7, noise));
	ALBEDO = mix(cloud_light.rgb, cloud, thick) * daylight.rgb;
	ALPHA = max(thick, light);
}
