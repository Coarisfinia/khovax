class_name LocalInput
extends Node
## The local player's commands. Every device feeds the same movement actions (keys, the touch
## stick, a controller), and this turns them into one command per tick for the player in
## `slot`. A press of the special attack (#410) fires it in the next command: one press fires once,
## and a press between two ticks isn't lost. place_totem places their totem (#423) while it's held,
## and a tap between two ticks isn't lost either. focus_next and focus_previous (Q and R, or the
## shoulder buttons) step the focus through the wild monsters near the player (#436). swap_1 to
## swap_3 (keys 1 to 3, the d-pad's left, up and right, or a tap on the roster, RosterHud) make the
## monster at that place in the carried order the companion (#540): one press swaps once.
## revive_monster (V, or the d-pad's down) uses a revive item (#656) on the fainted monster the
## player picks (#780, RevivePick), only while this player's profile holds one: the items are in the
## profile, outside the simulation, which posts the use as a request to its outbox (#818,
## revive_chosen) that goes in the next command. While picking, the player stands. interact (F, or
## a controller's A) harvests the tile the player stands on or next to by hand (#696): one press
## starts it once.

## A revive item is used on the fainted monster `short_id` (#818): the profile spends it and posts
## the request, sent back here (`send`) for the next command.
signal revive_chosen(short_id: String)

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
## Whether interact was pressed since the last command (#696).
var _interact_pressed: bool = false
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
## The requests from this player's profile's outbox (#771), waiting for the next commands, one
## each.
var _requests: Array[OutboxEntry] = []
## Which fainted monster the next revive item brings back (#780); views read its `picked`.
var revive_pick: RevivePick = RevivePick.new()


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
	if Input.is_action_just_pressed("interact"):
		_interact_pressed = true
	for place: int in SWAP_ACTIONS.size():
		if Input.is_action_just_pressed(SWAP_ACTIONS[place]):
			_swap_to = place + 1
	revive_pick.hear()


## Swaps to the monster at `place` in the carried order, from 1, in the next command, as a tap on
## the roster does.
func choose_swap(place: int) -> void:
	_swap_to = place


## Uses a revive item on the fainted monster `short_id` in the next command, as a tap on its roster
## square does (#780).
func choose_revive(short_id: String) -> void:
	revive_pick.tap(short_id)


## Sends the answer with the code `code` (DialogFeature.code) in the next command, as choosing it on
## the dialog screen does (#635).
func choose_answer(code: int) -> void:
	_answer = code


## Sends the request `request` from the profile's outbox (#771) in the next command that carries
## none yet, like the hand-over of a finished territory quest (#638).
func send(request: OutboxEntry) -> void:
	_requests.append(request)


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
	var interacting: bool = _interact_pressed
	_interact_pressed = false
	if blocked or in_dialog:
		# Presses while the game hears no input don't move the focus or use an item afterwards.
		_focus_steps = 0
		revive_pick.drop()
		return _standing(answering)
	_revive(state)
	# While picking a fainted monster to revive (#780), the arrows move the pick, not the player,
	# and other presses are dropped.
	if not revive_pick.picked.is_empty():
		_focus_steps = 0
		return _standing(answering)
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
	given.interact = interacting
	_send_next(given)
	return given


## A command that stands still, with the dialog `answering` chosen: the dialog screen's answers are
## the one input a dialog lets through.
func _standing(answering: int) -> Command:
	var standing: Command = Command.new()
	standing.answer = answering
	_send_next(standing)
	return standing


## Puts the next request waiting to be sent into `carrier`, taken off the queue, if there is one,
## with the code up to which the profile saw its requests of that kind acknowledged (#942, #968).
func _send_next(carrier: Command) -> void:
	if not _requests.is_empty():
		var next: OutboxEntry = _requests.pop_front()
		next.fill(carrier)
		carrier.acknowledged = holder.confirmed(next.kind) if holder != null else Command.NO_REQUEST


## Uses a revive item on the fainted monster the player picked (#780), only while this player's
## profile holds one (#656): whoever ties their profile to the session (ProfileTie) spends it and
## posts it to the profile's outbox, which sends it in the next command.
func _revive(state: GameState) -> void:
	var holds: bool = ReviveItem.held(holder) > 0 and state.player(slot) != null
	# One an item is already on its way to (#818) isn't offered again.
	var fainted: PackedStringArray = PackedStringArray()
	var on_the_way: PackedStringArray = ReviveItem.on_the_way(holder)
	for short_id: String in ReviveItemFeature.fainted(state, slot):
		if not on_the_way.has(short_id):
			var _added: bool = fainted.append(short_id)
	var reviving: String = revive_pick.chosen(fainted, holds)
	if not reviving.is_empty():
		revive_chosen.emit(reviving)
