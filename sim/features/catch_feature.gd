class_name CatchFeature
extends Feature
## Catching (#20): when a player's trail closes a ring around a wild monster, the monster is caught.
## Enclosed means the monster's tile can't reach the region's edge without crossing that player's
## trail: one flood fill from the edge over the region's tiles, whatever their terrain, so only the
## trail encloses. The caught monster leaves the world (a WildMonsterCaught event says who caught
## it) and the catcher's trail starts over from where it stands. Each player rings on their own
## trail. Strength, pressure, sealing and enrage build on this later (design report).
##
## It runs after the trail has grown this tick, reads the trail and the wild monsters, and starts
## the catcher's trail over through TrailFeature.restart: features later in the order change an
## earlier one only through its public methods.

## The edge of `_edge_region`, cached by _edge_of.
var _edge: Array[Vector2i] = []
var _edge_region: Region = null


func id() -> int:
	return Features.CATCH


func requires() -> Array[int]:
	var needed: Array[int] = [Features.TRAIL, Features.WILD_MONSTERS]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	var trails: TrailFeature = state.feature(Features.TRAIL) as TrailFeature
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	# A ring can only close when its player's trail grows, so rings are checked per new trail
	# tile, in the order the moves happened: entity id order, so when two players close rings
	# around the same monster in one tick, the earlier one catches it. This relies on wild monsters
	# standing still: every monster inside a ring was caught when the ring closed. A rule that
	# moves monsters must also check when a monster steps into an old ring. Copied, as catches add
	# events.
	for event: RefCounted in state.events.duplicate():
		var grew: TrailGrew = event as TrailGrew
		if grew == null or trails.trail(grew.entity_id) == null:
			continue
		var trail: Trail = trails.trail(grew.entity_id)
		if wild.monsters.is_empty() or not _may_close(trail, grew):
			continue
		# One flood per move, for every monster at once (#104).
		var edge: Array[Vector2i] = _edge_of(state.region)
		var reachable: Dictionary[Vector2i, bool] = outside(state.region, trail, edge)
		var caught: Array[int] = []
		for monster_id: int in wild.monsters:
			var spot: Vector2i = state.entity(monster_id).tile
			if not trail.tiles.has(spot) and not reachable.has(spot):
				caught.append(monster_id)
		for monster_id: int in caught:
			_catch(state, monster_id, grew.entity_id)
		if not caught.is_empty():
			trails.restart(grew.entity_id, state.entity(grew.entity_id).tile)


## Every tile off the trail that can reach the region's edge (a tile next to where the region ends)
## without stepping on the trail: one flood from the edge inward. A tile off the trail and not in
## it is enclosed by the trail.
static func outside(
	region: Region,
	trail: Trail,
	edge: Array[Vector2i],
) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {}
	var open: Array[Vector2i] = []
	for tile: Vector2i in edge:
		if not trail.tiles.has(tile):
			reached[tile] = true
			open.append(tile)
	while not open.is_empty():
		var current: Vector2i = open.pop_back()
		for direction: Vector2i in Hex.DIRECTIONS:
			var next: Vector2i = current + direction
			if region.has_tile(next) and not reached.has(next) and not trail.tiles.has(next):
				reached[next] = true
				open.append(next)
	return reached


## The region's edge: every tile next to where the region ends, in a fixed order. Regions don't
## change during a run (a rule that edits one in place must clear this cache), so it's worked out
## once per region, and a replaced region is noticed. Derived from the region, so not part of the
## hash.
func _edge_of(region: Region) -> Array[Vector2i]:
	if region != _edge_region:
		_edge_region = region
		_edge.clear()
		for tile: Vector2i in region.sorted_tiles():
			if _on_edge(region, tile):
				_edge.append(tile)
	return _edge


static func _on_edge(region: Region, tile: Vector2i) -> bool:
	for direction: Vector2i in Hex.DIRECTIONS:
		if not region.has_tile(tile + direction):
			return true
	return false


## Whether the step can have closed a ring: only if the tile walked onto touches the trail
## somewhere besides the tile it came from. A step that only extends a line, touching nothing
## else, seals no pocket off, so the flood can be skipped.
static func _may_close(trail: Trail, grew: TrailGrew) -> bool:
	for direction: Vector2i in Hex.DIRECTIONS:
		var next: Vector2i = grew.to + direction
		if next != grew.from and trail.tiles.has(next):
			return true
	return false


func _catch(state: GameState, monster_id: int, catcher_id: int) -> void:
	var tile: Vector2i = state.entity(monster_id).tile
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var species: String = wild.species_of(monster_id)
	var slot: int = state.entity(catcher_id).slot
	state.remove_entity(monster_id)
	state.events.append(WildMonsterCaught.new(monster_id, catcher_id, slot, tile, species))
