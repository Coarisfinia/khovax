class_name RevivePick
extends RefCounted
## Which fainted monster a revive item brings back (#780): the player picks. A press of
## revive_monster (V, the d-pad's down, or the herb button) revives the only fainted monster they
## carry at once; with several fainted it picks the first, in carried order, and then the arrows or
## the d-pad (ui_left/ui_up back, ui_right/ui_down and revive_monster on) move the pick between the
## fainted ones, ui_accept (Enter, A) uses the item on it and ui_cancel (Escape, B) lets it go. A
## tap on a fainted square of the roster (RosterHud, `tap`) revives that one at once. The player
## stands while picking (LocalInput). Presses are heard every frame and settled once per command,
## against the state the command is for.

## The short id of the fainted monster picked, or "" while not picking.
var picked: String = ""
## How many times revive_monster was pressed since the last command.
var _presses: int = 0
## How far the pick moved since the last command: +1 on, -1 back.
var _steps: int = 0
var _confirmed: bool = false
var _cancelled: bool = false
## The short id of the fainted monster tapped on the roster since the last command, or "".
var _tapped: String = ""


## Hears this frame's presses. While picking, one press moving the pick on counts once, as the
## d-pad's down is both revive_monster and ui_down.
func hear() -> void:
	if picked.is_empty():
		_presses += 1 if Input.is_action_just_pressed("revive_monster") else 0
		return
	var on: bool = Input.is_action_just_pressed("revive_monster")
	on = on or Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down")
	var back: bool = Input.is_action_just_pressed("ui_left")
	back = back or Input.is_action_just_pressed("ui_up")
	_steps += (1 if on else 0) - (1 if back else 0)
	_confirmed = _confirmed or Input.is_action_just_pressed("ui_accept")
	_cancelled = _cancelled or Input.is_action_just_pressed("ui_cancel")


## Revives the fainted monster `short_id` in the next command, ending any pick, as a tap on its
## roster square does.
func tap(short_id: String) -> void:
	_tapped = short_id
	picked = ""


## Ends any pick and forgets the presses, as while the game hears no input.
func drop() -> void:
	picked = ""
	_presses = 0
	_tapped = ""
	_settled()


## The fainted monster the next revive item brings back (ProfileTie): its short id, or ""
## for none. `fainted` are the short ids of the fainted monsters the player carries, in carried
## order, and `holds` whether their profile holds a revive item; without one, or once nothing picked
## has fainted anymore, nothing is used and the pick ends.
func chosen(fainted: PackedStringArray, holds: bool) -> String:
	var presses: int = _presses
	var tapped: String = _tapped
	var steps: int = _steps
	var confirmed: bool = _confirmed
	var cancelled: bool = _cancelled
	_presses = 0
	_tapped = ""
	_settled()
	if not holds or fainted.is_empty():
		picked = ""
		return ""
	if fainted.has(tapped):
		return tapped
	if picked.is_empty():
		if presses == 0:
			return ""
		if fainted.size() == 1:
			return fainted[0]
		# Further presses before this command already move the pick on.
		picked = fainted[0]
		steps = presses - 1
	var place: int = fainted.find(picked)
	if cancelled or place < 0:
		picked = ""
		return ""
	picked = fainted[posmod(place + steps, fainted.size())]
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
