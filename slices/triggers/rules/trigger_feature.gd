class_name TriggerFeature
extends Feature
## Tile triggers (#183): runs every trigger in the region's legend when it fires, each once per
## instance. The first is the lookout (#181): stepping onto it reveals the region around it to
## every player, through the fog feature (#177). Places (#339) are the exception: a player who comes
## to stand in one raises PlaceReached every time, for their own quests: stepping in from outside
## it, starting there, or arriving there through an exit (#348). Instances whose region has
## triggers have it.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "triggers"

## The region's triggers (TileTrigger.all_in), read when the instance begins.
var triggers: Array[TileTrigger] = []
## The index of every trigger in `triggers` that has fired, sorted.
var fired: Array[int] = []
## The place each player stands in. Coming to stand in another place reaches it.
var standing: AreaStanding = AreaStanding.new()


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [MovementFeature.ID, FogFeature.ID]
	return needed


func start(state: GameState) -> void:
	triggers = TileTrigger.all_in(state.region)


func step(state: GameState, _commands: Array[Command]) -> void:
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
	if not standing.areas.is_empty():
		values.append_array(standing.flat())
	return values


func entity_removed(_state: GameState, removed_id: int) -> void:
	standing.forget(removed_id)


## The triggers that have fired, by their index in the region's legend, and the place each player
## stands in.
func save_values() -> Dictionary:
	return { "fired": fired, "standing": standing.flat() }


func load_values(state: GameState, values: DataReader) -> void:
	var saved: Array[int] = values.wholes("fired", 0, triggers.size() - 1)
	fired.clear()
	for index: int in saved:
		if not fired.has(index):
			fired.append(index)
	fired.sort()
	# A save from before places were remembered has none: everyone stands in no place.
	var places: Dictionary[Vector2i, String] = _places()
	standing.load_flat(state, values, "standing", AreaStanding.ids_of(places).size())


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
		var fog: FogFeature = state.feature(FogFeature.ID) as FogFeature
		fog.reveal(state, Hex.disc(trigger.amount, trigger.tile))


## Raises PlaceReached for every player, in id order, who now stands in a place other than the one
## they stood in: stepping in from outside it, starting there, or arriving there through an exit.
func _reach_places(state: GameState) -> void:
	var places: Dictionary[Vector2i, String] = _places()
	if places.is_empty():
		return
	var reached: Array[PlaceReached] = []
	for walker: Entity in standing.enter(state, places, AreaStanding.ids_of(places)):
		reached.append(_reached(places[walker.tile], walker))
	state.events.append_array(reached)


## The place each of the region's place tiles is part of, by tile.
func _places() -> Dictionary[Vector2i, String]:
	var places: Dictionary[Vector2i, String] = {}
	for trigger: TileTrigger in triggers:
		if trigger.action == TileTrigger.REACH:
			places[trigger.tile] = trigger.place
	return places


## That `walker` reached `place`.
static func _reached(place: String, walker: Entity) -> PlaceReached:
	return PlaceReached.new(place, walker.id, walker.slot)
