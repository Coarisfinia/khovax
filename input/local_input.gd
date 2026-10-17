class_name LocalInput
extends Node
## The local player's commands. Every device feeds the same movement actions (keys, the touch
## stick, later controllers), and this turns them into one command per tick for the player in
## `slot`. A press of the special attack (#410) fires it in the next command: one press fires once,
## and a press between two ticks isn't lost. place_totem places their totem (#423) while it's held,
## and a tap between two ticks isn't lost either.

## The player slot this machine's player controls.
@export_range(0, GameState.MAX_PLAYERS - 1) var slot: int = 0

## Whether the game hears no input, as while the menu is open over it (#362): the player stands.
var blocked: bool = false
## Whether the special attack was pressed since the last command.
var _special_pressed: bool = false
## Whether place_totem was pressed since the last command.
var _totem_tapped: bool = false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("special_attack"):
		_special_pressed = true
	if Input.is_action_just_pressed("place_totem"):
		_totem_tapped = true


func command(state: GameState) -> Command:
	var fires: bool = _special_pressed
	_special_pressed = false
	var placing: bool = _totem_tapped or Input.is_action_pressed("place_totem")
	_totem_tapped = false
	if blocked:
		return Command.new()
	var vector: Vector2 = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	var player: Entity = state.player(slot)
	# Only the tie between two directions depends on the tile; without a player nothing walks.
	var tile: Vector2i = player.tile if player != null else Vector2i.ZERO
	return Command.new(
		HexInput.direction_toward(vector, tile),
		fires,
		Command.PLACE_TOTEM if placing else Command.NO_TOTEM,
	)
