class_name DialogFeature
extends Feature
## Dialog answers (#635): a player who chooses an answer on the dialog screen sends it in their
## command, as its code (`code`), and this raises DialogAnswered for them, naming the dialog and the
## answer. Reading a dialog on changes nothing in the game, so only the answers reach the
## simulation. A code no dialog has is ignored. It keeps no state of its own.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "dialogs"

## Every dialog answer, by its code: the dialog's id and the answer's (the dialogs' content data).
var answers: Dictionary[int, PackedStringArray] = {}


func _init(by_code: Dictionary[int, PackedStringArray] = {}) -> void:
	answers = by_code


func id() -> String:
	return ID


## The code a command gives the answer `answer_id` of the dialog `dialog_id` by: a whole number from
## both ids, the same on every machine, and never Command.NO_ANSWER for a real answer (the dialogs'
## content refuses one that would be, or two that share a code).
static func code(dialog_id: String, answer_id: String) -> int:
	return StateHash.name_code(dialog_id + "/" + answer_id)


## Raises DialogAnswered for every player, in slot order, whose command answers a dialog.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var player: Entity = state.player(slot)
		if command == null or player == null or not answers.has(command.answer):
			continue
		state.events.append(_answered(answers[command.answer], player))


## That `player` chose the answer `ids` names: its dialog's id and its own.
static func _answered(ids: PackedStringArray, player: Entity) -> DialogAnswered:
	return DialogAnswered.new(ids[0], ids[1], player.id, player.slot)
