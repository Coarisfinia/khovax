class_name QuestMarkerView
extends Node3D
## Every open quest's marker (#300, owner: quests always have a marker): an arrow floating
## over what this machine's player's quest asks for next, the nearest wild monster of the species a
## domination step names (any, when it names none), or the one quest target it names (#625), the
## nearest closed treasure chest, the nearest
## tile of the place a reached step names (#339) or of the region piece an entered step names
## (#350), or the nearest exit leading to the instance it names (#370), or that the step counts in
## while the player is elsewhere (#769). It shows through the fog,
## so it leads the player into it; a wild monster still hiding in its tile (#202) isn't pointed
## at, since that would give it away. The arrow's shape, not its color, says what it is (#68). It
## glides after a moving target, eases in and out, and bobs gently; it only reads the state and
## the profile. The same targets will be marked on the Survey (#301).

## How high over the tile's top the arrow floats, and how far and how slowly it bobs.
const HEIGHT: float = 2.6
const BOB: float = 0.12
const BOB_SECONDS: float = 1.8
## How quickly an arrow glides after its target: the share of the way left it closes per second.
const GLIDE: float = 6.0
## How long an arrow takes to grow in or shrink away.
const EASE_SECONDS: float = 0.3
const COLOR: Color = Color(1.0, 0.84, 0.25)
## The arrow: a triangle facing the camera, its tip pointing down the screen at the target, inside
## a slightly bigger one in ink, like every outline in the cel look.
const HALF_WIDTH: float = 0.42
const LENGTH: float = 0.66
const INK_WIDTH: float = 0.08

@export var driver: Session
## Whose quests are marked: this machine's player's profile.
@export var holder: ProfileHolder
## Which player the nearest target is measured from.
@export var input: LocalInput

## Each marked quest's arrow, by quest id, or one per choice on a step with choices (targets_of).
var markers: Dictionary[String, Node3D] = {}
## Where each arrow is headed: its target's tile.
var goals: Dictionary[String, Vector2i] = {}
var _fill: ArrayMesh
var _ink: ArrayMesh


func _process(delta: float) -> void:
	show_quests()
	var bob: float = sin(Time.get_ticks_msec() / 1000.0 * TAU / BOB_SECONDS) * BOB
	var glide: float = 1.0 - exp(-GLIDE * delta)
	# Every arrow faces the camera, so its tip points down the screen at its target.
	var camera: Camera3D = get_viewport().get_camera_3d()
	var facing: Quaternion = Quaternion.IDENTITY
	if camera != null:
		facing = (global_basis.inverse() * camera.global_basis).get_rotation_quaternion()
	for id: String in markers:
		var goal: Vector3 = _over(goals[id]) + Vector3(0.0, bob, 0.0)
		markers[id].position = markers[id].position.lerp(goal, glide)
		markers[id].quaternion = facing


## Matches the arrows to the open quests' targets. Called every frame; tests call it directly.
func show_quests() -> void:
	var targets: Dictionary[String, Vector2i] = {}
	if driver != null and driver.state != null and holder != null and holder.keeper != null:
		var here: String = driver.local_instance_name()
		targets = targets_of(driver.state, holder.keeper.profile, input.slot, here)
	for id: String in markers.keys():
		if not targets.has(id):
			_shrink_away(markers[id])
			var _dropped: bool = markers.erase(id)
			var _forgotten: bool = goals.erase(id)
	for id: String in targets:
		if not markers.has(id):
			markers[id] = _add_arrow(_over(targets[id]))
		goals[id] = targets[id]


## The tile each of `profile`'s open quests points at in `state`, by quest id, measured from the
## player in `slot`; a quest with nothing to point at here isn't listed. A step with choices (#573)
## points at each of them that's here, by the quest's id, a slash and the choice's index. `here` is
## the blueprint name of the instance `state` is (#769), or "" when it isn't known: a step that
## counts in another instance, or in one when it isn't known which this is, points at the exits
## leading there.
static func targets_of(
	state: GameState,
	profile: Profile,
	slot: int,
	here: String = "",
) -> Dictionary[String, Vector2i]:
	var targets: Dictionary[String, Vector2i] = {}
	var player: Entity = state.player(slot)
	if player == null:
		return targets
	var steps: Dictionary[String, QuestStep] = profile.open_steps()
	for id: String in steps:
		var triggers: Array[QuestStep] = steps[id].triggers()
		for index: int in triggers.size():
			var candidates: Array[Vector2i] = _candidates(state, triggers[index], here)
			var key: String = id if steps[id].choices.is_empty() else "%s/%d" % [id, index]
			if not candidates.is_empty():
				targets[key] = _nearest(candidates, player.tile)
	return targets


## The tiles `step` could be met at in `state`: wild monsters of its species, or its quest target
## (#625), that aren't hiding, in id order, the closed chests, the tiles of its place, in the
## legend's order, the tiles of
## its piece, or the exits leading to its instance, also when it counts there and `state` is
## another instance, `here`.
static func _candidates(state: GameState, step: QuestStep, here: String) -> Array[Vector2i]:
	var elsewhere: bool = not step.instance.is_empty() and step.instance != here
	if step.enters_instance() or elsewhere:
		return _exits_to(state, step.instance)
	if step.condition == "entered":
		return _piece_tiles(state, step.piece)
	var tiles: Array[Vector2i] = []
	if step.condition == "reached":
		for trigger: TileTrigger in state.region.triggers:
			if trigger.action == TileTrigger.REACH and trigger.place == step.place:
				tiles.append(trigger.tile)
		return tiles
	if step.condition == "opened":
		var chests: ChestFeature = state.feature(Features.CHESTS) as ChestFeature
		if chests != null:
			tiles.assign(chests.chests)
		return tiles
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	if wild == null or step.condition != "dominated":
		return tiles
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	var ids: Array[int] = wild.monsters.duplicate()
	ids.sort()
	for entity_id: int in ids:
		var entity: Entity = state.entity(entity_id)
		var hidden: bool = hiding != null and hiding.is_hidden(entity_id)
		var target: String = WildSpot.target_in(wild.marks, entity_id)
		var fits: bool = step.quarry.fits(wild.species_of(entity_id), target)
		if entity != null and fits and not hidden:
			tiles.append(entity.tile)
	return tiles


## The tiles of the exits in `state` leading to the instance `instance_name`.
static func _exits_to(state: GameState, instance_name: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for i: int in state.region.exits.size():
		if state.region.exit_blueprints[i] == instance_name:
			tiles.append(Vector2i(state.region.exits[i].x, state.region.exits[i].y))
	return tiles


## The tiles of the region piece `piece` in `state`.
static func _piece_tiles(state: GameState, piece: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in state.region.piece_of:
		if state.region.piece_of[tile] == piece:
			tiles.append(tile)
	return tiles


## The tile of `tiles` nearest to `from`; the first one on a tie.
static func _nearest(tiles: Array[Vector2i], from: Vector2i) -> Vector2i:
	var best: Vector2i = tiles[0]
	for tile: Vector2i in tiles:
		if Hex.distance(tile, from) < Hex.distance(best, from):
			best = tile
	return best


## Where an arrow over `tile` floats, before bobbing.
func _over(tile: Vector2i) -> Vector3:
	return HexLayout.to_world(tile) + Vector3(0.0, HexGrid.TILE_HEIGHT + HEIGHT, 0.0)


## A new arrow at `at`, growing in.
func _add_arrow(at: Vector3) -> Node3D:
	if _fill == null:
		_fill = _triangle(HALF_WIDTH, LENGTH, COLOR, InkOutline.TEXT_PRIORITY)
		var widen: float = INK_WIDTH * 2.0
		_ink = _triangle(HALF_WIDTH + widen, LENGTH + widen, Toon.INK, InkOutline.TEXT_PRIORITY - 1)
	var arrow: Node3D = Node3D.new()
	arrow.add_child(_part(_ink))
	arrow.add_child(_part(_fill))
	arrow.position = at
	arrow.scale = Vector3.ONE * 0.01
	add_child(arrow)
	var _grow: PropertyTweener = arrow.create_tween().set_trans(Tween.TRANS_SINE).tween_property(
		arrow,
		"scale",
		Vector3.ONE,
		EASE_SECONDS,
	)
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
