class_name FogCloud
extends MeshInstance3D
## The fog of war's look (#156): one cloud layer over the region and beyond it, drawn by
## its shader, beside it, from the brightness FogView eases per tile. Each tile's fog goes into a
## small texture, one texel per tile in axial coordinates, which the shader blends between tiles:
## thick cloud where no ally has ever looked, and light fog (#175) over ground seen before. Outside
## the region lies cloud, so the region's edge sinks into it instead of ending at a void.

const SHADER: Shader = preload("res://slices/fog/look/fog_cloud.gdshader")
## How far the cloud reaches past the region, in tiles.
const MARGIN: int = 12
## Where the cloud floats: just over the tiles, under everything standing on them.
const HEIGHT: float = HexGrid.TILE_HEIGHT + 0.02

## The neighbours drawn next to the region, which the cloud reaches over too.
@export var neighbours: NeighbourView

## The fog per tile as the shader reads it: red the thick cloud (1 never seen), green the light fog
## (1 seen before). Under thick cloud the light fog is 0, so it never bleeds into tiles in sight
## next to unexplored ground.
var fog_image: Image
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


## Tints the cloud by the light it's seen in (#1360): drawn unshaded, it doesn't follow the scene's
## lights, so Daylight hands it the hour's light; white leaves it as it is.
func light_by(color: Color) -> void:
	(material_override as ShaderMaterial).set_shader_parameter("daylight", color)


## Shows the fog over `region` from each tile's brightness (FogView's scale), or hides it when
## `brightness` is empty (no fog in this instance). Only the tiles in `changed` are drawn again
## (#1361), unless `everything` is set or the region is new: then the cloud is fitted anew, all
## thick
## cloud to start with, and every tile is, so a tile no longer in `brightness` (a neighbour that
## went or moved, #1388) lies under thick cloud again, and the cloud reaches the neighbours now.
func show_fog(
		region: Region,
		brightness: Dictionary[Vector2i, float],
		changed: Array[Vector2i],
		everything: bool,
) -> void:
	visible = region != null and not brightness.is_empty()
	if not visible:
		return
	var tiles: Array = changed
	if region != _region or everything:
		_fit(region)
		tiles = brightness.keys()
	# Only texels whose value changed are written, and the texture is uploaded only then: once the
	# fog has settled, a frame costs nothing.
	var written: bool = false
	for tile: Vector2i in tiles:
		var fog: Color = _fog_of(brightness[tile])
		var texel: Vector2i = tile + _offset
		if not fog_image.get_pixel(texel.x, texel.y).is_equal_approx(fog):
			fog_image.set_pixel(texel.x, texel.y, fog)
			written = true
	if written:
		_texture.update(fog_image)


## The fog the shader reads on `tile`: x the thick cloud, y the light fog, each 0 to 1. Tests
## check the fog image with it.
func fog_on(tile: Vector2i) -> Vector2:
	var texel: Vector2i = tile + _offset
	var fog: Color = fog_image.get_pixel(texel.x, texel.y)
	return Vector2(fog.r, fog.g)


## A tile's fog from its brightness, quantized as the fog image stores it, so an unchanged tile
## compares equal: thick cloud from seen before (0) to never seen (1), light fog from seen now (0)
## to seen before (1) and back to 0 under the thick cloud.
static func _fog_of(bright: float) -> Color:
	var thick: float = clampf(inverse_lerp(FogView.REMEMBERED, FogView.UNSEEN, bright), 0.0, 1.0)
	var seen: float = clampf(inverse_lerp(FogView.VISIBLE, FogView.REMEMBERED, bright), 0.0, 1.0)
	var light: float = seen * (1.0 - thick)
	return Color(roundf(thick * 255.0) / 255.0, roundf(light * 255.0) / 255.0, 0.0)


## Sizes the fog image and the cloud to `region`, its neighbours and a margin, all cloud to start
## with.
func _fit(region: Region) -> void:
	_region = region
	var low: Vector2i = Vector2i.MAX
	var high: Vector2i = Vector2i.MIN
	for tile: Vector2i in _covered(region):
		low = low.min(tile)
		high = high.max(tile)
	_offset = Vector2i(MARGIN, MARGIN) - low
	var size: Vector2i = high - low + Vector2i(MARGIN, MARGIN) * 2 + Vector2i.ONE
	fog_image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RG8)
	fog_image.fill(Color.RED)
	_texture = ImageTexture.create_from_image(fog_image)
	var cloud: ShaderMaterial = material_override as ShaderMaterial
	cloud.set_shader_parameter("fog_texture", _texture)
	cloud.set_shader_parameter("texel_offset", Vector2(_offset))
	cloud.set_shader_parameter("texture_size", Vector2(size))
	# A plane over the fog image's whole parallelogram, centered on it.
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
	cloud.set_shader_parameter("to_instance", Projection(transform))


## The tiles the cloud has to cover: the region's and its neighbours', in the region's coordinates.
func _covered(region: Region) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = region.sorted_tiles()
	if neighbours != null:
		tiles.append_array(neighbours.placed_tiles())
	return tiles
