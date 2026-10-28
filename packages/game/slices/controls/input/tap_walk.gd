class_name TapWalk
extends RefCounted
## Walking to a tapped or clicked tile on one's own (#1508): the device side finds the way, and
## each tick gives that tick's move, as the stick would (#26); the simulation never holds the way.
## The way goes over walkable tiles only, round whatever stands still on them now (a wild monster,
## MovementFeature.is_occupied), fewest steps first, then the first in Hex.DIRECTIONS' order. A tile
## bare hands can harvest (#696) is walked onto, or next to when it can't be stood on (beside it
## where the harvest takes it, not a neighbour), and harvested on arrival with one interact press.
## Without such a way the tap does nothing. The walk ends on arrival, or as soon as its next tile is
## closed or the player is off the way (pushed, sent back).

## No tile: never a region's, whose tiles are near the origin.
const NO_TILE: Vector2i = Vector2i(-DataReader.MOST, -DataReader.MOST)

## Whether a walk is under way: the way still has steps, or the harvest is still to press.
var walking: bool = false
## The tile tapped since the last command, or NO_TILE.
var _tapped: Vector2i = NO_TILE
## Where the player stands on the way: where the walk began, then the last tile reached.
var _at: Vector2i = NO_TILE
## The tiles still to step onto, in order; empty when not walking.
var _way: Array[Vector2i] = []
## The tile to harvest on arrival, or NO_TILE when the walk only goes there.
var _harvest: Vector2i = NO_TILE


## Walks to `tile` from the next command on (`steer`).
func tap(tile: Vector2i) -> void:
	_tapped = tile


## Steers `given`, the next command of the player standing on `at`: the stick or a key moving in
## it stops the walk; else a new tap starts one, and a walk under way gives the move and, on
## arrival, the interact press.
func steer(given: Command, state: GameState, at: Vector2i) -> void:
	if given.move != Command.NO_MOVE:
		stop()
		return
	if _tapped != NO_TILE:
		var _aimed: bool = aim(state, at, _tapped)
	if walking:
		given.move = move(state, at)
		given.interact = harvests(state, at) or given.interact


## Starts a walk from `from` to `tile` on `state`'s region; returns whether one started. A walk
## under way ends either way: a new tap replaces it.
func aim(state: GameState, from: Vector2i, tile: Vector2i) -> bool:
	stop()
	var region: Region = state.region
	if not region.has_tile(tile):
		return false
	var harvestable: bool = TileKinds.harvested_by_hand(region.terrain[tile])
	var goals: Dictionary[Vector2i, bool] = {}
	if region.is_walkable(tile):
		goals[tile] = true
	elif harvestable:
		goals = _beside(region, tile)
	if goals.is_empty():
		return false
	var found: Array[Vector2i] = _way_to(state, from, goals)
	if found.is_empty() and not goals.has(from):
		return false
	_way = found
	_at = from
	_harvest = tile if harvestable else NO_TILE
	walking = true
	return true


## The move toward the next tile of the way from `at`, where the player stands (a direction index,
## or Command.NO_MOVE once there); ends the walk when the way is closed or left.
func move(state: GameState, at: Vector2i) -> int:
	if not _way.is_empty() and _way[0] == at:
		var _reached: Vector2i = _way.pop_front()
		_at = at
	elif at != _at:
		stop()
		return Command.NO_MOVE
	if _way.is_empty():
		return Command.NO_MOVE
	var step: int = Hex.DIRECTIONS.find(_way[0] - at)
	if step == -1 or not _is_open(state, _way[0]):
		stop()
		return Command.NO_MOVE
	return step


## Whether to press interact now: once, on arrival, and only while a harvest from `at` still takes
## the tapped tile (another player may have harvested it, and the press would take a neighbour). A
## walk with nothing to harvest ends on arrival.
func harvests(state: GameState, at: Vector2i) -> bool:
	if not walking or not _way.is_empty():
		return false
	var pressing: bool = _harvest != NO_TILE and _takes(state.region, at, _harvest)
	stop()
	return pressing


## Ends the walk, and drops a tap not yet walked.
func stop() -> void:
	_tapped = NO_TILE
	_way.clear()
	_harvest = NO_TILE
	_at = NO_TILE
	walking = false


## The tiles beside `tile` from which a harvest takes it (`_takes`), not another one beside them.
## None when every such tile takes another one:
## the tap walks nowhere then, rather than harvest a tile it wasn't on.
static func _beside(region: Region, tile: Vector2i) -> Dictionary[Vector2i, bool]:
	var taking: Dictionary[Vector2i, bool] = {}
	for direction: Vector2i in Hex.DIRECTIONS:
		if _takes(region, tile + direction, tile):
			taking[tile + direction] = true
	return taking


## Whether a harvest begun on `at` takes `tile`: it's the first tile bare hands can harvest of `at`
## and its neighbours in Hex.DIRECTIONS' order, as TileHarvestFeature.target_of picks it.
static func _takes(region: Region, at: Vector2i, tile: Vector2i) -> bool:
	var around: Array[Vector2i] = [at]
	for direction: Vector2i in Hex.DIRECTIONS:
		around.append(at + direction)
	for each: Vector2i in around:
		if region.has_tile(each) and TileKinds.harvested_by_hand(region.terrain[each]):
			return each == tile
	return false


## The way from `from` to the nearest of `goals`, without `from`; empty when none can be reached,
## or `from` is one.
func _way_to(
	state: GameState,
	from: Vector2i,
	goals: Dictionary[Vector2i, bool],
) -> Array[Vector2i]:
	var came_from: Dictionary[Vector2i, Vector2i] = { from: from }
	var open: Array[Vector2i] = [from]
	var next: int = 0
	var way: Array[Vector2i] = []
	if goals.has(from):
		return way
	while next < open.size():
		var current: Vector2i = open[next]
		next += 1
		for direction: Vector2i in Hex.DIRECTIONS:
			var tile: Vector2i = current + direction
			if came_from.has(tile) or not _is_open(state, tile):
				continue
			came_from[tile] = current
			if goals.has(tile):
				return _traced(came_from, tile)
			open.append(tile)
	return way


## The way that ends on `last`, back to where `came_from` began, without that tile.
static func _traced(came_from: Dictionary[Vector2i, Vector2i], last: Vector2i) -> Array[Vector2i]:
	var way: Array[Vector2i] = []
	var tile: Vector2i = last
	while came_from[tile] != tile:
		way.push_front(tile)
		tile = came_from[tile]
	return way


## Whether a walker can step onto `tile` now.
func _is_open(state: GameState, tile: Vector2i) -> bool:
	if not state.region.is_walkable(tile):
		return false
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	return movement == null or not movement.is_occupied(state, tile)
