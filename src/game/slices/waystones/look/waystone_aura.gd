class_name WaystoneAura
extends MeshInstance3D
## The blue aura on the ground around a standing stone its player hasn't activated yet (#2385): a
## disc reaching about RADIUS_TILES tiles out from the stone, brightest towards its rim and fading
## out past it, which WaystoneGlow shows until the stone is activated and hides once it is. It is
## there or it isn't, so it doesn't tell the stones apart by colour alone (#68).

## The aura's node name in the stone's figure.
const NAME: String = "WaystoneAura"
## How many tiles out from the stone the aura reaches: its rim fades out across the outer half of
## the last ring of tiles.
const RADIUS_TILES: float = 2.0
## The aura's blue, its alpha how strong it shows at its brightest.
const COLOR: Color = Color(0.25, 0.55, 1.0, 0.5)
## How far above the tile's top the aura lies, so the ground doesn't flicker through it.
const LIFT: float = 0.02

## The aura's material, shared by every aura.
static var _material: StandardMaterial3D


func _init() -> void:
	name = NAME
	var disc: PlaneMesh = PlaneMesh.new()
	disc.size = Vector2.ONE * 2.0 * radius()
	mesh = disc
	material_override = _shared_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = LIFT


## Whether the waystone `figure` shows its aura.
static func shows(figure: Node3D) -> bool:
	var aura: Node3D = figure.get_node_or_null(NAME) as Node3D
	return aura != null and aura.visible


## Shows the aura around the waystone `figure`, adding it the first time, or hides it.
static func show_on(figure: Node3D, on: bool) -> void:
	var aura: Node3D = figure.get_node_or_null(NAME) as Node3D
	if aura == null:
		if not on:
			return
		aura = WaystoneAura.new()
		figure.add_child(aura)
	aura.visible = on


## The aura's radius in world units: RADIUS_TILES tiles from the stone's tile, to the middle of the
## outer edge of the last ring's tiles.
static func radius() -> float:
	return (RADIUS_TILES + 0.5) * sqrt(3.0) * HexLayout.SIZE


## The aura's see-through material: a radial gradient, faint at the stone, strongest just inside the
## rim and gone at it. Unshaded, so the light doesn't change its blue.
static func _shared_material() -> StandardMaterial3D:
	if _material != null:
		return _material
	var gradient: Gradient = Gradient.new()
	var clear: Color = Color(COLOR, 0.0)
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 0.85, 1.0])
	gradient.colors = PackedColorArray([
		Color(COLOR, COLOR.a * 0.45),
		Color(COLOR, COLOR.a * 0.6),
		COLOR,
		clear,
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_texture = texture
	return _material
