class_name DialogHoldFeature
extends Feature
## Locking dialogs hold their player (#891, #912): while DialogFeature says a player's open dialog
## holds them (it locks, or a committing answer moved it on), they can't move or act except to
## answer, so their command this tick keeps only its answer and its request from the profile's
## outbox (Outbox, #771), which is sent only once a session and would otherwise be lost. It
## steps first, so every rule after it sees the held command. While every player in the instance is
## held, its wild monsters pause too (they don't move, strike or jump out of hiding): in
## single-player the world stands still for the dialog, while in co-op the others go on. The views
## keep animating, since they run on real time.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "dialog_hold"
## The features that pause while every player in the instance is held.
const PAUSED: Array[String] = [WildMonsterFeature.ID, WildAttackFeature.ID, HidingFeature.ID]

## Whether this switched the wild monsters' features off, until a player is free again.
var paused: bool = false


func id() -> String:
	return ID


## The dialogs it reads, and the features it pauses, all stepping after it.
func before() -> Array[String]:
	var later: Array[String] = [DialogFeature.ID]
	later.append_array(PAUSED)
	return later


## Keeps only the answer and the request of every held player's command, then pauses the wild
## monsters
## while every player here is held, or lets them go on.
func step(state: GameState, commands: Array[Command]) -> void:
	var dialogs: DialogFeature = state.feature(DialogFeature.ID) as DialogFeature
	if dialogs == null:
		return
	var players: int = 0
	var held: int = 0
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) == null:
			continue
		players += 1
		if not dialogs.holds(slot):
			continue
		held += 1
		var given: Command = Command.of(commands, slot)
		if given != null:
			commands[slot] = _answer_only(given)
	var pausing: bool = players > 0 and held == players
	if pausing != paused:
		paused = pausing
		for paused_id: String in PAUSED:
			state.set_enabled(paused_id, not pausing)


func hash_values() -> Array[int]:
	return [1 if paused else 0]


func save_values() -> Dictionary:
	return { "paused": 1 if paused else 0 }


func load_values(_state: GameState, values: DataReader) -> void:
	paused = values.whole("paused", 0, 1) == 1


## A command that only answers and carries the request `given` does: the held player stands.
static func _answer_only(given: Command) -> Command:
	var kept: Command = Command.new()
	kept.answer = given.answer
	kept.request = given.request
	kept.request_kind = given.request_kind
	kept.request_data = given.request_data
	return kept
