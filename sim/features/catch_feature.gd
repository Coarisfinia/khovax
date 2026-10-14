class_name CatchFeature
extends Feature
## Catching (#20): when a player's trail closes a ring around a wild monster, the monster is
## caught. Enclosed means the monster's tile can't reach the map's edge without crossing that
## player's trail: a flood fill over the map's tiles, whatever their terrain, so only the trail
## encloses. The caught monster leaves the world (a WildMonsterCaught event says who caught it)
## and the catcher's trail starts over from where it stands. Each player rings on their own trail.
## Strength, pressure, sealing and enrage build on this later (design report).
##
## It runs after the trail has grown this tick, reads the trail and the wild monsters, and starts
## the catcher's trail over through TrailFeature.restart: features later in the order change an
## earlier one only through its public methods.


func id() -> int:
	return Features.CATCH


func requires() -> Array[int]:
	var needed: Array[int] = [Features.TRAIL, Features.WILD_MONSTERS]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	var trails: TrailFeature = state.feature(Features.TRAIL) as TrailFeature
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	# Only a trail that grew this tick can have closed a ring, in the order the moves happened.
	for event: RefCounted in state.events.duplicate():
		var moved: EntityMoved = event as EntityMoved
		if moved == null or trails.trail(moved.entity_id) == null:
			continue
		var trail: Trail = trails.trail(moved.entity_id)
		var caught: Array[int] = []
		for monster_id: int in wild.monsters:
			if is_enclosed(state.map, trail, state.entity(monster_id).tile):
				caught.append(monster_id)
		for monster_id: int in caught:
			_catch(state, monster_id, moved.entity_id)
		if not caught.is_empty():
			trails.restart(moved.entity_id, state.entity(moved.entity_id).tile)


## Whether `tile` can't reach the map's edge (a tile next to where the map ends) without stepping
## on the trail. A tile on the trail itself isn't enclosed by it.
static func is_enclosed(map: HexMap, trail: Trail, tile: Vector2i) -> bool:
	if trail.tiles.has(tile):
		return false
	var seen: Dictionary[Vector2i, bool] = { tile: true }
	var open: Array[Vector2i] = [tile]
	while not open.is_empty():
		var current: Vector2i = open.pop_back()
		for direction: Vector2i in Hex.DIRECTIONS:
			var next: Vector2i = current + direction
			if not map.has_tile(next):
				return false
			if not seen.has(next) and not trail.tiles.has(next):
				seen[next] = true
				open.append(next)
	return true


func _catch(state: GameState, monster_id: int, catcher_id: int) -> void:
	var tile: Vector2i = state.entity(monster_id).tile
	state.remove_entity(monster_id)
	state.events.append(WildMonsterCaught.new(monster_id, catcher_id, tile))
