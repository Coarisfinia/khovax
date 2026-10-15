class_name FogCloud
extends MeshInstance3D
## The fog of war's look (#156): one cloud layer over the region and beyond it, drawn by
## view/fog_cloud.gdshader from the brightness FogView eases per tile. Each tile's fog goes into a
## small texture,
## one texel per tile in axial coordinates, which the shader blends between tiles. Outside the
## region lies cloud, so the region's edge sinks into it instead of ending at a void.

const SHADER: Shader = preload("res://view/fog_cloud.gdshader")
## How far the cloud reaches past the region, in tiles.
const MARGIN: int = 12
## Where the cloud floats: just over the tiles, under everything standing on them.
const HEIGHT: float = HexGrid.TILE_HEIGHT + 0.02

## The fog per tile as the shader reads it: 0 seen now, 255 never seen.
var fog_map: Image
var _texture: ImageTexture
var _offset: Vector2i = Vector2i.ZERO
var _region: Region


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cloud: ShaderMaterial = ShaderMaterial.new()
	cloud.shader = SHADER
	# After the ink, so thick cloud hides the lines of unexplored ground and the veil softens them;
	# below text in the world, which stays readable.
	cloud.render_priority = InkOutline.PRIORITY + 1
	cloud.set_shader_parameter("hex_size", HexLayout.SIZE)
	var noise: NoiseTexture2D = NoiseTexture2D.new()
	noise.seamless = true
	noise.noise = FastNoiseLite.new()
	cloud.set_shader_parameter("cloud_noise", noise)
	material_override = cloud
	visible = false


## Shows the fog over `region` from each tile's brightness (FogView's scale), or hides it when
## `brightness` is empty (no fog in this instance).
func show_fog(region: Region, brightness: Dictionary[Vector2i, float]) -> void:
	visible = region != null and not brightness.is_empty()
	if not visible:
		return
	if region != _region:
		_fit(region)
	# Only texels whose value changed are written, and the texture is uploaded only then: once the
	# fog has settled, a frame costs nothing.
	var changed: bool = false
	for tile: Vector2i in brightness:
		var fog: float = inverse_lerp(FogView.VISIBLE, FogView.UNSEEN, brightness[tile])
		var level: int = roundi(clampf(fog, 0.0, 1.0) * 255.0)
		var texel: Vector2i = tile + _offset
		if roundi(fog_map.get_pixel(texel.x, texel.y).r * 255.0) != level:
			fog_map.set_pixel(texel.x, texel.y, Color(level / 255.0, 0.0, 0.0))
			changed = true
	if changed:
		_texture.update(fog_map)


## The fog the shader reads on `tile`, 0 to 1. Tests check the map with it.
func fog_on(tile: Vector2i) -> float:
	var texel: Vector2i = tile + _offset
	return fog_map.get_pixel(texel.x, texel.y).r


## Sizes the map and the cloud to `region` and its margin, all cloud to start with.
func _fit(region: Region) -> void:
	_region = region
	var low: Vector2i = Vector2i.MAX
	var high: Vector2i = Vector2i.MIN
	for tile: Vector2i in region.sorted_tiles():
		low = low.min(tile)
		high = high.max(tile)
	_offset = Vector2i(MARGIN, MARGIN) - low
	var size: Vector2i = high - low + Vector2i(MARGIN, MARGIN) * 2 + Vector2i.ONE
	fog_map = Image.create_empty(size.x, size.y, false, Image.FORMAT_R8)
	fog_map.fill(Color.WHITE)
	_texture = ImageTexture.create_from_image(fog_map)
	var cloud: ShaderMaterial = material_override as ShaderMaterial
	cloud.set_shader_parameter("fog_map", _texture)
	cloud.set_shader_parameter("map_offset", Vector2(_offset))
	cloud.set_shader_parameter("map_size", Vector2(size))
	# A plane over the map's whole parallelogram, centered on it.
	var corners: Array[Vector3] = [
		HexLayout.to_world(low - Vector2i(MARGIN, MARGIN)),
		HexLayout.to_world(high + Vector2i(MARGIN, MARGIN)),
		HexLayout.to_world(Vector2i(low.x - MARGIN, high.y + MARGIN)),
		HexLayout.to_world(Vector2i(high.x + MARGIN, low.y - MARGIN)),
	]
	var bounds: AABB = AABB(corners[0], Vector3.ZERO)
	for corner: Vector3 in corners:
		bounds = bounds.expand(corner)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(bounds.size.x, bounds.size.z)
	mesh = plane
	position = Vector3(bounds.get_center().x, HEIGHT, bounds.get_center().z)
