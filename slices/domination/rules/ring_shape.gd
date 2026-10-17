class_name RingShape
extends RefCounted
## The shape of a ring a trail closes (#20, #219): which tiles it encloses, its wall and the wall's
## segments, and whether a step can have closed one at all. Plain geometry over a region and a
## trail, no state: DominationFeature asks it when it dominates and seals.


## The ring's wall around the monsters on `spots`: every trail tile next to a tile enclosed with
## them, found by a flood from their spots that stops at the trail. Sorted.
static func wall_around(region: Region, trail: Trail, spots: Array[Vector2i]) -> Array[Vector2i]:
	var seen: Dictionary[Vector2i, bool] = {}
	var wall: Dictionary[Vector2i, bool] = {}
	var open: Array[Vector2i] = spots.duplicate()
	for spot: Vector2i in spots:
		seen[spot] = true
	while not open.is_empty():
		var current: Vector2i = open.pop_back()
		for direction: Vector2i in Hex.DIRECTIONS:
			var next: Vector2i = current + direction
			if trail.tiles.has(next):
				wall[next] = true
			elif region.has_tile(next) and not seen.has(next):
				seen[next] = true
				open.append(next)
	var sorted: Array[Vector2i] = []
	sorted.assign(wall.keys())
	sorted.sort()
	return sorted


## The index of the wall segment nearest to `spot` by hex distance; of equally near ones, the
## first in the wall's order.
static func nearest(walls: Array[Vector2i], spot: Vector2i) -> int:
	var best: int = 0
	for i: int in walls.size():
		if Hex.distance(walls[i], spot) < Hex.distance(walls[best], spot):
			best = i
	return best


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


## The region's edge: every tile next to where the region ends, in the region's tile order.
static func edge_of(region: Region) -> Array[Vector2i]:
	var edge: Array[Vector2i] = []
	for tile: Vector2i in region.sorted_tiles():
		if on_edge(region, tile):
			edge.append(tile)
	return edge


## Whether `tile` lies next to where the region ends.
static func on_edge(region: Region, tile: Vector2i) -> bool:
	for direction: Vector2i in Hex.DIRECTIONS:
		if not region.has_tile(tile + direction):
			return true
	return false


## Whether the step can have closed a ring: only if the tile walked onto touches the trail
## somewhere besides the tile it came from. A step that only extends a line, touching nothing
## else, seals no pocket off, so the flood can be skipped.
static func may_close(trail: Trail, grew: TrailGrew) -> bool:
	for direction: Vector2i in Hex.DIRECTIONS:
		var next: Vector2i = grew.to + direction
		if next != grew.from and trail.tiles.has(next):
			return true
	return false
