class_name LocalInput
extends SessionInput
## The local player's commands. Every device feeds the same movement actions (keys, the touch
## stick, a controller), and this turns them into one command per tick for the player in
## `slot`. A press of the special attack (#410) fires it in the next command: one press fires once,
## and a press between two ticks isn't lost. place_totem places their totem (#423) while it's held,
## and a tap between two ticks isn't lost either. focus_next and focus_previous (Q and R, or the
## shoulder buttons) step the focus through the wild monsters near the player (#436). swap_1 to
## swap_3 (keys 1 to 3, the d-pad's left, up and right, or a tap on the roster, RosterHud) make the
## monster at that place in the carried order the companion (#540): one press swaps once.
## revive_monster (V, or the d-pad's down) uses a revive item (#656) on the fainted monster the
## player picks (#780, ItemPick), only while this player's profile holds one: the items are in the
## profile, outside the simulation, which posts the use as a request to its outbox (#818,
## revive_chosen) that goes in the next command. drink_tonic (G, or a controller's left trigger)
## drinks a tonic or a draught (#2313) the same way, picked among those the profile holds
## (drink_chosen). While picking either, the player stands. interact (F, or
## a controller's A) harvests the tile the player stands on or next to by hand (#696): one press
## starts it once. A tap or click on a tile (FocusPicker) walks there on the player's own, and
## harvests it on arrival when bare hands can (#1508, TapWalk); the stick or a key stops that walk.
## The left mouse button held on the world walks toward the cursor while it's held (#1567,
## HeldWalk), as a held stick does; the stick or a key steers over it while pressed.

## A revive item is used on the fainted monster `short_id` (#818): the profile spends it and posts
## the request, sent back here (`send`) for the next command.
signal revive_chosen(short_id: String)
## The tonic or draught `brew_id` is drunk (#2313): the profile spends it and posts the request, or
## says why it can't. "" when drink_tonic was pressed with nothing to drink, so that's said too.
signal drink_chosen(brew_id: String)

## What place_totem did since the last command (_totem).
enum TotemPress {
	NONE,
	TAPPED,
	HELD_OVER,
}

## The swap actions, in the carried order's places from 1.
const SWAP_ACTIONS: Array[StringName] = [&"swap_1", &"swap_2", &"swap_3"]
## The actions whose press counts once, in the next command, even when it lifts between two ticks:
## the special attack, respawn (#495: going back to the spawn when down) and interact (#696).
const PRESSED_ONCE: Array[StringName] = [&"special_attack", &"respawn", &"interact"]
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]

## What the requests it sends were acknowledged up to (#942): this machine's player's profile's,
## through its tie (ProfileTie); none without one.
@export var acks: RequestAcks
## Which fainted monsters a revive item may go to (#656): those this machine's player's profile
## holds one for, through the revive items' tie (ReviveTie); none without one.
@export var revive: ReviveOffer
## Which tonics and draughts may be drunk (#2313): those this machine's player's profile holds,
## through the drink's tie (DrinkTie); none without one.
@export var drink: DrinkOffer

## The last frame whose presses are dropped (#1509): the frame after the game last heard no input
## too, since the key or button that closed the menu or a dialog (a controller's A is interact as
## well) still reads as just pressed in the frame it closed.
var _deaf_through: int = -1
## The PRESSED_ONCE actions pressed since the last command.
var _pressed: Dictionary[StringName, bool] = {}
## place_totem since the last command: TAPPED when pressed, or HELD_OVER while it has been held
## since the game last heard no input (#1509): held on over the menu or a dialog, it places nothing
## until it's let go or pressed again.
var _totem: TotemPress = TotemPress.NONE
## How far focus_next (+1) and focus_previous (-1) stepped the focus since the last command.
var _focus_steps: int = 0
## The place in the carried order chosen since the last command (#540), from 1, or Command.NO_SWAP.
var _swap_to: int = Command.NO_SWAP
## The code of the dialog answer chosen since the last command (#635), or Command.NO_ANSWER.
var _answer: int = Command.NO_ANSWER
## The requests from this player's profile's outbox (#771), waiting for the next commands, one
## each.
var _requests: Array[OutboxEntry] = []
## The walk to a tapped or clicked tile (#1508), and the tap the next command walks to.
var tap_walk: TapWalk = TapWalk.new()
## Which fainted monster the next revive item brings back (#780); views read its `picked`.
var revive_pick: ItemPick = ItemPick.new(&"revive_monster")
## Which tonic or draught the next drink is (#2313); views read its `picked`.
var drink_pick: ItemPick = ItemPick.new(&"drink_tonic")
## The walk toward the cursor while the left mouse button is held on the world (#1567).
var held_walk: HeldWalk = HeldWalk.new()


func _process(_delta: float) -> void:
	var frame: int = Engine.get_process_frames()
	if blocked or in_dialog:
		_deaf_through = frame + 1
	if frame <= _deaf_through:
		_drop_presses()
	else:
		_hear()


## Keeps the presses of this frame for the next command.
func _hear() -> void:
	for action: StringName in PRESSED_ONCE:
		if Input.is_action_just_pressed(action):
			_pressed[action] = true
	# A key tapped between two commands stops a walk to a tapped tile too, though the next command
	# sees it let go. A tap queued this frame stays: the touch stick presses these actions for a
	# tap's slight wiggle too.
	for action: StringName in MOVE_ACTIONS:
		if Input.is_action_just_pressed(action):
			tap_walk.halt()
	_hear_totem()
	if Input.is_action_just_pressed("focus_next"):
		_focus_steps += 1
	if Input.is_action_just_pressed("focus_previous"):
		_focus_steps -= 1
	for place: int in SWAP_ACTIONS.size():
		if Input.is_action_just_pressed(SWAP_ACTIONS[place]):
			_swap_to = place + 1
	# One pick at a time: the arrows and ui_accept move and end only the one open, and of two
	# presses before a command only the first pick's counts.
	if drink_pick.picked.is_empty() and not drink_pick.was_pressed():
		revive_pick.hear()
	if revive_pick.picked.is_empty() and not revive_pick.was_pressed():
		drink_pick.hear()


## Keeps a tap of place_totem for the next command, and ends a hold kept over from while the game
## heard no input once it's let go or pressed anew.
func _hear_totem() -> void:
	if Input.is_action_just_pressed("place_totem"):
		_totem = TotemPress.TAPPED
	elif _totem == TotemPress.HELD_OVER and not Input.is_action_pressed("place_totem"):
		_totem = TotemPress.NONE


## Drops every press heard since the last command (#1509): while the game hears no input, the
## driver may be paused (the menu's pause), and a press kept until the menu closes would fire then.
func _drop_presses() -> void:
	_pressed.clear()
	_totem = TotemPress.HELD_OVER
	_focus_steps = 0
	_swap_to = Command.NO_SWAP
	_drop_picks()
	tap_walk.stop()
	held_walk.let_go()


## Uses what the revive item's and the drink's picks chose for the command for `state`; returns
## whether the player stands for a pick: one is open, or was until now, since the A that ends it
## is interact as well.
func _settle_picks(state: GameState) -> bool:
	var picking: bool = not revive_pick.picked.is_empty() or not drink_pick.picked.is_empty()
	_revive(state)
	_drink(state)
	return picking or not revive_pick.picked.is_empty() or not drink_pick.picked.is_empty()


## Ends both picks, the revive item's and the drink's, forgetting their presses.
func _drop_picks() -> void:
	revive_pick.drop()
	drink_pick.drop()


## Walks to `tile` on the player's own from the next command, as a tap or click on it does (#1508).
## A tap while the game hears no input (the menu or a dialog is open, #1509) walks nowhere.
func tap_tile(tile: Vector2i) -> void:
	if hears():
		tap_walk.tap(tile)


## Whether the game hears input now: not while the menu or a dialog is open, nor in the frame after
## one closed (#1509). Taps and clicks on the world (FocusPicker) ask it too.
func hears() -> bool:
	return not (blocked or in_dialog) and Engine.get_process_frames() > _deaf_through


## Swaps to the monster at `place` in the carried order, from 1, in the next command, as a tap on
## the roster does.
func choose_swap(place: int) -> void:
	_swap_to = place


## Uses a revive item on the fainted monster `short_id` in the next command, as a tap on its roster
## square does (#780).
func choose_revive(short_id: String) -> void:
	revive_pick.tap(short_id)


## Drinks the tonic or draught `brew_id` in the next command, as a tap on it in the pick's list
## does (#2313).
func choose_drink(brew_id: String) -> void:
	drink_pick.tap(brew_id)


## Sends the answer with the code `code` (DialogFeature.code) in the next command, as choosing it on
## the dialog screen does (#635).
func choose_answer(code: int) -> void:
	_answer = code


## Sends the request `request` from the profile's outbox (#771) in the next command that carries
## none yet, like the hand-over of a finished territory quest (#638).
func send(request: OutboxEntry) -> void:
	_requests.append(request)


func command(state: GameState) -> Command:
	# The driver may ask before this frame's _process ran: what came in as the menu or a dialog
	# closed (a roster tap during the dialog's fade) is dropped here too.
	if Engine.get_process_frames() <= _deaf_through:
		_drop_presses()
	var fires: bool = _pressed.has(&"special_attack")
	var placing: bool = _placing()
	var gives_up: bool = _pressed.has(&"respawn")
	var interacting: bool = _pressed.has(&"interact")
	_pressed.clear()
	var swap: int = _swap_to
	_swap_to = Command.NO_SWAP
	var answering: int = _answer
	_answer = Command.NO_ANSWER
	if blocked or in_dialog:
		# Presses while the game hears no input don't move the focus or use an item afterwards.
		_focus_steps = 0
		_drop_picks()
		tap_walk.stop()
		return _standing(answering)
	# While picking a fainted monster to revive (#780) or a brew to drink (#2313), the arrows move
	# the pick, not the player, and other presses are dropped.
	if _settle_picks(state):
		_focus_steps = 0
		tap_walk.stop()
		return _standing(answering)
	var player: Entity = state.player(slot)
	# Only the tie between two directions depends on the tile; without a player nothing walks.
	var tile: Vector2i = player.tile if player != null else Vector2i.ZERO
	focus = FocusChoice.stepped(state, tile, focus, _focus_steps)
	_focus_steps = 0
	var given: Command = Command.new(
		HexInput.direction_toward(_steering(tile), tile),
		fires,
		Command.PLACE_TOTEM if placing else Command.NO_TOTEM,
		focus,
		gives_up,
	)
	given.swap = swap
	given.answer = answering
	given.interact = interacting
	if player != null:
		tap_walk.steer(given, state, tile)
	else:
		tap_walk.stop()
	_send_next(given)
	return given


## The screen-space steering of the player on `tile`: the stick's or the keys', also while two
## opposite ones pressed together cancel out, else the held left mouse button's (#1567). The vector
## comes first: a slight diagonal stick passes get_vector's round dead zone while neither of its
## actions counts as pressed.
func _steering(tile: Vector2i) -> Vector2:
	var vector: Vector2 = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	if not vector.is_zero_approx():
		return vector
	for action: StringName in MOVE_ACTIONS:
		if Input.is_action_pressed(action):
			return vector
	return held_walk.steering(tile)


## Whether the next command places the totem: tapped since the last one, or held, unless held on
## from while the game heard no input. A tap counts once.
func _placing() -> bool:
	# A fresh press ends a hold kept over even when the driver asks before this frame's _process,
	# which would hear it only after this command.
	var fresh: bool = Input.is_action_just_pressed("place_totem")
	if fresh and _totem == TotemPress.HELD_OVER and Engine.get_process_frames() > _deaf_through:
		_totem = TotemPress.NONE
	var held: bool = Input.is_action_pressed("place_totem") and _totem != TotemPress.HELD_OVER
	var tapped: bool = _totem == TotemPress.TAPPED
	if tapped:
		_totem = TotemPress.NONE
	return tapped or held


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
		carrier.acknowledged = acks.confirmed(next.kind) if acks != null else Command.NO_REQUEST


## Uses a revive item on the fainted monster the player picked (#780), only while this player's
## profile holds one (#656, `revive`): the revive items' tie (ReviveTie) spends it and posts it to
## the profile's outbox, which sends it in the next command.
func _revive(state: GameState) -> void:
	var offered: PackedStringArray = PackedStringArray()
	if revive != null and state.player(slot) != null:
		offered = revive.offered(state, slot)
	var reviving: String = revive_pick.chosen(offered, not offered.is_empty())
	if not reviving.is_empty():
		revive_chosen.emit(reviving)


## Drinks the tonic or draught the player picked (#2313), from those this player's profile holds:
## the drink's tie (DrinkTie) spends it and posts it to the profile's outbox, or says why it can't.
## A press with none held is told to it as "".
func _drink(state: GameState) -> void:
	var offered: PackedStringArray = PackedStringArray()
	if drink != null and state.player(slot) != null:
		offered = drink.offered(state, slot)
	var pressed: bool = drink_pick.was_pressed()
	var drinking: String = drink_pick.chosen(offered, not offered.is_empty())
	if not drinking.is_empty():
		drink_chosen.emit(drinking)
	elif pressed and offered.is_empty() and drink != null:
		drink_chosen.emit("")
