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

## Whether the wild monsters pause, until a player is free again, and which of their features this
## switched off for it: only those that were on, so a feature switched off for another reason stays
## off when they go on.
var paused: bool = false
var switched: Array[String] = []


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
		var given: Command = Command.of(commands, slot)
		var answering: bool = given != null and dialogs.answer_holds(given.answer)
		if not dialogs.holds(slot) and not answering:
			continue
		held += 1
		if given != null:
			commands[slot] = _answer_only(given)
	var pausing: bool = players > 0 and held == players
	if pausing == paused:
		return
	paused = pausing
	if pausing:
		for paused_id: String in PAUSED:
			var paused_feature: Feature = state.feature(paused_id)
			if paused_feature != null and paused_feature.enabled:
				switched.append(paused_id)
				state.set_enabled(paused_id, false)
	else:
		for paused_id: String in switched:
			state.set_enabled(paused_id, true)
		switched.clear()


func hash_values() -> Array[int]:
	var values: Array[int] = [1 if paused else 0, switched.size()]
	for paused_id: String in switched:
		values.append(StateHash.name_code(paused_id))
	return values


func save_values() -> Dictionary:
	return { "paused": 1 if paused else 0, "switched": switched.duplicate() }


func load_values(_state: GameState, values: DataReader) -> void:
	paused = values.whole("paused", 0, 1) == 1
	switched.clear()
	var saved: Variant = values.data.get("switched")
	if not saved is Array:
		values.fail("switched isn't a list")
		return
	for paused_id: Variant in saved:
		if not paused_id is String or not PAUSED.has(paused_id) or switched.has(paused_id):
			values.fail("a paused feature %s isn't one this pauses" % [paused_id])
			return
		switched.append(paused_id)


## A command that only answers and carries the request `given` does: the held player stands.
static func _answer_only(given: Command) -> Command:
	var kept: Command = Command.new()
	kept.answer = given.answer
	kept.request = given.request
	kept.request_kind = given.request_kind
	kept.request_data = given.request_data
	return kept
