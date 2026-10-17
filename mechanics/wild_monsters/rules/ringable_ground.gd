class_name RingableGround
extends RefCounted
## Where a ring can't be drawn around a wild monster (#364), by the rule DominationFeature
## dominates by: a monster is enclosed when the trail cuts its tile off from the region's edge,
## and the trail only lies on walkable tiles. So no ring encloses a monster on a tile next to where
## the region ends, nor one beside unwalkable ground (rock, water) that joins up with the edge: no
## trail cuts through that. Anywhere else, the walkable tiles around the monster and the unwalkable
## ground beside it make a ring. Only the terrain counts, so a region's answer never changes.


## Every walkable tile of `region` a ring can't enclose a wild monster on.
static func unringable(region: Region) -> Dictionary[Vector2i, bool]:
	var exposed: Dictionary[Vector2i, bool] = _unwalkable_from_edge(region)
	var stuck: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in region.sorted_tiles():
		if not region.is_walkable(tile):
			continue
		for direction: Vector2i in Hex.DIRECTIONS:
			var next: Vector2i = tile + direction
			if not region.has_tile(next) or exposed.has(next):
				stuck[tile] = true
	return stuck


## Every unwalkable tile joined to the region's edge through unwalkable tiles: one flood from the
## unwalkable tiles next to where the region ends.
static func _unwalkable_from_edge(region: Region) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {}
	var open: Array[Vector2i] = []
	for tile: Vector2i in region.sorted_tiles():
		if region.is_walkable(tile):
			continue
		for direction: Vector2i in Hex.DIRECTIONS:
			if not reached.has(tile) and not region.has_tile(tile + direction):
				reached[tile] = true
				open.append(tile)
	while not open.is_empty():
		var current: Vector2i = open.pop_back()
		for direction: Vector2i in Hex.DIRECTIONS:
			var next: Vector2i = current + direction
			if region.has_tile(next) and not region.is_walkable(next) and not reached.has(next):
				reached[next] = true
				open.append(next)
	return reached


## The first step from `from` toward the nearest tile not in `stuck` (a wild monster's way out),
## over walkable tiles not in `blocked`, the first in direction order of the equally near; `from`
## itself when there is none. It searches only through tiles in `stuck`, so it stays small.
static func way_out(
	region: Region,
	stuck: Dictionary[Vector2i, bool],
	blocked: Dictionary[Vector2i, bool],
	from: Vector2i,
) -> Vector2i:
	var first: Dictionary[Vector2i, Vector2i] = { from: from }
	var open: Array[Vector2i] = [from]
	var next: int = 0
	while next < open.size():
		var current: Vector2i = open[next]
		next += 1
		for direction: Vector2i in Hex.DIRECTIONS:
			var tile: Vector2i = current + direction
			if first.has(tile) or blocked.has(tile) or not region.is_walkable(tile):
				continue
			first[tile] = tile if current == from else first[current]
			if not stuck.has(tile):
				return first[tile]
			open.append(tile)
	return from
