class_name LocalInput
extends Node
## The local player's commands. Every device feeds the same movement actions (keys, the touch
## stick, later controllers), and this turns them into one command per tick for the player in
## `slot`. A press of the special attack (#410) fires it in the next command: one press fires once,
## and a press between two ticks isn't lost. place_totem places their totem (#423) while it's held,
## and a tap between two ticks isn't lost either. focus_next and focus_previous (Q and R, or the
## shoulder buttons) step the focus through the wild monsters near the player (#436). swap_1 to
## swap_3 (keys 1 to 3, the d-pad's left, up and right, or a tap on the roster, RosterHud) make the
## monster at that place in the carried order the companion (#540): one press swaps once.
## revive_monster (V, or the d-pad's down) uses a revive item (#656) in the next command, only while
## this player's profile holds one: the items are in the profile, outside the simulation.

## The swap actions, in the carried order's places from 1.
const SWAP_ACTIONS: Array[StringName] = [&"swap_1", &"swap_2", &"swap_3"]

## The player slot this machine's player controls.
@export_range(0, GameState.MAX_PLAYERS - 1) var slot: int = 0
## This machine's player's profile, which holds their revive items (#656).
@export var holder: ProfileHolder

## Whether the game hears no input, as while the menu is open over it (#362): the player stands.
var blocked: bool = false
## Whether a dialog is open on screen (#635): the player stands, as while blocked, and the d-pad,
## the stick and A choose on the dialog screen instead. Its own flag, so the menu opening and
## closing over a dialog doesn't let the player walk off.
var in_dialog: bool = false
## Whether the special attack was pressed since the last command.
var _special_pressed: bool = false
## Whether place_totem was pressed since the last command.
var _totem_tapped: bool = false
## The wild monster the player focuses (#436), by entity id, or Command.NO_FOCUS; the special
## attack strikes it. Views read it to mark it.
var focus: int = Command.NO_FOCUS
## How far focus_next (+1) and focus_previous (-1) stepped the focus since the last command.
var _focus_steps: int = 0
## Whether respawn was pressed since the last command (#495): going back to the spawn when down.
var _respawn_pressed: bool = false
## The place in the carried order chosen since the last command (#540), from 1, or Command.NO_SWAP.
var _swap_to: int = Command.NO_SWAP
## The code of the dialog answer chosen since the last command (#635), or Command.NO_ANSWER.
var _answer: int = Command.NO_ANSWER
## The codes of the territories this player's finished territory quests hand over (#638), waiting
## for the next commands, one each.
var _handing: Array[int] = []
## Whether revive_monster was pressed since the last command (#656).
var _revive_pressed: bool = false


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("special_attack"):
		_special_pressed = true
	if Input.is_action_just_pressed("place_totem"):
		_totem_tapped = true
	if Input.is_action_just_pressed("focus_next"):
		_focus_steps += 1
	if Input.is_action_just_pressed("focus_previous"):
		_focus_steps -= 1
	if Input.is_action_just_pressed("respawn"):
		_respawn_pressed = true
	for place: int in SWAP_ACTIONS.size():
		if Input.is_action_just_pressed(SWAP_ACTIONS[place]):
			_swap_to = place + 1
	if Input.is_action_just_pressed("revive_monster"):
		_revive_pressed = true


## Swaps to the monster at `place` in the carried order, from 1, in the next command, as a tap on
## the roster does.
func choose_swap(place: int) -> void:
	_swap_to = place


## Sends the answer with the code `code` (DialogFeature.code) in the next command, as choosing it on
## the dialog screen does (#635).
func choose_answer(code: int) -> void:
	_answer = code


## Hands the territory with the code `code` (Territory.code) over in the next command that hands
## none over yet, as finishing its territory quest does (#638).
func hand_over(code: int) -> void:
	_handing.append(code)


func command(state: GameState) -> Command:
	var fires: bool = _special_pressed
	_special_pressed = false
	var placing: bool = _totem_tapped or Input.is_action_pressed("place_totem")
	_totem_tapped = false
	var gives_up: bool = _respawn_pressed
	_respawn_pressed = false
	var swap: int = _swap_to
	_swap_to = Command.NO_SWAP
	var answering: int = _answer
	_answer = Command.NO_ANSWER
	if blocked or in_dialog:
		# Presses while the game hears no input don't move the focus or use an item afterwards.
		_focus_steps = 0
		_revive_pressed = false
		var standing: Command = Command.new()
		# The dialog screen's answers are the one input a dialog lets through.
		standing.answer = answering
		standing.hand_over = _next_hand_over()
		return standing
	var vector: Vector2 = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	var player: Entity = state.player(slot)
	# Only the tie between two directions depends on the tile; without a player nothing walks.
	var tile: Vector2i = player.tile if player != null else Vector2i.ZERO
	focus = FocusChoice.stepped(state, tile, focus, _focus_steps)
	_focus_steps = 0
	var given: Command = Command.new(
		HexInput.direction_toward(vector, tile),
		fires,
		Command.PLACE_TOTEM if placing else Command.NO_TOTEM,
		focus,
		gives_up,
	)
	given.swap = swap
	given.answer = answering
	given.hand_over = _next_hand_over()
	given.revive = _reviving()
	return given


## The code of the next territory waiting to be handed over, taken off the queue, or
## Command.NO_HAND_OVER.
func _next_hand_over() -> int:
	if _handing.is_empty():
		return Command.NO_HAND_OVER
	var code: int = _handing[0]
	_handing.remove_at(0)
	return code


## Whether the next command uses a revive item: one was pressed since the last command, and this
## player's profile holds one (#656).
func _reviving() -> bool:
	var pressed: bool = _revive_pressed
	_revive_pressed = false
	return pressed and ReviveItem.held(holder) > 0
