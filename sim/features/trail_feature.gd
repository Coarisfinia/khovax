class_name TrailFeature
extends Feature
## The trails: each player's trail holds every tile that player has stood on or moved onto. Rings
## are drawn with them. They grow from EntityMoved events, so the trail comes after movement in an
## instance's order. Walking over a trail again changes nothing yet.

## Every player's trail, by entity id.
var trails: Dictionary[int, Trail] = {}


func id() -> int:
	return Features.TRAIL


func requires() -> Array[int]:
	var needed: Array[int] = [Features.MOVEMENT]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	for event: RefCounted in state.events:
		var moved: EntityMoved = event as EntityMoved
		if moved != null and trails.has(moved.entity_id):
			trails[moved.entity_id].tiles[moved.to] = true


func entity_added(_state: GameState, added: Entity) -> void:
	if added.slot != Entity.NO_SLOT:
		trails[added.id] = Trail.new(added.tile)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = trails.erase(removed_id)


## The entity's trail, or null when it has none.
func trail(entity_id: int) -> Trail:
	return trails.get(entity_id)


func hash_values() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(trails.keys())
	ids.sort()
	var values: Array[int] = [ids.size()]
	for each: int in ids:
		var tiles: Array[Vector2i] = trails[each].sorted_tiles()
		values.append(each)
		values.append(tiles.size())
		for tile: Vector2i in tiles:
			values.append(tile.x)
			values.append(tile.y)
	return values
