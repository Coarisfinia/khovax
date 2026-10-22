class_name EyeGlow
extends Node3D
## The glow in a monster's eyes (#1008): a soft halo on each of its model's eyes (ModelPoints,
## #1007), following them through every clip, drawn by its shader (eye_glow.gdshader) in place of
## the bloom the Compatibility renderer lacks. It reads its monster's mood from its view:
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
## How a leaning shapes the halo (#1063), never by colour alone (#68): how fast it fades from its
## middle to its edge (higher fades sooner), how wide it is, and how bright its core, each as a
## share of the glow without a leaning. Harmony's is round and steady (it never flickers);
## supremacy's narrower, with a brighter, sharper core.
const FADE: float = 2.5
const ROUND_FADE: float = 1.2
const SHARP_FADE: float = 3.5
const SHARP_WIDTH: float = 0.75
const SHARP_CORE: float = 2.5
## The halos' shader, one for every glow: a fixed shader resource, compiled once for the session.
## A generated material shader is freed with its last material and compiled again with the next,
## and the GLES3 renderer then reloads it from its shader cache, which fails with a warning on the
## Android emulator's driver and so the device flow.
const SHADER: Shader = preload("res://slices/board/look/eye_glow.gdshader")

## Whether the monster is agitated (enraged, #220), and whether it fainted.
var agitated: bool = false
var out: bool = false
## The glow's colour: its monster's type's (TypeGlow).
var color: Color = COLOR
## The path the player it belongs to leans toward (PathLeaning.toward): PathMark.NONE for a wild
## monster, or while its player leans toward neither.
var leaning: String = PathMark.NONE
## How bright the glow is now, before the flare, easing toward its mood's.
var brightness: float = CALM
## What is left of the last attack's flare: 1 just as it struck, 0 once it's eased back.
var flare_left: float = 0.0
var _model: Node3D
var _material: ShaderMaterial = ShaderMaterial.new()
var _clock: float = 0.0


func _init() -> void:
	_material.shader = SHADER
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


## How bright the glow shows now: its mood's, the flare on top, and an agitated one's flicker,
## but for harmony's, which stays steady.
func shown() -> float:
	var flickers: bool = agitated and leaning != PathMark.HARMONY
	var flickering: float = 1.0 + FLICKER * sin(_clock * FLICKER_SPEED) if flickers else 1.0
	return clampf((brightness + FLARE * flare_left) * flickering, 0.0, 1.0)


## Moves the glow on by `seconds`: toward its mood's brightness, and the flare eased back that much.
func advance(seconds: float) -> void:
	_clock += seconds
	var wanted: float = 0.0 if out else (AGITATED if agitated else CALM)
	brightness = move_toward(brightness, wanted, EASE_SPEED * seconds)
	flare_left = maxf(flare_left - seconds / FLARE_SECONDS, 0.0)


## Puts a halo on each of the model's eyes, as bright and as wide as the glow shows now, in its
## colour and shaped by its leaning, standing out of the eye toward the camera.
func place() -> void:
	var eyes: Array[Vector3] = ModelPoints.eyes(_model)
	while get_child_count() < eyes.size():
		add_child(_halo_mesh())
	var glow: float = shown()
	var sharp: bool = leaning == PathMark.SUPREMACY
	var fade: float = FADE
	if leaning == PathMark.HARMONY:
		fade = ROUND_FADE
	elif sharp:
		fade = SHARP_FADE
	_material.set_shader_parameter(&"color", color)
	_material.set_shader_parameter(&"strength", glow * (SHARP_CORE if sharp else 1.0))
	_material.set_shader_parameter(&"fade", fade)
	var width: float = lerpf(NARROW, WIDE, glow) * (SHARP_WIDTH if sharp else 1.0)
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
