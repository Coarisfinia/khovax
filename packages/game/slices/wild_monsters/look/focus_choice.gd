class_name FocusChoice
extends RefCounted
## Which wild monster the local player focuses (#436): the ones near the player, nearest first (ties
## by id), stepped through with focus_next and focus_previous. A focus that's gone or out of range
## is
## dropped. The simulation checks the focus again before striking it.

## How far from the player a wild monster can be focused, in tiles.
const RANGE: int = 6


## The focus after stepping `steps` from `focus` among the wild monsters within RANGE of `tile` in
## `state`, or Command.NO_FOCUS when there are none.
static func stepped(state: GameState, tile: Vector2i, focus: int, steps: int) -> int:
	var near: Array[int] = nearest(state, tile)
	if near.is_empty():
		return Command.NO_FOCUS
	var at: int = near.find(focus)
	if steps == 0:
		return focus if at >= 0 else Command.NO_FOCUS
	# With nothing focused, stepping starts just before the nearest (forward) or after the last.
	if at < 0:
		at = -1 if steps > 0 else near.size()
	return near[posmod(at + steps, near.size())]


## The wild monsters within RANGE of `tile`, not hiding, nearest first, ties by id.
static func nearest(state: GameState, tile: Vector2i) -> Array[int]:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var near: Array[int] = []
	if wild == null:
		return near
	for monster: int in wild.monsters:
		var hidden: bool = hiding != null and hiding.is_hidden(monster)
		if not hidden and Hex.distance(state.entity(monster).tile, tile) <= RANGE:
			near.append(monster)
	near.sort_custom(func(a: int, b: int) -> bool: return _closer(state, tile, a, b))
	return near


static func _closer(state: GameState, tile: Vector2i, a: int, b: int) -> bool:
	var to_a: int = Hex.distance(state.entity(a).tile, tile)
	var to_b: int = Hex.distance(state.entity(b).tile, tile)
	return to_a < to_b or (to_a == to_b and a < b)
