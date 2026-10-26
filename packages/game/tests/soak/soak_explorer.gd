class_name SoakExplorer
extends CommandSource
## The soak test's player (#1311). It stands still on its first tile, its home, until told to
## `explore`; then it walks slot 0 to the nearest tile of its instance it hasn't stood on yet, by a
## shortest walk over ground players can walk onto, and on to the next once there, so the walk keeps
## exploring new ground the way a player roaming the world does. It never steps off the region, so
## it stays in the instance it starts in. A target it can't reach for a while (a sleeping wild
## monster in the way) counts as visited, so the walk never stalls. Once no tile is left to explore
## it walks back home and stands there again (`is_home`). It measures its own time, which the soak
## leaves out of the frames it measures.

## Ticks without reaching a new tile after which the walk gives its target up.
const STUCK_TICKS: int = MovementFeature.MOVE_TICKS * 4

## Microseconds spent choosing moves since the soak last reset it.
var spent_usec: int = 0
## Every tile stood on or given up.
var visited: Dictionary[Vector2i, bool] = {}
## Every tile stood on: what the walk explored.
var stood_on: Dictionary[Vector2i, bool] = {}
var _home: Vector2i = Vector2i.ZERO
var _homed: bool = false
var _exploring: bool = false
var _explored: bool = false
var _back: bool = false
var _target: Vector2i = Vector2i.ZERO
var _tile: Vector2i = Vector2i.ZERO
var _stuck: int = 0


## Starts the walk.
func explore() -> void:
	_exploring = true


## Whether the walk explored its instance and is back home.
func is_home() -> bool:
	return _back


func poll(schedule: CommandSchedule, tick: int, state: GameState) -> void:
	if schedule.has(tick + schedule.delay, slot):
		return
	var started: int = Time.get_ticks_usec()
	schedule.put(tick + schedule.delay, slot, Command.new(_move(state)))
	spent_usec += Time.get_ticks_usec() - started


## The direction to step in next, or NO_MOVE to stand.
func _move(state: GameState) -> int:
	var player: Entity = state.player(slot)
	if player == null:
		return Command.NO_MOVE
	if not _homed:
		_homed = true
		_home = player.tile
	if not _exploring or _back:
		return Command.NO_MOVE
	visited[player.tile] = true
	stood_on[player.tile] = true
	if player.tile != _tile:
		_tile = player.tile
		_stuck = 0
	else:
		_stuck += 1
	if _stuck > STUCK_TICKS:
		visited[_target] = true
		_stuck = 0
	# The tile under the player is already the one a step under way leads to, and a command only
	# starts the next step once it's done, so the way on is always measured from there.
	if not _explored:
		var onward: int = _first_step(state, player.tile, _unvisited)
		if onward != Command.NO_MOVE:
			return onward
		_explored = true
	if player.tile == _home:
		_back = true
		return Command.NO_MOVE
	return _first_step(state, player.tile, _at_home)


func _unvisited(tile: Vector2i) -> bool:
	return not visited.has(tile)


func _at_home(tile: Vector2i) -> bool:
	return tile == _home


## The first step of a shortest walk from `from` to the nearest tile `wanted` accepts, or NO_MOVE
## when none is in reach (or `from` itself is one).
func _first_step(state: GameState, from: Vector2i, wanted: Callable) -> int:
	var first: Dictionary[Vector2i, int] = { from: Command.NO_MOVE }
	var open: Array[Vector2i] = [from]
	while not open.is_empty():
		var current: Vector2i = open.pop_front()
		if wanted.call(current):
			_target = current
			return first[current]
		for direction: int in Hex.DIRECTIONS.size():
			var next: Vector2i = current + Hex.DIRECTIONS[direction]
			if first.has(next) or not FlowSteps.walkable_for_players(state, next):
				continue
			first[next] = direction if current == from else first[current]
			open.append(next)
	return Command.NO_MOVE
