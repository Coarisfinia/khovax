class_name CompanionView
extends Node3D
## The companions' look (#338): a placeholder figure for each, the wild monsters' placeholder made
## smaller, standing in a smaller circle in its player's personal color with its player's slot marks
## (PlayerCircle, #233), so whose companion it is shows by a shape too, never by color alone (#68).
## It glides from tile to tile as it walks, like the players, turning smoothly toward where it goes.
## It only reads the state.

## How big the figure is next to a wild monster's, and its circle next to a player's.
const FIGURE_SCALE: float = 0.6
const CIRCLE_SCALE: float = 0.75
## How fast the figure turns toward where it walks, in radians per second.
const TURN_SPEED: float = 10.0

@export var driver: GameDriver

## The figure shown for each companion, by entity id: a piece on the tile holding the model, then
## the circle.
var figures: Dictionary[int, HexPiece] = {}
## The yaw each figure turns toward, by entity id: where it last walked.
var _facing: Dictionary[int, float] = {}
## The instance the figures belong to: another instance drops them at once (#189).
var _shown: GameState


func _process(delta: float) -> void:
	show_state()
	for companion_id: int in figures:
		var model: Node3D = figures[companion_id].get_child(0) as Node3D
		var yaw: float = _facing.get(companion_id, 0.0)
		model.rotation.y = rotate_toward(model.rotation.y, yaw, TURN_SPEED * delta)


## Matches the figures to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		HexPiece.free_all(figures)
		_facing.clear()
		_shown = driver.state
	var feature: CompanionFeature = driver.state.feature(Features.COMPANIONS) as CompanionFeature
	var shown: Array[int] = feature.companions() if feature != null else []
	for companion_id: int in figures.keys():
		if not shown.has(companion_id):
			figures[companion_id].queue_free()
			var _dropped: bool = figures.erase(companion_id)
			_dropped = _facing.erase(companion_id)
	for companion_id: int in shown:
		var slot: int = feature.owners[companion_id]
		if not figures.has(companion_id):
			figures[companion_id] = _add_figure(slot)
		# Every frame, so a color the player chooses in the menu shows at once (#391).
		circle_of(companion_id).paint(PersonalColor.shown(driver, slot))
		_place(companion_id)


## The circle under the companion's figure, or null when it has none shown.
func circle_of(companion_id: int) -> PlayerCircle:
	var figure: HexPiece = figures.get(companion_id)
	return figure.get_child(1) as PlayerCircle if figure != null else null


## Puts the companion's figure on its tile, or between tiles while it walks, by tick and by how far
## real time is into the next tick.
func _place(companion_id: int) -> void:
	var figure: HexPiece = figures[companion_id]
	figure.tile = driver.state.entity(companion_id).tile
	var movement: MovementFeature = driver.state.feature(Features.MOVEMENT) as MovementFeature
	var walk: Walk = movement.walk(companion_id) if movement != null else null
	if walk == null or not walk.is_moving():
		return
	var ticks_done: float = MovementFeature.MOVE_TICKS - walk.ticks_left + driver.tick_fraction()
	var from: Vector3 = figure.position_on(walk.from)
	figure.position = from.lerp(
		figure.tile_position(),
		clampf(ticks_done / MovementFeature.MOVE_TICKS, 0.0, 1.0),
	)
	var heading: Vector3 = figure.tile_position() - from
	_facing[companion_id] = atan2(heading.x, heading.z)


## A new figure for the companion of the player in `slot`, in the comic look and idling, in a
## circle of that player's marks (show_state paints it in their color).
func _add_figure(slot: int) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = WildMonsterView.placeholder_model()
	model.scale = Vector3.ONE * FIGURE_SCALE
	piece.add_child(model)
	var circle: PlayerCircle = PlayerCircle.new(slot)
	circle.scale = Vector3.ONE * CIRCLE_SCALE
	piece.add_child(circle)
	add_child(piece)
	WildMonsterView.idle(model)
	return piece
