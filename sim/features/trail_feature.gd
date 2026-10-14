class_name TrailFeature
extends Feature
## The trails: each player's trail holds every tile that player has stood on or moved onto. Rings
## are drawn with them. They grow from EntityMoved events, so the trail comes after movement in an
## instance's order. Walking over a trail again changes nothing yet; a catch starts the catcher's
## trail over (CatchFeature).

## Every player's trail, by entity id.
var trails: Dictionary[int, Trail] = {}


func id() -> int:
	return Features.TRAIL


func requires() -> Array[int]:
	var needed: Array[int] = [Features.MOVEMENT]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	# Copied, as the loop adds TrailGrew events to the same list.
	for event: RefCounted in state.events.duplicate():
		var moved: EntityMoved = event as EntityMoved
		if moved == null or not trails.has(moved.entity_id):
			continue
		var tiles: Dictionary[Vector2i, bool] = trails[moved.entity_id].tiles
		if not tiles.has(moved.to):
			tiles[moved.to] = true
			state.events.append(_grew(moved))


func entity_added(_state: GameState, added: Entity) -> void:
	if added.slot != Entity.NO_SLOT:
		trails[added.id] = Trail.new(added.tile)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = trails.erase(removed_id)


## The event for a trail that grew by the tile `moved` walked onto.
static func _grew(moved: EntityMoved) -> TrailGrew:
	return TrailGrew.new(moved.entity_id, moved.from, moved.to)


## Starts the entity's trail over, with only `tile` on it. Does nothing for an entity without one.
func restart(entity_id: int, tile: Vector2i) -> void:
	if trails.has(entity_id):
		trails[entity_id] = Trail.new(tile)


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
