@tool
class_name PlayerView
extends HexPiece
## Draws the player in `slot` from the simulation's state: on its tile, or between tiles while a
## move is under way, interpolated by tick and by how far real time is into the next tick, so the
## walk glides at a constant speed. Its character model (#79) idles while standing, runs while
## moving and turns smoothly to face where it goes. Players walk through each other (#31), so
## several can stand on one tile: then each stands at its own spot inside it, by slot, easing there
## and back rather than snapping (#151). It only reads the state; the spot is the view's alone.

## How fast the character turns toward where it walks, in radians per second: quick enough to
## follow a zigzag, never a snap.
const TURN_SPEED: float = 10.0
const IDLE: StringName = &"Idle"
const MOVE: StringName = &"Running_A"
## Parts of the placeholder model the player doesn't carry: its weapons.
const HIDDEN_PARTS: Array[String] = [
	"Knife",
	"Knife_Offhand",
	"1H_Crossbow",
	"2H_Crossbow",
	"Throwable",
]
## Each slot's spot inside a tile it shares with other players: the corners of a small square,
## in world units from the tile's center.
const SPOTS: Array[Vector3] = [
	Vector3(-0.3, 0.0, -0.3),
	Vector3(0.3, 0.0, -0.3),
	Vector3(-0.3, 0.0, 0.3),
	Vector3(0.3, 0.0, 0.3),
]
## How fast a player eases to its spot and back to the center, in world units per second.
const SPOT_SPEED: float = 1.2

@export var driver: GameDriver
@export_range(0, GameState.MAX_PLAYERS - 1) var slot: int = 0
## The character model, a child of this piece: it turns and animates; the piece moves.
@export var model: Node3D

## The yaw the character turns toward, in radians: where it last walked.
var facing: float = 0.0
## Where the player stands inside its tile, from the center: easing toward its slot's spot while
## it shares the tile, back to the center while it doesn't.
var spot: Vector3 = Vector3.ZERO
var _animations: AnimationPlayer


func _ready() -> void:
	super()
	if model == null:
		return
	# Only in the game: in the editor, the copies would be saved into the scene.
	if not Engine.is_editor_hint():
		Toon.apply_to_model(model)
	for part: String in HIDDEN_PARTS:
		var node: Node3D = model.find_child(part) as Node3D
		if node != null:
			node.visible = false
	# The clips loop by the model's import settings (Rogue.glb.import), not by changing the
	# imported animations here, which every instance shares.
	_animations = model.find_child("AnimationPlayer") as AnimationPlayer


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		ease_spot(delta)
		show_state()
		turn(delta)


## Places the piece from the current state and picks the clip. Called every frame; tests call it
## after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	var player: Entity = driver.state.player(slot)
	# A slot nobody plays in shows nothing.
	visible = player != null
	if player == null:
		return
	tile = player.tile
	# Set explicitly, not left to the tile setter: the spot is added to it once below.
	position = tile_position()
	# Without movement in the instance, the player simply stands on its tile.
	var movement: MovementFeature = driver.state.feature(Features.MOVEMENT) as MovementFeature
	var walk: Walk = movement.walk(player.id) if movement != null else null
	var moving: bool = walk != null and walk.is_moving()
	if moving:
		var whole_ticks: int = MovementFeature.MOVE_TICKS - walk.ticks_left
		var ticks_done: float = whole_ticks + driver.tick_fraction()
		var done: float = clampf(ticks_done / MovementFeature.MOVE_TICKS, 0.0, 1.0)
		position = position_on(walk.from).lerp(tile_position(), done)
		# The yaw that turns the model's front (+Z, Vector3.MODEL_FRONT, as glTF models face)
		# toward the walk.
		var heading: Vector3 = tile_position() - position_on(walk.from)
		facing = atan2(heading.x, heading.z)
	position += spot
	_play(MOVE if moving else IDLE)


## The clip the character is playing, or "" without a model.
func current_clip() -> StringName:
	return StringName(_animations.current_animation) if _animations != null else &""


## Moves the player toward its spot by at most SPOT_SPEED per second. Called every frame; tests
## call it with their own step.
func ease_spot(delta: float) -> void:
	if driver == null or driver.state == null:
		return
	var player: Entity = driver.state.player(slot)
	var target: Vector3 = Vector3.ZERO
	if player != null and _shares_tile(player):
		target = SPOTS[slot]
	spot = spot.move_toward(target, SPOT_SPEED * delta)


## Whether another player stands on (or is walking onto) `player`'s tile.
func _shares_tile(player: Entity) -> bool:
	for other_slot: int in GameState.MAX_PLAYERS:
		var other: Entity = driver.state.player(other_slot)
		if other_slot != slot and other != null and other.tile == player.tile:
			return true
	return false


## Turns the character toward `facing` by at most TURN_SPEED per second. Called every frame;
## tests call it with their own step.
func turn(delta: float) -> void:
	if model != null:
		model.rotation.y = rotate_toward(model.rotation.y, facing, TURN_SPEED * delta)


func _play(clip: StringName) -> void:
	# A model without the clip simply doesn't animate.
	if _animations == null or not _animations.has_animation(clip):
		return
	if _animations.current_animation != clip:
		_animations.play(clip, 0.15)
