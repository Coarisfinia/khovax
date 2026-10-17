class_name TriggerFeature
extends Feature
## Tile triggers (#183): runs every trigger in the region's legend when it fires, each once per
## instance. The first is the lookout (#181): stepping onto it reveals the region around it to
## every player, through the fog feature (#177). Places (#339) are the exception: a player who steps
## into one, onto a tile of it from a tile outside it, raises PlaceReached every time, for their own
## quests. Instances whose region has triggers have it.

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
		var once: bool = triggers[i].action != TileTrigger.REACH
		if once and not fired.has(i) and _fires(state, triggers[i]):
			fired.append(i)
			fired.sort()
			_act(state, triggers[i])
	_reach_places(state)


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


## Raises PlaceReached for every player whose step this tick (an EntityMoved, in the order they
## were raised) leads onto a tile of a place from one that isn't part of it.
static func _reach_places(state: GameState) -> void:
	var places: Dictionary[Vector2i, String] = {}
	for trigger: TileTrigger in state.region.triggers:
		if trigger.action == TileTrigger.REACH:
			places[trigger.tile] = trigger.place
	if places.is_empty():
		return
	var reached: Array[PlaceReached] = []
	for event: RefCounted in state.events:
		if not event is EntityMoved:
			continue
		var moved: EntityMoved = event as EntityMoved
		var walker: Entity = state.entity(moved.entity_id)
		var place: String = places.get(moved.to, "")
		var entered: bool = not place.is_empty() and places.get(moved.from, "") != place
		if walker != null and walker.slot != Entity.NO_SLOT and entered:
			reached.append(_reached(place, walker))
	state.events.append_array(reached)


## That `walker` reached `place`.
static func _reached(place: String, walker: Entity) -> PlaceReached:
	return PlaceReached.new(place, walker.id, walker.slot)
