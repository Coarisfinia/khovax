class_name SceneHoldFeature
extends Feature
## Holds every player in the instance and pauses wild attacks and hunts while a scene runs
## (#2415, #981), like DialogHoldFeature does for locking dialogs: players cannot move or act
## (keeping only their profile outbox requests so none is lost), HealthFeature shields them, and
## wild monsters, wild attacks, hiding and hunts pause until the scene finishes. Steps right after
## DialogHoldFeature so it never clobbers a locking dialog's shields or paused features.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "scene_hold"
## The features that pause while a scene runs in this instance.
const PAUSED: Array[String] = [
	WildMonsterFeature.ID,
	WildAttackFeature.ID,
	HidingFeature.ID,
	HuntFeature.ID,
]

## Whether this feature currently holds the instance paused for a scene, and which features it
## switched off (only those that were enabled, so features off for another reason stay off).
var paused: bool = false
var switched: Array[String] = []


func id() -> String:
	return ID


## Steps after DialogHoldFeature when present so a dialog's shields are applied first.
func after() -> Array[String]:
	var earlier: Array[String] = [DialogHoldFeature.ID]
	return earlier


## Reads SceneFeature and HealthFeature, and pauses PAUSED features before they step.
func before() -> Array[String]:
	var later: Array[String] = [HealthFeature.ID, SceneFeature.ID]
	later.append_array(PAUSED)
	return later


func step(state: GameState, commands: Array[Command]) -> void:
	var scenes: SceneFeature = state.feature(SceneFeature.ID) as SceneFeature
	var running: bool = scenes != null and scenes.is_running()
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if running:
		for slot: int in GameState.MAX_PLAYERS:
			var player: Entity = state.player(slot)
			if player == null:
				continue
			if health != null:
				health.shield(player.id, true)
			var given: Command = Command.of(commands, slot)
			if given != null:
				commands[slot] = _request_only(given)
		paused = true
		for paused_id: String in PAUSED:
			var paused_feature: Feature = state.feature(paused_id)
			if paused_feature != null and paused_feature.enabled:
				if not switched.has(paused_id):
					switched.append(paused_id)
				state.set_enabled(paused_id, false)
	elif paused:
		_release(state, health)


func disabled(state: GameState) -> void:
	if paused:
		var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
		_release(state, health)


## Re-enables the features this switched off and clears shields when DialogHoldFeature didn't
## already set them this tick.
func _release(state: GameState, health: HealthFeature) -> void:
	paused = false
	for paused_id: String in switched:
		state.set_enabled(paused_id, true)
	switched.clear()
	var dialog_hold: DialogHoldFeature = state.feature(DialogHoldFeature.ID) as DialogHoldFeature
	if health != null and (dialog_hold == null or not dialog_hold.enabled):
		for slot: int in GameState.MAX_PLAYERS:
			var player: Entity = state.player(slot)
			if player != null:
				health.shield(player.id, false)


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


## A command keeping only the profile outbox request `given` carries: held players stand still.
static func _request_only(given: Command) -> Command:
	var kept: Command = Command.new()
	kept.request = given.request
	kept.request_kind = given.request_kind
	kept.request_data = given.request_data
	return kept
