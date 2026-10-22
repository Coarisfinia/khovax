class_name AreaStanding
extends RefCounted
## Which area each player stands in (#348, #350): a place (#339) or a region piece, each named by
## its id. A player who now stands in another area than remembered enters it, however they came to
## stand there: stepping in from outside it, starting there, or arriving through an exit. Leaving
## an area forgets it, so stepping back in enters it again.

## The area each player stands in, by entity id, as its index among the area ids (sorted); a player
## standing in none isn't here.
var areas: Dictionary[int, int] = {}


## The players in `state`, in id order, who now stand in another area than remembered, which is
## remembered from now on. `area_of` names each tile's area, and `ids` are every area's id, sorted.
func enter(
	state: GameState,
	area_of: Dictionary[Vector2i, String],
	ids: Array[String],
) -> Array[Entity]:
	var entered: Array[Entity] = []
	for walker: Entity in state.entities:
		if walker.slot == Entity.NO_SLOT:
			continue
		var index: int = ids.find(area_of.get(walker.tile, ""))
		if index == areas.get(walker.id, -1):
			continue
		if index < 0:
			forget(walker.id)
		else:
			areas[walker.id] = index
			entered.append(walker)
	return entered


## Forgets where the entity with this id stands: it left the instance.
func forget(entity_id: int) -> void:
	var _forgotten: bool = areas.erase(entity_id)


## Where the players stand, as entity id and area index after one another, by id: for the state
## hash and the save.
func flat() -> Array[int]:
	return DataReader.flat_pairs(areas)


## Restores what `flat` gave, saved under `key` in `values`, for a region with `count` areas: each
## an entity in `state` standing in one of them, or the save is refused.
func load_flat(state: GameState, values: DataReader, key: String, count: int) -> void:
	areas.clear()
	var saved: Dictionary[int, int] = values.pairs(key, 0, DataReader.MOST)
	for entity_id: int in saved:
		if saved[entity_id] >= count or state.entity(entity_id) == null:
			values.fail("%s: %d isn't an entity in one of %d areas" % [key, entity_id, count])
			return
		areas[entity_id] = saved[entity_id]


## The area ids `area_of` names, sorted, each once.
static func ids_of(area_of: Dictionary[Vector2i, String]) -> Array[String]:
	var ids: Array[String] = []
	for area: String in area_of.values():
		if not ids.has(area):
			ids.append(area)
	ids.sort()
	return ids
