class_name TourExplorer
extends SoakExplorer
## The soak test's player on a tour of the world (#2084): it stands on its home tile until told to
## `explore`, then walks out through the exits into every instance it can reach, one after another
## and deeper first, back the way it came once an instance has no new one beside it, the way a
## player roams the world's instances, and once home again onto its home tile (`is_home`). Each
## instance it passes through stays loaded behind it, as in play. An instance it can't walk to (a
## sealed passage) counts as seen.

## The driver, which says which instance the player is in.
var driver: Session
## Every instance it has been in, or given up on.
var seen: Dictionary[String, bool] = {}
## The instances on the way from home to the one it is in, home first.
var trail: Array[String] = []
## Every instance it has walked into, home included.
var reached: Dictionary[String, bool] = {}
## The instance it walks to next, or "".
var _next: String = ""
var _in: String = ""


func _walk(state: GameState, player: Entity) -> int:
	_arrive(driver.local_instance_name())
	while true:
		if _next.is_empty():
			_next = _onward(state)
		if _next.is_empty():
			if player.tile == _home:
				_back = true
				return Command.NO_MOVE
			return _first_step(state, player.tile, _at_home)
		var out: int = _out_towards(state, player.tile)
		if out != Command.NO_MOVE:
			return out
		var step: int = _first_step(state, player.tile, _on_exit.bind(state))
		if step != Command.NO_MOVE:
			return step
		if trail.size() >= 2 and _next == trail[-2]:
			# No way back just now (a wild monster in it): wait for one, never give the way home up.
			return Command.NO_MOVE
		# No way to that exit: count the instance behind it as seen.
		seen[_next] = true
		_next = ""
	return Command.NO_MOVE


## Notes walking into `instance_name`: one more on the trail, or one fewer when it walked back.
func _arrive(instance_name: String) -> void:
	if instance_name == _in:
		return
	_in = instance_name
	reached[instance_name] = true
	_next = ""
	seen[instance_name] = true
	if trail.size() >= 2 and trail[-2] == instance_name:
		trail.pop_back()
	else:
		trail.append(instance_name)


## The instance to walk into next from `state`: one beside it not seen yet, else the one it came
## from; "" at home with every instance seen.
func _onward(state: GameState) -> String:
	for target: String in state.region.exit_blueprints:
		if not seen.has(target):
			return target
	return trail[-2] if trail.size() >= 2 else ""


## The side to walk out of on `tile` towards `_next`, or NO_MOVE when it isn't an exit there.
func _out_towards(state: GameState, tile: Vector2i) -> int:
	for i: int in state.region.exits.size():
		var exit: Vector3i = state.region.exits[i]
		if state.region.exit_blueprints[i] == _next and Vector2i(exit.x, exit.y) == tile:
			return exit.z
	return Command.NO_MOVE


func _on_exit(tile: Vector2i, state: GameState) -> bool:
	return _out_towards(state, tile) != Command.NO_MOVE
