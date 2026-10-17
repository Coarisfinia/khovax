class_name LocalInput
extends Node
## The local player's commands. Every device feeds the same movement actions (keys, the touch
## stick, later controllers), and this turns them into one command per tick for the player in
## `slot`. A press of the special attack (#410) fires it in the next command: one press fires once,
## and a press between two ticks isn't lost.

## The player slot this machine's player controls.
@export_range(0, GameState.MAX_PLAYERS - 1) var slot: int = 0

## Whether the game hears no input, as while the menu is open over it (#362): the player stands.
var blocked: bool = false
## Whether the special attack was pressed since the last command.
var _special_pressed: bool = false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("special_attack"):
		_special_pressed = true


func command(state: GameState) -> Command:
	var fires: bool = _special_pressed
	_special_pressed = false
	if blocked:
		return Command.new()
	var vector: Vector2 = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	var player: Entity = state.player(slot)
	# Only the tie between two directions depends on the tile; without a player nothing walks.
	var tile: Vector2i = player.tile if player != null else Vector2i.ZERO
	return Command.new(HexInput.direction_toward(vector, tile), fires)
