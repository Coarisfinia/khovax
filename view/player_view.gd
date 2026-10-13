@tool
class_name PlayerView
extends HexPiece
## Draws the player in `slot` from the simulation's state: on its tile, or between tiles while a
## move is under way, interpolated by tick and by how far real time is into the next tick, so the
## walk glides at a constant speed. It only reads the state.

@export var driver: GameDriver
@export_range(0, GameState.MAX_PLAYERS - 1) var slot: int = 0


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		show_state()


## Places the piece from the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	var player: Entity = driver.state.player(slot)
	# A slot nobody plays in shows nothing.
	visible = player != null
	if player == null:
		return
	tile = player.tile
	# Without movement in the instance, the player simply stands on its tile.
	var movement: MovementFeature = driver.state.feature(Features.MOVEMENT) as MovementFeature
	if movement == null:
		return
	var walk: Walk = movement.walk(player.id)
	if walk != null and walk.is_moving():
		var whole_ticks: int = MovementFeature.MOVE_TICKS - walk.ticks_left
		var ticks_done: float = whole_ticks + driver.tick_fraction()
		var done: float = clampf(ticks_done / MovementFeature.MOVE_TICKS, 0.0, 1.0)
		position = position_on(walk.from).lerp(tile_position(), done)
