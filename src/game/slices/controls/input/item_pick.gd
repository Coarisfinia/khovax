class_name ItemPick
extends RefCounted
## Which of several things an item from the profile is used on, or which item is used: the player
## picks (#780). A revive item picks the fainted monster it brings back (`revive_monster`: V, the
## d-pad's down, or the herb button), a drink the tonic or draught drunk (#2313, `drink_tonic`).
## A press of its action uses the only one offered at once; with several offered it picks the
## first, and then the arrows or the d-pad (ui_left/ui_up back, ui_right/ui_down and its action on)
## move the pick between them, ui_accept (Enter, A) uses it and ui_cancel (Escape, B) lets it go. A
## tap on one (`tap`, the roster's fainted square or a listed brew) uses that one at once. The
## player stands while picking (LocalInput). Presses are heard every frame and settled once per
## command, against the state the command is for.

## The InputMap action that starts the pick and moves it on.
var action: StringName = &""
## The id of the one picked, or "" while not picking.
var picked: String = ""
## How many times the action was pressed since the last command.
var _presses: int = 0
## How far the pick moved since the last command: +1 on, -1 back.
var _steps: int = 0
var _confirmed: bool = false
var _cancelled: bool = false
## The id of the one tapped since the last command, or "".
var _tapped: String = ""


func _init(pressed_with: StringName) -> void:
	action = pressed_with


## Hears this frame's presses. While picking, one press moving the pick on counts once, as the
## d-pad's down is both revive_monster and ui_down.
func hear() -> void:
	if picked.is_empty():
		_presses += 1 if Input.is_action_just_pressed(action) else 0
		return
	var on: bool = Input.is_action_just_pressed(action)
	on = on or Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down")
	var back: bool = Input.is_action_just_pressed("ui_left")
	back = back or Input.is_action_just_pressed("ui_up")
	_steps += (1 if on else 0) - (1 if back else 0)
	_confirmed = _confirmed or Input.is_action_just_pressed("ui_accept")
	_cancelled = _cancelled or Input.is_action_just_pressed("ui_cancel")


## Uses the one `id` in the next command, ending any pick, as a tap on it does.
func tap(id: String) -> void:
	_tapped = id
	picked = ""


## Ends any pick and forgets the presses, as while the game hears no input.
func drop() -> void:
	picked = ""
	_presses = 0
	_tapped = ""
	_settled()


## Whether the action was pressed since the last command while not picking: asked before `chosen`,
## which forgets it, so a press with nothing offered can be told apart from no press.
func was_pressed() -> bool:
	return _presses > 0 or not _tapped.is_empty()


## The one the next use goes to: its id, or "" for none. `offered` are the ids it may go to, in
## the order to pick them, and `holds` whether the profile holds the item; without one, or once
## nothing picked is offered anymore, nothing is used and the pick ends.
func chosen(offered: PackedStringArray, holds: bool) -> String:
	var presses: int = _presses
	var tapped: String = _tapped
	var steps: int = _steps
	var confirmed: bool = _confirmed
	var cancelled: bool = _cancelled
	_presses = 0
	_tapped = ""
	_settled()
	if not holds or offered.is_empty():
		picked = ""
		return ""
	if offered.has(tapped):
		return tapped
	if picked.is_empty():
		if presses == 0:
			return ""
		if offered.size() == 1:
			return offered[0]
		# Further presses before this command already move the pick on.
		picked = offered[0]
		steps = presses - 1
	var place: int = offered.find(picked)
	if cancelled or place < 0:
		picked = ""
		return ""
	picked = offered[posmod(place + steps, offered.size())]
	if not confirmed:
		return ""
	var chosen_id: String = picked
	picked = ""
	return chosen_id


## Forgets the moves, the confirmation and the cancel heard since the last command.
func _settled() -> void:
	_steps = 0
	_confirmed = false
	_cancelled = false
