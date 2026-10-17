class_name EnteringFeature
extends Feature
## Entering a region piece (#350): a player who comes to stand in another piece of an arranged
## region raises PieceEntered, once per arrival, for their own quests. No legend marks it: every
## piece is one, by its file name. Instances whose region is arranged from pieces have it.

## The piece each player stands in.
var inside: AreaStanding = AreaStanding.new()
## Every piece's id, sorted; the region never changes while it's loaded.
var _ids: Array[String] = []


func id() -> int:
	return Features.ENTERING


func requires() -> Array[int]:
	var needed: Array[int] = [Features.MOVEMENT]
	return needed


func start(state: GameState) -> void:
	_ids = AreaStanding.ids_of(state.region.piece_of)


func step(state: GameState, _commands: Array[Command]) -> void:
	var entered: Array[PieceEntered] = []
	for walker: Entity in inside.enter(state, state.region.piece_of, _ids):
		entered.append(PieceEntered.new(state.region.piece_of[walker.tile], walker.id, walker.slot))
	state.events.append_array(entered)


func hash_values() -> Array[int]:
	var values: Array[int] = [inside.areas.size()]
	values.append_array(inside.flat())
	return values


func entity_removed(_state: GameState, removed_id: int) -> void:
	inside.forget(removed_id)


## The piece each player stands in.
func save_values() -> Dictionary:
	return { "inside": inside.flat() }


func load_values(state: GameState, values: DataReader) -> void:
	inside.load_flat(state, values, "inside", _ids.size())
