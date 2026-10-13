@tool
class_name PlayerView
extends HexPiece
## Draws the player from the simulation's state: on its tile, or between tiles while a move is
## under way, interpolated by tick and by how far real time is into the next tick, so the walk
## glides at a constant speed. It only reads the state.

@export var driver: GameDriver


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		show_state()


## Places the piece from the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	var state: GameState = driver.state
	tile = state.player_tile
	if state.is_moving():
		var whole_ticks: int = Simulation.MOVE_TICKS - state.move_ticks_left
		var ticks_done: float = whole_ticks + driver.tick_fraction()
		var done: float = clampf(ticks_done / Simulation.MOVE_TICKS, 0.0, 1.0)
		position = position_on(state.move_from).lerp(tile_position(), done)
