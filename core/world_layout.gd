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
		for tile: Vector2i in region_for(world, instance_name).sorted_tiles():
			var placed: Vector2i = tile + _offsets[instance_name]
			if taken.has(placed):
				return "%s and %s would overlap on %s" % [taken[placed], instance_name, placed]
			taken[placed] = instance_name
	return ""


## Places every instance the web reaches, breadth first from the starting instance, checking every
## exit against the places already given; the first exit that doesn't fit is `_layout_problem`.
## An exit may be many tiles wide (#689): the instance it leads into lies where every one of them
## lands on a way back.
func _lay_out(world: World) -> void:
	_offsets[world.start_name] = Vector2i.ZERO
	var queue: Array[String] = [world.start_name]
	while not queue.is_empty():
		var from: String = queue.pop_front()
		var region: Region = region_for(world, from)
		var targets: Array[String] = []
		for target: String in region.exit_blueprints:
			if not targets.has(target):
				targets.append(target)
		for target: String in targets:
			var back: Region = region_for(world, target)
			var placed: Array[Vector2i] = _places(region, from, back, target)
			if placed.is_empty():
				_note("%s's exit to %s has no way back lined up with it" % [from, target])
			elif not _offsets.has(target):
				_offsets[target] = _offsets[from] + placed[0]
				queue.append(target)
			elif not placed.has(_offsets[target] - _offsets[from]):
				_note("%s doesn't fit where %s's exit leads into it" % [target, from])


## Every shift from the instance `from`, with `region`, to the instance `target`, with `back`, that
## lands each of the exits to it on a way back facing it, in a fixed order; none when there's no
## such shift.
static func _places(region: Region, from: String, back: Region, target: String) -> Array[Vector2i]:
	var shifts: Array[Vector2i] = []
	var first: int = region.exit_blueprints.find(target)
	var exit: Vector3i = region.exits[first]
	for i: int in back.exits.size():
		var way: Vector3i = back.exits[i]
		var shift: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
		shift -= Vector2i(way.x, way.y)
		if back.exit_blueprints[i] == from and _lands(region, from, back, target, shift):
			shifts.append(shift)
	return shifts


## Whether every exit of `region` (the instance `from`'s) to `target` lands, `shift` away, on an
## exit of `back` (the target's region) leading back to `from` out the opposite side.
static func _lands(
	region: Region,
	from: String,
	back: Region,
	target: String,
	shift: Vector2i,
) -> bool:
	for i: int in region.exits.size():
		var exit: Vector3i = region.exits[i]
		var tile: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z] - shift
		var side: int = posmod(exit.z + 3, Hex.DIRECTIONS.size())
		var way: int = back.exits.find(Vector3i(tile.x, tile.y, side))
		var lands: bool = way >= 0 and back.exit_blueprints[way] == from
		if region.exit_blueprints[i] == target and not lands:
			return false
	return true


## The region of the blueprint `instance_name` for the world's seed and its variant there (#529),
## arranged once.
func region_for(world: World, instance_name: String) -> Region:
	if not _regions.has(instance_name):
		_regions[instance_name] = world.source.region_of(
			instance_name,
			world.seed_for(instance_name),
			world.variant_of(instance_name),
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
