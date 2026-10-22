class_name EyeGlow
extends Node3D
## The glow in a monster's eyes (#1008): a soft halo on each of its model's eyes (ModelPoints,
## #1007), following them through every clip. The Compatibility renderer has no bloom, so the glow
## is a camera-facing disc that fades out from its middle, added onto what is behind it: it
## brightens
## the eye and the fur around it the way a bloom would. It reads its monster's mood from its view:
## calm, it glows softly and steadily; agitated, brighter and wider, flickering; and an attack makes
## it flare up and ease back. Fainted, it goes out. It changes how bright and how big it is, never
## only its colour (#68), and eases between moods. A model without eyes gets none.

## The glow's colour until it takes its monster's type's (#1008).
const COLOR: Color = Color(0.3, 0.9, 1.0)
## How bright the glow is calm, agitated and at the peak of an attack's flare, 1 being full.
const CALM: float = 0.45
const AGITATED: float = 0.8
const FLARE: float = 0.6
## How long an attack's flare takes to ease back, and how fast the glow eases to a new mood, in
## its brightness per second.
const FLARE_SECONDS: float = 0.7
const EASE_SPEED: float = 1.5
## How much an agitated glow flickers, as a share of its brightness, and how fast.
const FLICKER: float = 0.15
const FLICKER_SPEED: float = 9.0
## How wide the halo is at full brightness, in the model's units, and at none.
const WIDE: float = 0.18
const NARROW: float = 0.07
## How far the halo stands out of the eye toward the camera, as a share of its width, so the head
## hides it only when it is between the eye and the camera.
const STAND_OUT: float = 0.35

static var _halo: GradientTexture2D
## The halos' material, which each glow copies to set its own brightness. Kept for good, so its
## shader stays compiled while no monster is shown: compiled again, the GLES3 renderer reloads it
## from its shader cache, which fails with a warning on some Android drivers.
static var _halo_material: StandardMaterial3D

## Whether the monster is agitated (enraged, #220), and whether it fainted.
var agitated: bool = false
var out: bool = false
## How bright the glow is now, before the flare, easing toward its mood's.
var brightness: float = CALM
## What is left of the last attack's flare: 1 just as it struck, 0 once it's eased back.
var flare_left: float = 0.0
var _model: Node3D
var _material: StandardMaterial3D
var _clock: float = 0.0


func _init() -> void:
	_material = _template().duplicate() as StandardMaterial3D
	# After the model's clips have posed it this frame, so the halos sit on the eyes.
	process_priority = 1


func _process(delta: float) -> void:
	advance(delta)
	place()


## Gives `model` a glow in its eyes, under it, and returns it.
static func add_to(model: Node3D) -> EyeGlow:
	var glow: EyeGlow = EyeGlow.new()
	glow.name = "EyeGlow"
	glow._model = model
	model.add_child(glow)
	return glow


## The glow in `model`'s eyes, or null when it has none.
static func of(model: Node3D) -> EyeGlow:
	return model.get_node_or_null("EyeGlow") as EyeGlow


## The monster attacked: the glow flares up and eases back.
func flare() -> void:
	flare_left = 1.0


## How bright the glow shows now: its mood's, the flare on top, and an agitated one's flicker.
func shown() -> float:
	var flickering: float = 1.0 + FLICKER * sin(_clock * FLICKER_SPEED) if agitated else 1.0
	return clampf((brightness + FLARE * flare_left) * flickering, 0.0, 1.0)


## Moves the glow on by `seconds`: toward its mood's brightness, and the flare eased back that much.
func advance(seconds: float) -> void:
	_clock += seconds
	var wanted: float = 0.0 if out else (AGITATED if agitated else CALM)
	brightness = move_toward(brightness, wanted, EASE_SPEED * seconds)
	flare_left = maxf(flare_left - seconds / FLARE_SECONDS, 0.0)


## Puts a halo on each of the model's eyes, as bright and as wide as the glow shows now, standing
## out of the eye toward the camera.
func place() -> void:
	var eyes: Array[Vector3] = ModelPoints.eyes(_model)
	while get_child_count() < eyes.size():
		add_child(_halo_mesh())
	var glow: float = shown()
	_material.albedo_color = Color(COLOR * glow, 1.0)
	var width: float = lerpf(NARROW, WIDE, glow)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var size: float = _model.global_basis.get_scale().x
	for index: int in eyes.size():
		var halo: MeshInstance3D = get_child(index) as MeshInstance3D
		var toward: Vector3 = Vector3.ZERO
		if camera != null:
			toward = (camera.global_position - eyes[index]).normalized()
		halo.global_position = eyes[index] + toward * width * STAND_OUT * size
		halo.scale = Vector3.ONE * width
		halo.visible = glow > 0.0


func _halo_mesh() -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.material = _material
	var halo: MeshInstance3D = MeshInstance3D.new()
	halo.mesh = quad
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return halo


## The halos' material: unshaded, added onto what is behind it, facing the camera, made once.
static func _template() -> StandardMaterial3D:
	if _halo_material == null:
		_halo_material = StandardMaterial3D.new()
		_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_halo_material.billboard_keep_scale = true
		_halo_material.albedo_texture = _halo_texture()
	return _halo_material


## A disc, white in its middle and fading out to nothing at its edge, made once.
static func _halo_texture() -> GradientTexture2D:
	if _halo == null:
		var fade: Gradient = Gradient.new()
		fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		fade.add_point(0.2, Color(1.0, 1.0, 1.0, 0.85))
		fade.add_point(0.5, Color(1.0, 1.0, 1.0, 0.25))
		_halo = GradientTexture2D.new()
		_halo.gradient = fade
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.5)
		_halo.fill_to = Vector2(0.5, 0.0)
		_halo.width = 64
		_halo.height = 64
	return _halo
