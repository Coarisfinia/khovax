class_name MapGenerator
extends RefCounted
## Generated maps, deterministic from the instance's seed (#36): the same seed gives the same map on
## every platform. Each generator draws from its own stream of the seed (STREAM), apart from the
## features' streams, so changing a rule never changes the maps.

## The map generators' stream of the run's seed. Feature ids are small, so this can't collide.
const STREAM: int = 1_000_000


## An island of `size` tiles grown from the origin, one random neighbor at a time, so every tile
## connects to the origin. Then up to `rocks` tiles turn into rock, each only where it doesn't cut
## any ground off from the rest. The players start on the origin and the tiles nearest to it.
static func island(seed_value: int, size: int, rocks: int) -> HexMap:
	var rng: Rng = Rng.new(seed_value, STREAM)
	var map: HexMap = HexMap.new()
	var wanted: int = clampi(size, GameState.MAX_PLAYERS, HexMap.MAX_TILES)
	var frontier: Array[Vector2i] = [Vector2i.ZERO]
	while map.size() < wanted:
		var tile: Vector2i = frontier.pop_at(rng.below(frontier.size()))
		if map.has_tile(tile):
			continue
		map.terrain[tile] = HexMap.GROUND
		for direction: Vector2i in Hex.DIRECTIONS:
			if not map.has_tile(tile + direction):
				frontier.append(tile + direction)
	map.starts = map.reachable(Vector2i.ZERO).slice(0, GameState.MAX_PLAYERS)
	_place_rocks(map, rng, rocks)
	return map


## Turns up to `rocks` ground tiles into rock, never a start and never one that splits the ground.
static func _place_rocks(map: HexMap, rng: Rng, rocks: int) -> void:
	var candidates: Array[Vector2i] = []
	for tile: Vector2i in map.sorted_tiles():
		if not map.starts.has(tile):
			candidates.append(tile)
	var placed: int = 0
	var ground: int = map.size()
	while placed < rocks and not candidates.is_empty():
		var tile: Vector2i = candidates.pop_at(rng.below(candidates.size()))
		map.terrain[tile] = HexMap.BLOCKED
		if map.reachable(map.starts[0]).size() == ground - 1:
			placed += 1
			ground -= 1
		else:
			map.terrain[tile] = HexMap.GROUND
