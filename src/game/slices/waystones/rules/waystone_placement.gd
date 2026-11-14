class_name WaystonePlacement
extends RefCounted
## Where an instance's region gets its standing stone (#1872): every instance a realm holds has at
## least one waystone SAFE_DISTANCE tiles (hex distance) from every wild monster's spot when it
## loads, in its clearing (#2323). Placement only: roaming monsters may come closer later. The
## stone stands on a tile players walk to that far from every wild monster, in the open (the most
## rings of walkable tiles around it, up to OPEN_RINGS, so it never stands in a corner), then the
## farthest from every wild monster, then by the tile's order; never on an exit, a start or a
## placed thing, and never where it would cut the tiles players walk to apart. It depends only on
## the region, so every seed's arrangement gets its own.

## How many tiles (hex distance) the placed stone keeps at least from every wild monster's spot.
const SAFE_DISTANCE: int = 15
## How many rings of walkable tiles around a tile count at most for how open it stands.
const OPEN_RINGS: int = 3


## Makes one tile of `region` a waystone, unless it already has one SAFE_DISTANCE tiles from every
## wild monster, beside a tile players walk to from the first start, or has no tile that far.
static func place(region: Region) -> void:
	if not region.problem.is_empty() or region.starts.is_empty():
		return
	var walked: Array[Vector2i] = region.reachable(region.starts[0])
	if _has_safe_stone(region, walked):
		return
	var kept: Dictionary[Vector2i, bool] = _kept_free(region)
	var candidates: Array[Vector2i] = []
	var reach: Dictionary[Vector2i, int] = {}
	var open: Dictionary[Vector2i, int] = {}
	for tile: Vector2i in walked:
		var far: int = _nearest_monster(region, tile)
		if far >= SAFE_DISTANCE and not kept.has(tile):
			candidates.append(tile)
			reach[tile] = far
			open[tile] = _open_rings(region, tile)
	candidates.sort_custom(_better.bind(open, reach))
	for tile: Vector2i in candidates:
		var kind: String = region.terrain[tile]
		var overridden: bool = region.walkable_overrides.has(tile)
		var walkable: bool = region.walkable_overrides.get(tile, false)
		var _changed: bool = region.change(tile, WaystoneFeature.KIND)
		if region.reachable(region.starts[0]).size() == walked.size() - 1:
			return
		region.terrain[tile] = kind
		if overridden:
			region.walkable_overrides[tile] = walkable


## Whether the stone stands better on `a` than on `b`: more `open` rings around it, then farther
## from every wild monster (`reach`), then first in the tiles' order.
static func _better(
	a: Vector2i,
	b: Vector2i,
	open: Dictionary[Vector2i, int],
	reach: Dictionary[Vector2i, int],
) -> bool:
	if open[a] != open[b]:
		return open[a] > open[b]
	if reach[a] != reach[b]:
		return reach[a] > reach[b]
	return a < b


## Whether `region` has a waystone SAFE_DISTANCE tiles from every wild monster, beside one of the
## `walked` tiles.
static func _has_safe_stone(region: Region, walked: Array[Vector2i]) -> bool:
	for tile: Vector2i in region.sorted_tiles():
		if region.terrain[tile] != WaystoneFeature.KIND:
			continue
		if _nearest_monster(region, tile) < SAFE_DISTANCE:
			continue
		for direction: Vector2i in Hex.DIRECTIONS:
			if walked.has(tile + direction):
				return true
	return false


## The tiles no stone may stand on: the exits, the starts and every placed thing.
static func _kept_free(region: Region) -> Dictionary[Vector2i, bool]:
	var kept: Dictionary[Vector2i, bool] = {}
	for exit: Vector3i in region.exits:
		kept[Vector2i(exit.x, exit.y)] = true
	for tile: Vector2i in region.starts:
		kept[tile] = true
	for tile: Vector2i in region.wild_monsters:
		kept[tile] = true
	for kind: String in region.placements:
		for tile: Vector2i in region.placed(kind):
			kept[tile] = true
	return kept


## How many whole rings of walkable tiles stand around `tile` in `region`, up to OPEN_RINGS.
static func _open_rings(region: Region, tile: Vector2i) -> int:
	for rings: int in OPEN_RINGS:
		for near: Vector2i in Hex.ring(rings + 1, tile):
			if not region.is_walkable(near):
				return rings
	return OPEN_RINGS


## How many tiles `tile` is from the nearest wild monster's spot in `region`, or SAFE_DISTANCE for
## a region without any.
static func _nearest_monster(region: Region, tile: Vector2i) -> int:
	var nearest: int = SAFE_DISTANCE
	if region.wild_monsters.is_empty():
		return nearest
	nearest = Hex.distance(tile, region.wild_monsters[0])
	for spot: Vector2i in region.wild_monsters:
		nearest = mini(nearest, Hex.distance(tile, spot))
	return nearest
