class_name FogInputs
extends RefCounted
## What FogView last worked its tiles' targets out from (#1361): every ally's sight, whether the
## fog is on, the revealed tiles and where the neighbours lie. Copies, so a change made in place is
## noticed too. While none of it changes, no tile's target can, and the view skips working them out.

var _sight: Dictionary[int, Array] = {}
var _enabled: bool = true
var _revealed: Array[Vector2i] = []
var _shifts: Dictionary[String, Vector2i] = {}
var _next_door: bool = false


## Whether `fog` or `next_door` (null when none are drawn) changed since `remember`.
func changed(fog: FogFeature, next_door: NeighbourView) -> bool:
	if fog.enabled != _enabled or fog.visible != _sight or fog.revealed != _revealed:
		return true
	return next_door_moved(next_door)


## Whether the neighbours drawn (`next_door`, null when none are) appeared, went or moved since
## `remember`: their tiles then all have to be drawn again.
func next_door_moved(next_door: NeighbourView) -> bool:
	if (next_door != null) != _next_door:
		return true
	return next_door != null and next_door.shifts != _shifts


## Remembers `fog` and `next_door` as they are now.
func remember(fog: FogFeature, next_door: NeighbourView) -> void:
	_enabled = fog.enabled
	_sight.clear()
	for slot: int in fog.visible:
		_sight[slot] = fog.visible[slot].duplicate()
	_revealed.assign(fog.revealed)
	_shifts.clear()
	_next_door = next_door != null
	if next_door != null:
		_shifts.assign(next_door.shifts)
