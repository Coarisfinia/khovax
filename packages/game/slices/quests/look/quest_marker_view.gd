class_name QuestMarkerView
extends Node3D
## Every open quest's marker (#300, owner: quests always have a marker): an arrow floating
## over what this machine's player's quest asks for next (QuestTargets). It shows through the fog,
## so it leads the player into it. The arrow's shape, not its color, says what it is (#68). Like
## on the Survey (#1328), the arrows of the quest this machine's player follows
## (QuestTracker.focused, #1298) are full size and bright yellow and float a little higher, so they
## draw over the others, which are smaller and grey: size, not only color, tells them apart. An
## arrow glides after a moving target and to its size, eases in and out, and bobs gently; it only
## reads the state and the quests. The Survey marks the same targets (#301).

## How high over the tile's top the arrow floats, and how far and how slowly it bobs.
const HEIGHT: float = 2.6
const BOB: float = 0.12
const BOB_SECONDS: float = 1.8
## How quickly an arrow glides after its target: the share of the way left it closes per second.
const GLIDE: float = 6.0
## How long an arrow takes to shrink away.
const EASE_SECONDS: float = 0.3
const COLOR: Color = Color(1.0, 0.9, 0.1)
## The arrows of the quests not followed: their color, their size as a share of the followed one's,
## and how much lower they float.
const OTHER_COLOR: Color = Color(0.66, 0.66, 0.66)
const OTHER_SHARE: float = 0.6
const OTHER_DROP: float = 0.4
## The arrow: a triangle facing the camera, its tip pointing down the screen at the target, inside
## a slightly bigger one in ink, like every outline in the cel look.
const HALF_WIDTH: float = 0.42
const LENGTH: float = 0.66
const INK_WIDTH: float = 0.08

@export var driver: Session
## Whose quests are marked: this machine's player's.
@export var keeper: QuestKeeper
## Which player the nearest target is measured from.
@export var input: LocalInput

## Each marked quest's arrow, by quest id, or one per choice on a step with choices
## (QuestTargets.of).
var markers: Dictionary[String, Node3D] = {}
## Where each arrow is headed: its target's tile.
var goals: Dictionary[String, Vector2i] = {}
## Whether each arrow is the followed quest's, by its key in `markers`.
var followed: Dictionary[String, bool] = {}
## The arrows' meshes: the followed quest's and the others', each a fill in ink.
var _fill: ArrayMesh
var _ink: ArrayMesh
var _other_fill: ArrayMesh
## The seconds the arrows have bobbed: game time, summed from the frames' steps rather than read
## off the clock, so a render with fixed frame steps (offscreen.py) bobs the same each run (#1140).
var _bobbed: float = 0.0


func _process(delta: float) -> void:
	show_quests()
	_bobbed = fmod(_bobbed + delta, BOB_SECONDS)
	var bob: float = sin(_bobbed * TAU / BOB_SECONDS) * BOB
	var glide: float = 1.0 - exp(-GLIDE * delta)
	# Every arrow faces the camera, so its tip points down the screen at its target.
	var camera: Camera3D = get_viewport().get_camera_3d()
	var facing: Quaternion = Quaternion.IDENTITY
	if camera != null:
		facing = (global_basis.inverse() * camera.global_basis).get_rotation_quaternion()
	for id: String in markers:
		var drop: float = 0.0 if followed[id] else OTHER_DROP
		var goal: Vector3 = _over(goals[id]) + Vector3(0.0, bob - drop, 0.0)
		markers[id].position = markers[id].position.lerp(goal, glide)
		var size: float = 1.0 if followed[id] else OTHER_SHARE
		markers[id].scale = markers[id].scale.lerp(Vector3.ONE * size, glide)
		markers[id].quaternion = facing


## Matches the arrows to the open quests' targets. Called every frame; tests call it directly.
func show_quests() -> void:
	var targets: Dictionary[String, Vector2i] = {}
	var quests: QuestTracker = keeper.quests() if keeper != null else null
	var focused: String = ""
	if driver != null and driver.state != null and quests != null:
		var here: String = driver.local_instance_name()
		targets = QuestTargets.of(driver.state, quests, input.slot, here)
		focused = quests.focused()
	for id: String in markers.keys():
		if not targets.has(id):
			_shrink_away(markers[id])
			var _dropped: bool = markers.erase(id)
			var _forgotten: bool = goals.erase(id)
			var _unfollowed: bool = followed.erase(id)
	for id: String in targets:
		if not markers.has(id):
			markers[id] = _add_arrow(_over(targets[id]))
		goals[id] = targets[id]
		# Its id, or its id and a choice's index after a slash.
		followed[id] = id.get_slice("/", 0) == focused
		(markers[id].get_child(1) as MeshInstance3D).mesh = _fill if followed[id] else _other_fill


## Where an arrow over `tile` floats, before bobbing.
func _over(tile: Vector2i) -> Vector3:
	return HexLayout.to_world(tile) + Vector3(0.0, HexGrid.TILE_HEIGHT + HEIGHT, 0.0)


## A new arrow at `at`, growing in, as `_process` sizes it.
func _add_arrow(at: Vector3) -> Node3D:
	if _fill == null:
		_fill = _triangle(HALF_WIDTH, LENGTH, COLOR, InkOutline.TEXT_PRIORITY)
		_other_fill = _triangle(HALF_WIDTH, LENGTH, OTHER_COLOR, InkOutline.TEXT_PRIORITY)
		var widen: float = INK_WIDTH * 2.0
		_ink = _triangle(HALF_WIDTH + widen, LENGTH + widen, Toon.INK, InkOutline.TEXT_PRIORITY - 1)
	var arrow: Node3D = Node3D.new()
	arrow.add_child(_part(_ink))
	arrow.add_child(_part(_fill))
	arrow.position = at
	arrow.scale = Vector3.ONE * 0.01
	add_child(arrow)
	return arrow


## One layer of an arrow, showing `mesh`.
static func _part(mesh: ArrayMesh) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	return part


## A flat triangle pointing down, `half_width` wide each side and `length` long, centered on its
## origin, in `color`, drawn over the fog at `priority`.
static func _triangle(half_width: float, length: float, color: Color, priority: int) -> ArrayMesh:
	var corners: PackedVector3Array = PackedVector3Array([
		Vector3(-half_width, length / 2.0, 0.0),
		Vector3(half_width, length / 2.0, 0.0),
		Vector3(0.0, -length / 2.0, 0.0),
	])
	var arrays: Array = []
	var _sized: int = arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = corners
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	# Over the fog, which hides everything else beneath it: only transparent materials skip the
	# depth test and keep their render priority.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = priority
	mesh.surface_set_material(0, material)
	return mesh


## Shrinks `arrow` away calmly, then frees it.
func _shrink_away(arrow: Node3D) -> void:
	var tween: Tween = arrow.create_tween().set_trans(Tween.TRANS_SINE)
	var _shrink: PropertyTweener = tween.tween_property(
		arrow,
		"scale",
		Vector3.ONE * 0.01,
		EASE_SECONDS,
	)
	var _done: CallbackTweener = tween.tween_callback(arrow.queue_free)
