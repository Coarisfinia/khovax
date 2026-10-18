class_name LocalInput
extends Node
## The local player's commands. Every device feeds the same movement actions (keys, the touch
## stick, later controllers), and this turns them into one command per tick for the player in
## `slot`. A press of the special attack (#410) fires it in the next command: one press fires once,
## and a press between two ticks isn't lost. place_totem places their totem (#423) while it's held,
## and a tap between two ticks isn't lost either. focus_next and focus_previous (Q and R, or the
## shoulder buttons) step the focus through the wild monsters near the player (#436).

## The player slot this machine's player controls.
@export_range(0, GameState.MAX_PLAYERS - 1) var slot: int = 0

## Whether the game hears no input, as while the menu is open over it (#362): the player stands.
var blocked: bool = false
## Whether the special attack was pressed since the last command.
var _special_pressed: bool = false
## Whether place_totem was pressed since the last command.
var _totem_tapped: bool = false
## The wild monster the player focuses (#436), by entity id, or Command.NO_FOCUS; the special
## attack strikes it. Views read it to mark it.
var focus: int = Command.NO_FOCUS
## How far focus_next (+1) and focus_previous (-1) stepped the focus since the last command.
var _focus_steps: int = 0


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("special_attack"):
		_special_pressed = true
	if Input.is_action_just_pressed("place_totem"):
		_totem_tapped = true
	if Input.is_action_just_pressed("focus_next"):
		_focus_steps += 1
	if Input.is_action_just_pressed("focus_previous"):
		_focus_steps -= 1


func command(state: GameState) -> Command:
	var fires: bool = _special_pressed
	_special_pressed = false
	var placing: bool = _totem_tapped or Input.is_action_pressed("place_totem")
	_totem_tapped = false
	if blocked:
		# Presses while the game hears no input don't move the focus afterwards.
		_focus_steps = 0
		return Command.new()
	var vector: Vector2 = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	var player: Entity = state.player(slot)
	# Only the tie between two directions depends on the tile; without a player nothing walks.
	var tile: Vector2i = player.tile if player != null else Vector2i.ZERO
	focus = FocusChoice.stepped(state, tile, focus, _focus_steps)
	_focus_steps = 0
	return Command.new(
		HexInput.direction_toward(vector, tile),
		fires,
		Command.PLACE_TOTEM if placing else Command.NO_TOTEM,
		focus,
	)
