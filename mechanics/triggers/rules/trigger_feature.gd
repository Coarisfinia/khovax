class_name TriggerFeature
extends Feature
## Tile triggers (#183): runs every trigger in the region's legend when it fires, each once per
## instance. The first is the lookout (#181): stepping onto it reveals the region around it to
## every player, through the fog feature (#177). Places (#339) are the exception: a player who comes
## to stand in one raises PlaceReached every time, for their own quests: stepping in from outside
## it, starting there, or arriving there through an exit (#348). Instances whose region has
## triggers have it.

## The index of every trigger in `state.region.triggers` that has fired, sorted.
var fired: Array[int] = []
## The place each player stands in, by entity id, as its index among the region's place ids
## (sorted); a player standing in none isn't here. Coming to stand in another place reaches it.
var standing: Dictionary[int, int] = {}


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
	# Only where someone stands in a place, so regions without places hash as before.
	if not standing.is_empty():
		values.append_array(_standing_flat())
	return values


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _forgotten: bool = standing.erase(removed_id)


## The triggers that have fired, by their index in the region's legend, and the place each player
## stands in.
func save_values() -> Dictionary:
	return { "fired": fired, "standing": _standing_flat() }


func load_values(state: GameState, values: DataReader) -> void:
	var saved: Array[int] = values.wholes("fired", 0, state.region.triggers.size() - 1)
	fired.clear()
	for index: int in saved:
		if not fired.has(index):
			fired.append(index)
	fired.sort()
	standing.clear()
	# A save from before places were remembered has none: everyone stands in no place.
	if values.data.has("standing"):
		var places: int = _place_ids(state.region).size()
		var pairs: Array[int] = values.wholes("standing", 0, DataReader.MOST)
		for i: int in range(0, pairs.size() - 1, 2):
			if pairs[i + 1] < places and state.entity(pairs[i]) != null:
				standing[pairs[i]] = pairs[i + 1]


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


## Raises PlaceReached for every player, in id order, who now stands in a place other than the one
## they stood in: stepping in from outside it, starting there, or arriving there through an exit.
func _reach_places(state: GameState) -> void:
	var places: Dictionary[Vector2i, String] = {}
	for trigger: TileTrigger in state.region.triggers:
		if trigger.action == TileTrigger.REACH:
			places[trigger.tile] = trigger.place
	if places.is_empty():
		return
	var ids: Array[String] = _place_ids(state.region)
	var reached: Array[PlaceReached] = []
	for walker: Entity in state.entities:
		if walker.slot == Entity.NO_SLOT:
			continue
		var place: String = places.get(walker.tile, "")
		var index: int = ids.find(place)
		if index == standing.get(walker.id, -1):
			continue
		if index < 0:
			var _left: bool = standing.erase(walker.id)
		else:
			standing[walker.id] = index
			reached.append(_reached(place, walker))
	state.events.append_array(reached)


## The ids of the places in `region`'s legend, sorted, each once.
static func _place_ids(region: Region) -> Array[String]:
	var ids: Array[String] = []
	for trigger: TileTrigger in region.triggers:
		if trigger.action == TileTrigger.REACH and not ids.has(trigger.place):
			ids.append(trigger.place)
	ids.sort()
	return ids


## Where the players stand, as entity id and place index after one another, by id.
func _standing_flat() -> Array[int]:
	var flat: Array[int] = []
	var ids: Array[int] = []
	ids.assign(standing.keys())
	ids.sort()
	for entity_id: int in ids:
		flat.append_array([entity_id, standing[entity_id]])
	return flat


## That `walker` reached `place`.
static func _reached(place: String, walker: Entity) -> PlaceReached:
	return PlaceReached.new(place, walker.id, walker.slot)
