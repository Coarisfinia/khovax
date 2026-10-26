class_name FogInputs
extends RefCounted
## What FogView last worked its tiles' targets out from (#1361): every ally's sight, whether the
## fog is on, the revealed tiles, how much of the instance shown is remembered as explored, and
## where the neighbours lie and whether they were drawn anew. Copies, so a change made in place is
## noticed too. While none of it changes, no tile's target can, and the view skips working them out.

## How many times the targets were worked out (`remember`): each time, a tile's brightness can
## change and even arrive within that frame, outside FogView.moving (#1386).
var times: int = 0
var _sight: Dictionary[int, Array] = {}
var _enabled: bool = true
var _revealed: Array[Vector2i] = []
var _shifts: Dictionary[String, Vector2i] = {}
var _next_door: bool = false
var _rebuilds: int = 0
## How many tiles of the instance shown were remembered as explored. Only sight adds to it while
## the view draws, so another count means it was remembered from elsewhere (a resumed save).
var _explored: int = 0


## Whether `fog`, the `explored` count or `next_door` (null when none are drawn) changed since
## `remember`.
func changed(fog: FogFeature, explored: int, next_door: NeighbourView) -> bool:
	if fog.enabled != _enabled or fog.visible != _sight or fog.revealed != _revealed:
		return true
	if explored != _explored:
		return true
	return next_door_moved(next_door)


## Whether the neighbours drawn (`next_door`, null when none are) appeared, went, moved or were
## drawn anew since `remember`: their tiles then all have to be drawn again.
func next_door_moved(next_door: NeighbourView) -> bool:
	if (next_door != null) != _next_door:
		return true
	if next_door == null:
		return false
	return next_door.shifts != _shifts or next_door.rebuilds != _rebuilds


## Remembers `fog`, the `explored` count and `next_door` as they are now.
func remember(fog: FogFeature, explored: int, next_door: NeighbourView) -> void:
	times += 1
	_enabled = fog.enabled
	_explored = explored
	_sight.clear()
	for slot: int in fog.visible:
		_sight[slot] = fog.visible[slot].duplicate()
	_revealed.assign(fog.revealed)
	_shifts.clear()
	_next_door = next_door != null
	if next_door != null:
		_shifts.assign(next_door.shifts)
		_rebuilds = next_door.rebuilds
