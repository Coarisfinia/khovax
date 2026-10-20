class_name DialogFeature
extends Feature
## Dialogs in the simulation (#635, #898): a player who chooses an answer on the dialog screen sends
## it in their command, as its code (`code`), and this raises DialogAnswered for them, naming the
## dialog and the answer. A code no dialog has is ignored. It also keeps each player's open dialog,
## the state the dialog card follows: talking to a person (NpcTalkedTo, raised earlier in the tick)
## opens their dialog at its first line, and an answer moves it on to the line it leads to, or
## closes it. Reading on through lines without answers changes nothing in the game, so the line kept
## is the one the last answer led to, and the card reads on from it.

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
## Each player's open dialog, by slot: its id and the index of its line.
var _open: Dictionary[int, String] = {}
var _lines: Dictionary[int, int] = {}


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
			_move(talked.slot, talked.dialog, 0)
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var player: Entity = state.player(slot)
		if command == null or player == null or not answers.has(command.answer):
			continue
		var ids: PackedStringArray = answers[command.answer]
		state.events.append(_answered(ids, player))
		var leads_to: int = leads.get(command.answer, NO_LINE)
		_move(slot, ids[0], leads_to)


## Each open dialog, in slot order: the slot, its id's code and its line.
func hash_values() -> Array[int]:
	var values: Array[int] = [_open.size()]
	for slot: int in _slots():
		values.append_array([slot, StateHash.name_code(_open[slot]), _lines[slot]])
	return values


## Each open dialog, in slot order: the slot, its id and its line.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for slot: int in _slots():
		saved.append({ "slot": slot, "dialog": _open[slot], "line": _lines[slot] })
	return { "open": saved }


func load_values(_state: GameState, values: DataReader) -> void:
	_open.clear()
	_lines.clear()
	for entry: DataReader in values.entries("open"):
		var slot: int = entry.whole("slot", 0, GameState.MAX_PLAYERS - 1)
		var dialog_id: String = entry.text("dialog")
		var line: int = entry.whole("line", 0, DataReader.MOST)
		if values.failed():
			return
		var lines: int = line_counts.get(dialog_id, 0)
		if _open.has(slot) or line >= lines:
			values.fail("slot %d's open dialog %s at line %d isn't one" % [slot, dialog_id, line])
			return
		_move(slot, dialog_id, line)


## Opens the dialog `dialog_id` at the line `line` for the player in `slot`, or closes theirs for
## NO_LINE.
func _move(slot: int, dialog_id: String, line: int) -> void:
	if line == NO_LINE:
		_close(slot)
		return
	_open[slot] = dialog_id
	_lines[slot] = line


func _close(slot: int) -> void:
	var _closed: bool = _open.erase(slot)
	var _cleared: bool = _lines.erase(slot)


## The slots with an open dialog, in order.
func _slots() -> Array[int]:
	var slots: Array[int] = []
	slots.assign(_open.keys())
	slots.sort()
	return slots


## That `player` chose the answer `ids` names: its dialog's id and its own.
static func _answered(ids: PackedStringArray, player: Entity) -> DialogAnswered:
	return DialogAnswered.new(ids[0], ids[1], player.id, player.slot)
