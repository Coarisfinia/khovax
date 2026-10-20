class_name DialogFeature
extends Feature
## Dialogs in the simulation (#635, #898): a player who chooses an answer on the dialog screen sends
## it in their command, as its code (`code`), and this raises DialogAnswered for them, naming the
## dialog and the answer. A code no dialog has is ignored. It also keeps each player's open dialog,
## the state the dialog card follows: talking to a person (NpcTalkedTo, raised earlier in the tick)
## opens their dialog at its first line, and an answer moves it on to the line it leads to, or
## closes it. Reading on through lines without answers changes nothing in the game, so the line kept
## is the one the last answer led to, and the card reads on from it. A dialog that locks, or one a
## committing answer moved on, holds its player until it closes (#912, DialogHoldFeature).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "dialogs"
## The line of a player with no open dialog.
const NO_LINE: int = -1

## Every dialog answer, by its code: the dialog's id and the answer's (the dialogs' content data).
var answers: Dictionary[int, PackedStringArray] = {}
## The index of the line each answer leads to, by its code, or NO_LINE when it ends the dialog.
var leads: Dictionary[int, int] = {}
## How many lines each dialog has, by its id.
var line_counts: Dictionary[String, int] = {}
## Whether each dialog locks, by its id, and whether each answer commits, by its code (#912).
var locking: Dictionary[String, bool] = {}
var committing: Dictionary[int, bool] = {}
## Each player's open dialog, by slot: its id and the index of its line, and whether it holds them.
var _open: Dictionary[int, String] = {}
var _lines: Dictionary[int, int] = {}
var _holding: Dictionary[int, bool] = {}


func _init(
	by_code: Dictionary[int, PackedStringArray] = {},
	leading: Dictionary[int, int] = {},
	counts: Dictionary[String, int] = {},
) -> void:
	answers = by_code
	leads = leading
	line_counts = counts


func id() -> String:
	return ID


## People to talk to open the dialogs, when the instance has them.
func after() -> Array[String]:
	var earlier: Array[String] = [NpcFeature.ID]
	return earlier


## The code a command gives the answer `answer_id` of the dialog `dialog_id` by (CommandCodes),
## never Command.NO_ANSWER for a real answer (the dialogs' content files it with CommandCodes.file).
static func code(dialog_id: String, answer_id: String) -> int:
	return CommandCodes.of(dialog_id + "/" + answer_id)


## The id of the dialog open for the player in `slot`, or "".
func dialog_of(slot: int) -> String:
	var open_id: String = _open.get(slot, "")
	return open_id


## The index of the line the dialog open for the player in `slot` is at, or NO_LINE.
func line_of(slot: int) -> int:
	var line: int = _lines.get(slot, NO_LINE)
	return line


## Whether the open dialog of the player in `slot` holds them until it closes (#912).
func holds(slot: int) -> bool:
	return _holding.has(slot)


## Whether choosing the answer `answer_code` holds its player: it commits, or its dialog locks. A
## command carrying it is held from that tick on, so nothing else in it acts (DialogHoldFeature).
func answer_holds(answer_code: int) -> bool:
	if not answers.has(answer_code):
		return false
	var commits: bool = committing.get(answer_code, false)
	var locks: bool = locking.get(answers[answer_code][0], false)
	return commits or locks


## Closes the dialogs of players who left, opens the dialogs players talked to someone for, then,
## in slot order, raises DialogAnswered for every player whose command answers a dialog and moves
## their dialog to where the answer leads.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in _open.keys():
		if state.player(slot) == null:
			_close(slot)
	for event: RefCounted in state.events:
		var talked: NpcTalkedTo = event as NpcTalkedTo
		if talked != null and line_counts.has(talked.dialog):
			var locks: bool = locking.get(talked.dialog, false)
			_move(talked.slot, talked.dialog, 0, locks)
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var player: Entity = state.player(slot)
		if command == null or player == null or not answers.has(command.answer):
			continue
		var ids: PackedStringArray = answers[command.answer]
		state.events.append(_answered(ids, player))
		var leads_to: int = leads.get(command.answer, NO_LINE)
		var held: bool = _open.get(slot, "") == ids[0] and holds(slot)
		var commits: bool = committing.get(command.answer, false)
		var locks: bool = locking.get(ids[0], false)
		_move(slot, ids[0], leads_to, held or commits or locks)


## Each open dialog, in slot order: the slot, its id's code, its line and whether it holds them.
func hash_values() -> Array[int]:
	var values: Array[int] = [_open.size()]
	for slot: int in _slots():
		var held: int = 1 if holds(slot) else 0
		values.append_array([slot, StateHash.name_code(_open[slot]), _lines[slot], held])
	return values


## Each open dialog, in slot order: the slot, its id, its line and whether it holds them.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for slot: int in _slots():
		var held: int = 1 if holds(slot) else 0
		saved.append({ "slot": slot, "dialog": _open[slot], "line": _lines[slot], "holds": held })
	return { "open": saved }


func load_values(_state: GameState, values: DataReader) -> void:
	_open.clear()
	_lines.clear()
	_holding.clear()
	for entry: DataReader in values.entries("open"):
		var slot: int = entry.whole("slot", 0, GameState.MAX_PLAYERS - 1)
		var dialog_id: String = entry.text("dialog")
		var line: int = entry.whole("line", 0, DataReader.MOST)
		var held: bool = entry.whole("holds", 0, 1) == 1
		if values.failed():
			return
		var lines: int = line_counts.get(dialog_id, 0)
		if _open.has(slot) or line >= lines:
			values.fail("slot %d's open dialog %s at line %d isn't one" % [slot, dialog_id, line])
			return
		_move(slot, dialog_id, line, held)


## Opens the dialog `dialog_id` at the line `line` for the player in `slot`, holding them with
## `held`, or closes theirs for NO_LINE.
func _move(slot: int, dialog_id: String, line: int, held: bool) -> void:
	if line == NO_LINE:
		_close(slot)
		return
	_open[slot] = dialog_id
	_lines[slot] = line
	if held:
		_holding[slot] = true
	else:
		var _released: bool = _holding.erase(slot)


func _close(slot: int) -> void:
	var _closed: bool = _open.erase(slot)
	var _cleared: bool = _lines.erase(slot)
	var _released: bool = _holding.erase(slot)


## The slots with an open dialog, in order.
func _slots() -> Array[int]:
	var slots: Array[int] = []
	slots.assign(_open.keys())
	slots.sort()
	return slots


## That `player` chose the answer `ids` names: its dialog's id and its own.
static func _answered(ids: PackedStringArray, player: Entity) -> DialogAnswered:
	return DialogAnswered.new(ids[0], ids[1], player.id, player.slot)
