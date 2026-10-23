class_name WildWay
extends RefCounted
## The way a wild monster finds when it walks somewhere of its own accord (#1259): breadth first
## over the ground it may step onto, up to REACH steps, so it walks round rocks, water and whoever
## stands in its way instead of stalling behind them. It searches only walkable tiles in neither
## `blocked` (the trail and every tile something stands on) nor `stuck` (no ring could enclose it
## there, RingableGround), the ground WildMonsterFeature lets it step onto, so every way it finds is
## one it can walk and stays catchable. Of the equally good tiles it takes the one fewest steps
## away, then the first in direction order, so the same ground always gives the same way. Made for
## the ground of one tick, it finds the ways of any monster on it.

## How many steps ahead a wild monster looks for its way. A placeholder to tune (#960).
const REACH: int = 10

var _region: Region
var _stuck: Dictionary[Vector2i, bool]
var _blocked: Dictionary[Vector2i, bool]


## The ground of `region` a wild monster may step onto: walkable, in neither `stuck` nor `blocked`.
func _init(
	region: Region,
	stuck: Dictionary[Vector2i, bool],
	blocked: Dictionary[Vector2i, bool],
) -> void:
	_region = region
	_stuck = stuck
	_blocked = blocked


## The first step from `from` toward the tile within REACH steps nearest to `goal`, if that's nearer
## than `from`; `from` itself otherwise. A chaser walks round a wall between it and its goal.
func toward(from: Vector2i, goal: Vector2i) -> Vector2i:
	return _search(from, goal, false)


## The first step from `from` away from `threat`, toward the tile furthest from it it can reach
## within REACH steps that each take it further away: a fleeing monster never steps nearer its
## threat nor sideways, and of its ways away takes the one that runs longest, not one into a dead
## end. `from` itself when no step takes it further away: it's cornered.
func away(from: Vector2i, threat: Vector2i) -> Vector2i:
	return _search(from, threat, true)


## The tile within REACH steps of `from` a wild monster reaches first where `wanted` (a
## `func(tile: Vector2i) -> bool`) holds: fewest steps away, then first in direction order, so a
## forager goes for the food it can walk to soonest, not the food behind a wall (#1291). `from`
## itself when no such tile is within reach.
func nearest(from: Vector2i, wanted: Callable) -> Vector2i:
	var reached: Dictionary[Vector2i, int] = { from: 0 }
	var queue: Array[Vector2i] = [from]
	var index: int = 0
	while index < queue.size():
		var at: Vector2i = queue[index]
		index += 1
		if reached[at] == REACH:
			continue
		for direction: Vector2i in Hex.DIRECTIONS:
			var tile: Vector2i = at + direction
			if reached.has(tile) or not _is_open(tile):
				continue
			if wanted.call(tile):
				return tile
			reached[tile] = reached[at] + 1
			queue.append(tile)
	return from


## Whether a wild monster may step onto `tile`.
func _is_open(tile: Vector2i) -> bool:
	return not (_blocked.has(tile) or _stuck.has(tile)) and _region.is_walkable(tile)


## The breadth-first search both ways share: toward `goal` it keeps the reached tile nearest to it,
## `fleeing` from it it only steps further from it and keeps the one furthest.
func _search(from: Vector2i, goal: Vector2i, fleeing: bool) -> Vector2i:
	var first: Dictionary[Vector2i, Vector2i] = { from: from }
	var steps: Dictionary[Vector2i, int] = { from: 0 }
	var open: Array[Vector2i] = [from]
	var best: Vector2i = from
	var next: int = 0
	while next < open.size():
		var current: Vector2i = open[next]
		next += 1
		if steps[current] == REACH:
			continue
		for direction: Vector2i in Hex.DIRECTIONS:
			var tile: Vector2i = current + direction
			if first.has(tile) or not _is_open(tile):
				continue
			var gap: int = Hex.distance(tile, goal)
			if fleeing and gap <= Hex.distance(current, goal):
				continue
			first[tile] = tile if current == from else first[current]
			steps[tile] = steps[current] + 1
			open.append(tile)
			# Strictly better only: of the equally good, the one found first stays.
			var best_gap: int = Hex.distance(best, goal)
			if (gap > best_gap) if fleeing else (gap < best_gap):
				best = tile
	return first[best]
