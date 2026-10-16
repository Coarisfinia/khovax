class_name TriggerFeature
extends Feature
## Tile triggers (#183): runs every trigger in the region's legend when it fires, each once per
## instance. The first is the lookout (#181): stepping onto it reveals the region around it to
## every player, through the fog feature (#177). Instances whose region has triggers have it.

## The index of every trigger in `state.region.triggers` that has fired, sorted.
var fired: Array[int] = []


func id() -> int:
	return Features.TRIGGERS


func requires() -> Array[int]:
	var needed: Array[int] = [Features.MOVEMENT, Features.FOG]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	var triggers: Array[TileTrigger] = state.region.triggers
	for i: int in triggers.size():
		if not fired.has(i) and _fires(state, triggers[i]):
			fired.append(i)
			fired.sort()
			_act(state, triggers[i])


func hash_values() -> Array[int]:
	var values: Array[int] = [fired.size()]
	values.append_array(fired)
	return values


## The triggers that have fired, by their index in the region's legend.
func save_values() -> Dictionary:
	return { "fired": fired }


func load_values(state: GameState, values: DataReader) -> void:
	var saved: Array[int] = values.wholes("fired", 0, state.region.triggers.size() - 1)
	fired.clear()
	for index: int in saved:
		if not fired.has(index):
			fired.append(index)
	fired.sort()


## Whether `trigger`'s when has come: for STEP, a player stands on its tile. Standing counts, not
## only a step onto it, so arriving there through an exit or starting there fires it too.
static func _fires(state: GameState, trigger: TileTrigger) -> bool:
	if trigger.condition == TileTrigger.STEP:
		for slot: int in GameState.MAX_PLAYERS:
			var player: Entity = state.player(slot)
			if player != null and player.tile == trigger.tile:
				return true
	return false


## Runs `trigger`'s action.
static func _act(state: GameState, trigger: TileTrigger) -> void:
	if trigger.action == TileTrigger.REVEAL:
		var fog: FogFeature = state.feature(Features.FOG) as FogFeature
		fog.reveal(state, Hex.disc(trigger.amount, trigger.tile))
