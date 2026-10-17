class_name WorldLayout
extends RefCounted
## Where each instance of the world's web lies in world space (#187, #282), so that walking out of
## one exit lands on the tile right next to it in the next, and the views can place neighbouring
## instances side by side. Worked out once, from the world's starting instance and the regions of
## its seed. It keeps only what it worked out; the world is handed in, so the two don't hold each
## other.

## Each reachable instance's place in the world, worked out once (`offset`).
var _offsets: Dictionary[String, Vector2i] = {}
## Each blueprint's region for the world's seed, arranged once for the layout.
var _regions: Dictionary[String, Region] = {}
## The first problem laying out the web met, or "".
var _layout_problem: String = ""


## Where tile (0, 0) of the instance `instance_name` lies in the world (#187): every instance of
## the web has a fixed place, so walking out of one exit lands on the tile right next to it in the
## next. Worked out from the web outward from the starting instance: if this instance's exit on `a`
## leads out side `d` into one whose way back is `b`, that one lies at this one's offset plus
## `a + direction(d) - b`. The simulation keeps each instance's own coordinates; views add this.
## Vector2i.ZERO for an instance the web doesn't reach.
func offset(world: World, instance_name: String) -> Vector2i:
	if _offsets.is_empty():
		_lay_out(world)
	return _offsets.get(instance_name, Vector2i.ZERO)


## Why the web can't be laid out as one world, or "" (#187): an exit whose target has no way back to
## it, a second way into an instance that doesn't fit where the first placed it, or two instances
## that would lie on the same tile. The world flow checks it over many seeds, since arranged
## regions vary with them.
func problem(world: World) -> String:
	if _offsets.is_empty():
		_lay_out(world)
	if not _layout_problem.is_empty():
		return _layout_problem
	var taken: Dictionary[Vector2i, String] = {}
	var names: Array[String] = []
	names.assign(_offsets.keys())
	names.sort()
	for instance_name: String in names:
		for tile: Vector2i in region(world, instance_name).sorted_tiles():
			var placed: Vector2i = tile + _offsets[instance_name]
			if taken.has(placed):
				return "%s and %s would overlap on %s" % [taken[placed], instance_name, placed]
			taken[placed] = instance_name
	return ""


## Places every instance the web reaches, breadth first from the starting instance, checking every
## exit against the places already given; the first exit that doesn't fit is `_layout_problem`.
func _lay_out(world: World) -> void:
	_offsets[world.start_name] = Vector2i.ZERO
	var queue: Array[String] = [world.start_name]
	while not queue.is_empty():
		var from: String = queue.pop_front()
		var region: Region = region(world, from)
		for i: int in region.exits.size():
			var target: String = region.exit_blueprints[i]
			var back: Vector3i = _way_back(world, target, from)
			var exit: Vector3i = region.exits[i]
			var outside: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
			var placed: Vector2i = _offsets[from] + outside - Vector2i(back.x, back.y)
			if back.z < 0:
				_note("%s's exit to %s has no way back" % [from, target])
			elif not _offsets.has(target):
				_offsets[target] = placed
				queue.append(target)
			elif _offsets[target] != placed:
				_note("%s doesn't fit where %s's exit leads into it" % [target, from])


## The exit in `instance_name` that leads back to `from` as (q, r, side), or z = -1 when there's
## none.
func _way_back(world: World, instance_name: String, from: String) -> Vector3i:
	var region: Region = region(world, instance_name)
	for i: int in region.exits.size():
		if region.exit_blueprints[i] == from:
			return region.exits[i]
	return Vector3i(0, 0, -1)


## The region of the blueprint `instance_name` for the world's seed, arranged once.
func region(world: World, instance_name: String) -> Region:
	if not _regions.has(instance_name):
		_regions[instance_name] = InstanceBlueprints.region_of(
			instance_name,
			world.seed_for(instance_name),
		)
	return _regions[instance_name]


## Keeps the first layout problem found.
func _note(found: String) -> void:
	if _layout_problem.is_empty():
		_layout_problem = found


## Forgets the region of `instance_name`, arranged anew once it's purged (#212), and every place
## worked out from it: the layout is worked out again on the next ask.
func forget(instance_name: String) -> void:
	var _arranged: bool = _regions.erase(instance_name)
	_offsets.clear()
	_layout_problem = ""
