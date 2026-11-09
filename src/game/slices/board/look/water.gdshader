// The one water (#1933): every water surface is drawn by this shader, and only its parameters vary.
// Stylized to fit the flat matte look: toon light, two hard ripple bands and a soft foam along the
// shore. Everything is computed from the surface's own position, with no depth or screen texture,
// so it runs in the Compatibility renderer (web) too.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// Multiplies each instance's color, which is the tile's own (its blueprint's, or what paints it).
uniform vec4 color : source_color = vec4(1.0);
// Multiplies the color away from the shore, where the water is deep.
uniform vec4 depth_tint : source_color = vec4(0.72, 0.8, 0.92, 1.0);
// How fast the ripples move: slowly, since the game is designed around motion sickness.
uniform float ripple_speed = 0.35;
// The way the water flows, on the ground plane (x, z).
uniform vec2 flow_direction = vec2(1.0, 0.35);
// How many ripples fit one world unit, and how much lighter a ripple's crest is.
uniform float ripple_scale = 2.2;
uniform float crest_light = 0.1;
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 0.97, 1.0);
// How far from the shore the foam and the shallows reach, in world units.
uniform float foam_width = 0.14;
uniform float shallow_width = 0.5;
// From a tile's center to the middle of its edge, in world units (WaterSurface sets it).
uniform float edge_distance = 0.8;

// Which of the six edges are shore, one bit each, the bit's edge at bit * 60 degrees (x towards z).
varying flat int shore;
varying vec3 world;
varying vec2 local;

void vertex() {
	shore = int(INSTANCE_CUSTOM.r * 255.0 + 0.5);
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = VERTEX.xz;
}

// The distance to the nearest shore edge; large where the tile has none.
float shore_distance() {
	float nearest = 1000.0;
	for (int edge = 0; edge < 6; edge++) {
		if (((shore >> edge) & 1) == 1) {
			float angle = float(edge) * PI / 3.0;
			float along = dot(local, vec2(cos(angle), sin(angle)));
			nearest = min(nearest, edge_distance - along);
		}
	}
	return nearest;
}

// A ripple field from -1 to 1, moving along the flow.
float ripples(vec2 at, float time) {
	float first = sin(at.x * 1.3 + sin(at.y * 0.9 + time * 0.7) * 1.4 - time);
	float second = sin(at.y * 1.7 - sin(at.x * 1.1 - time * 0.5) * 1.2 - time * 0.8);
	return (first + second) * 0.5;
}

void fragment() {
	vec2 flow = normalize(flow_direction);
	vec2 along_flow = vec2(dot(world.xz, flow), dot(world.xz, vec2(-flow.y, flow.x)));
	float ripple = ripples(along_flow * ripple_scale, TIME * ripple_speed);
	float to_shore = shore_distance();
	float deep = smoothstep(0.0, shallow_width, to_shore);
	vec3 water = color.rgb * COLOR.rgb * mix(vec3(1.0), depth_tint.rgb, deep);
	// Two hard bands, not a gradient: the same comic look as the toon light.
	water += crest_light * step(0.45, ripple);
	// The foam's edge wobbles with the ripple and stays soft, unlike the bands.
	float foam = 1.0 - smoothstep(foam_width * 0.4, foam_width, to_shore + ripple * 0.03);
	ALBEDO = mix(water, foam_color.rgb, foam);
	ROUGHNESS = 1.0;
}
