class_name SpikesHitView
extends Node3D
## A ring's spikes hurting a wild monster (#777): a short thorn flash on the wall segment it pushes
## on, a few bright thorns that spring out of the segment toward it and sink back. The thorns are a
## shape, not only a color (#68), and the flash stays on the segment: the camera never shakes. It
## only reads the tick's events and the state.

const SECONDS: float = 0.45
## The share of SECONDS the thorns take to spring out; they sink back in the rest.
const SPRING_SHARE: float = 0.3
## A hot red, standing out from the trail's warm yellow it flashes on.
const THORN_COLOR: Color = Color(0.94, 0.26, 0.2)
const THORN_LENGTH: float = 0.8
const THORN_RADIUS: float = 0.11
## How far each thorn leans toward the monster, and how far apart the thorns fan out.
const LEAN: float = PI / 4.0
const FAN: float = PI / 6.0
const THORNS: int = 5

@export var driver: Session

## The flashes still playing, newest last. Kept here so tests can read them.
var flashes: Array[HexPiece] = []


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


## The wall segment the wild monster `struck` hurt pushes on, by the rings' own rule (#937).
static func wall_of(state: GameState, struck: SpikesStruck) -> Vector2i:
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	return domination.wall_pushed_by(state, struck.monster_id, struck.dominator_id)


## Flashes thorns on `wall`, leaning toward `toward`.
func show_hit(wall: Vector2i, toward: Vector2i) -> void:
	var flash: HexPiece = HexPiece.new()
	flash.base_offset = 0.0
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = THORN_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var facing: Vector3 = HexLayout.to_world(toward) - HexLayout.to_world(wall)
	var heading: float = atan2(facing.x, facing.z) if wall != toward else 0.0
	for thorn: int in THORNS:
		flash.add_child(_thorn(material, heading + (thorn - (THORNS - 1) / 2.0) * FAN))
	add_child(flash)
	flash.tile = wall
	flash.scale = Vector3.ZERO
	flashes.append(flash)
	var tween: Tween = flash.create_tween().set_trans(Tween.TRANS_SINE)
	var _out: PropertyTweener = tween.tween_property(
		flash, "scale", Vector3.ONE, SECONDS * SPRING_SHARE
	).set_ease(Tween.EASE_OUT)
	var _in: PropertyTweener = tween.tween_property(
		flash, "scale", Vector3.ZERO, SECONDS * (1.0 - SPRING_SHARE)
	).set_ease(Tween.EASE_IN)
	var _done: CallbackTweener = tween.tween_callback(_drop.bind(flash))


## One thorn, standing on the segment and leaning toward `heading` (radians around the up axis).
func _thorn(material: StandardMaterial3D, heading: float) -> Node3D:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = THORN_RADIUS
	cone.height = THORN_LENGTH
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = cone
	mesh.material_override = material
	mesh.position = Vector3(0.0, THORN_LENGTH / 2.0, 0.0)
	var pivot: Node3D = Node3D.new()
	pivot.rotation = Vector3(LEAN, heading, 0.0)
	pivot.rotation_order = EULER_ORDER_YXZ
	pivot.add_child(mesh)
	return pivot


func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for event: RefCounted in driver.local_events(events):
		var struck: SpikesStruck = event as SpikesStruck
		var monster: Entity = driver.state.entity(struck.monster_id) if struck != null else null
		if monster != null and FogView.ally_sees(driver.state, monster.tile):
			show_hit(wall_of(driver.state, struck), monster.tile)


func _drop(flash: HexPiece) -> void:
	flashes.erase(flash)
	flash.queue_free()
