class_name WorldLayout
extends RefCounted
## Where each instance of the world's web lies in world space (#187, #282), so that walking out of
## one exit lands on the tile right next to it in the next, and the views can place neighbouring
## instances side by side. Worked out lazily (#1011), outward from the instances already placed,
## starting with the loaded ones, where the players are: a world never arranges the regions far
## from them just to place what's near. The web is consistent (the world flow checks it over many
## seeds), so the order places each instance where a layout of the whole web would. It keeps only
## what it worked out; the world is handed in, so the two don't hold each other.

## Each instance placed so far: where it lies in the world (`offset`).
var _offsets: Dictionary[String, Vector2i] = {}
## The placed instances whose exits haven't been followed yet, in the order they were placed.
var _unfollowed: Array[String] = []
## Each blueprint's region for the world's seed, arranged once for the layout.
var _regions: Dictionary[String, Region] = {}


## Where tile (0, 0) of the instance `instance_name` lies in the world (#187): every instance of
## the web has a fixed place, so walking out of one exit lands on the tile right next to it in the
## next. The starting instance lies at the origin; if a placed instance's exit on `a` leads out
## side `d` into one whose way back is `b`, that one lies at the placed one's offset plus
## `a + direction(d) - b`. Exits are followed until this instance is placed: first those of the
## loaded instances, in name order, then outward from the start, breadth first. The simulation
## keeps each instance's own coordinates; views add this. Vector2i.ZERO for an instance the web
## doesn't reach.
func offset(world: World, instance_name: String) -> Vector2i:
	if _offsets.is_empty():
		_offsets[world.start_name] = Vector2i.ZERO
		_unfollowed.append(world.start_name)
	while not _offsets.has(instance_name) and not _unfollowed.is_empty():
		_follow(world, _next_to_follow(world))
	return _offsets.get(instance_name, Vector2i.ZERO)


## Places `instance_name`, then every instance its exits lead to, from it: the ones the world hands
## it the ground of when it loads, so a walk outward places each next one from the last.
func place_around(world: World, instance_name: String) -> void:
	var _placed: Vector2i = offset(world, instance_name)
	if _unfollowed.has(instance_name):
		_follow(world, instance_name)


## The placed instance whose exits to follow next: a loaded one's, in name order, else the first
## placed.
func _next_to_follow(world: World) -> String:
	for loaded: String in world.sorted_names():
		if _unfollowed.has(loaded):
			return loaded
	return _unfollowed[0]


## Places every instance the exits of the placed instance `from` lead to that isn't placed yet. An
## exit may be many tiles wide (#689): the instance it leads into lies where every one of them lands
## on a way back. One with no way back lined up stays unplaced from here; the world flow checks
## that the web has none.
func _follow(world: World, from: String) -> void:
	_unfollowed.erase(from)
	var region: Region = region_for(world, from)
	for target: String in region.exit_blueprints:
		if _offsets.has(target):
			continue
		var placed: Array[Vector2i] = places(region, from, region_for(world, target), target)
		if not placed.is_empty():
			_offsets[target] = _offsets[from] + placed[0]
			_unfollowed.append(target)


## Every shift from the instance `from`, with `region`, to the instance `target`, with `back`, that
## lands each of the exits to it on a way back facing it, in a fixed order; none when there's no
## such shift. The world flow lays out the whole web with it to check it.
static func places(region: Region, from: String, back: Region, target: String) -> Array[Vector2i]:
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
			WorldFlags.variant_of(world, instance_name),
		)
	return _regions[instance_name]


## Forgets the region of `instance_name`, arranged anew once it's purged (#212), and every place
## worked out from it: the layout is worked out again as it's asked.
func forget(instance_name: String) -> void:
	var _arranged: bool = _regions.erase(instance_name)
	_offsets.clear()
	_unfollowed.clear()
