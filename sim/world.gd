class_name World
extends RefCounted
## The world (#139, #148): every instance it has loaded, by blueprint name, each a GameState of
## its own. Each tick it steps every instance a player is in, in name order, and leaves the others
## loaded but still, until one has been left behind for PURGE_TICKS: then it is purged (#212).
## Every instance's seed comes from the world's seed, its name and its generation, which goes up
## with each purge, so the same world loads the same instance the same way however and whenever
## it's reached, and a purged one comes back arranged anew. Players walk from one instance into
## the next through exits (#154). Deterministic, like everything in sim/.

## How long an instance nobody is in stays loaded (#212): an hour of play, counted in the world's
## ticks, which only pass while the game is played, never while it's closed.
const PURGE_TICKS: int = 60 * 60 * Simulation.TICKS_PER_SECOND

## The world's seed, which every instance's own seed is drawn from.
var world_seed: int = 0
## Ticks the world has run. An instance nobody is in doesn't step, so its own tick can lag behind.
var tick: int = 0
## Every loaded instance, by blueprint name.
var instances: Dictionary[String, GameState] = {}
## Why the world couldn't be set up, or "" when it could.
var problem: String = ""
## The blueprint the world starts in: the origin of the world's layout (#187). Never purged.
var start_name: String = ""
## How often each blueprint's instance has been purged, by name; none for one never purged.
var generations: Dictionary[String, int] = {}
## The world tick each loaded instance nobody is in was left behind (or loaded empty), by name.
var left_at: Dictionary[String, int] = {}
## Each reachable instance's place in the world, worked out once (`offset`).
var _offsets: Dictionary[String, Vector2i] = {}
## Each blueprint's region for the world's seed, arranged once for the layout.
var _regions: Dictionary[String, Region] = {}
## The first problem laying out the web met, or "".
var _layout_problem: String = ""


## A world that starts in the blueprint `start` with `players` players in it; with no `start`, an
## empty one, which only a refused save gives (`WorldData.to_world`).
func _init(seed_value: int, start: String, players: int = 1) -> void:
	world_seed = seed_value
	start_name = start
	if start.is_empty():
		return
	var first: GameState = InstanceBlueprints.create(start, seed_for(start), players)
	if first == null:
		problem = "the starting instance %s doesn't load" % start
		return
	instances[start] = first


## The seed of the instance loaded from the blueprint `instance_name` at its current generation:
## drawn from the world's seed, with the name as the stream. Generation n takes the stream's next
## draw after n purges, so generation 0 keeps the first draw, the seed every instance had before
## purging.
func seed_for(instance_name: String) -> int:
	var stream: Rng = Rng.new(world_seed, name_code(instance_name))
	var drawn: int = stream.next_u32()
	for _purged: int in generation(instance_name):
		drawn = stream.next_u32()
	return drawn


## How often the instance of `instance_name` has been purged (#212).
func generation(instance_name: String) -> int:
	return generations.get(instance_name, 0)


## The instance loaded from `instance_name`, loading it with nobody in it the first time, or null
## when it can't load.
func instance(instance_name: String) -> GameState:
	if not instances.has(instance_name):
		var loaded: GameState = InstanceBlueprints.create(instance_name, seed_for(instance_name), 0)
		if loaded == null:
			return null
		instances[instance_name] = loaded
		left_at[instance_name] = tick
	return instances[instance_name]


## Where tile (0, 0) of the instance `instance_name` lies in the world (#187): every instance of
## the web has a fixed place, so walking out of one exit lands on the tile right next to it in the
## next. Worked out from the web outward from the starting instance: if this instance's exit on `a`
## leads out side `d` into one whose way back is `b`, that one lies at this one's offset plus
## `a + direction(d) - b`. The simulation keeps each instance's own coordinates; views add this.
## Vector2i.ZERO for an instance the web doesn't reach.
func offset(instance_name: String) -> Vector2i:
	if _offsets.is_empty():
		_lay_out()
	return _offsets.get(instance_name, Vector2i.ZERO)


## Why the web can't be laid out as one world, or "" (#187): an exit whose target has no way back to
## it, a second way into an instance that doesn't fit where the first placed it, or two instances
## that would lie on the same tile. The world flow checks it over many seeds, since arranged
## regions vary with them.
func layout_problem() -> String:
	if _offsets.is_empty():
		_lay_out()
	if not _layout_problem.is_empty():
		return _layout_problem
	var taken: Dictionary[Vector2i, String] = {}
	var names: Array[String] = []
	names.assign(_offsets.keys())
	names.sort()
	for instance_name: String in names:
		for tile: Vector2i in _region(instance_name).sorted_tiles():
			var placed: Vector2i = tile + _offsets[instance_name]
			if taken.has(placed):
				return "%s and %s would overlap on %s" % [taken[placed], instance_name, placed]
			taken[placed] = instance_name
	return ""


## Places every instance the web reaches, breadth first from the starting instance, checking every
## exit against the places already given; the first exit that doesn't fit is `_layout_problem`.
func _lay_out() -> void:
	_offsets[start_name] = Vector2i.ZERO
	var queue: Array[String] = [start_name]
	while not queue.is_empty():
		var from: String = queue.pop_front()
		var region: Region = _region(from)
		for i: int in region.exits.size():
			var target: String = region.exit_blueprints[i]
			var back: Vector3i = _way_back(target, from)
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
func _way_back(instance_name: String, from: String) -> Vector3i:
	var region: Region = _region(instance_name)
	for i: int in region.exits.size():
		if region.exit_blueprints[i] == from:
			return region.exits[i]
	return Vector3i(0, 0, -1)


## The region of the blueprint `instance_name` for the world's seed, arranged once.
func _region(instance_name: String) -> Region:
	if not _regions.has(instance_name):
		_regions[instance_name] = InstanceBlueprints.region_of(
			instance_name,
			seed_for(instance_name),
		)
	return _regions[instance_name]


## Keeps the first layout problem found.
func _note(found: String) -> void:
	if _layout_problem.is_empty():
		_layout_problem = found


## The names of the instances a player is in, in name order: the ones that step.
func active() -> Array[String]:
	var names: Array[String] = []
	for instance_name: String in sorted_names():
		if has_player(instances[instance_name]):
			names.append(instance_name)
	return names


## Advances every instance a player is in by one tick, with the tick's commands by slot, then moves
## every player who walked out through an exit into the instance it leads to (#154). Moving them
## only after every instance has stepped means no one steps twice in a tick. Last, it purges what
## has been left behind long enough.
func step(commands: Array[Command]) -> void:
	tick += 1
	var leaving: Array[Array] = []
	for instance_name: String in active():
		var state: GameState = instances[instance_name]
		Simulation.step(state, commands)
		for event: RefCounted in state.events:
			if event is ExitTaken:
				leaving.append([instance_name, event])
	for move: Array in leaving:
		var from: String = move[0]
		var taken: ExitTaken = move[1]
		_walk_through(from, taken)
	_purge_left_behind()


## Notes when each instance was left behind, and purges every one but the starting instance that
## nobody has been in for PURGE_TICKS (#212): it is dropped, and its next visit loads it fresh at
## its next generation. Anyone entering it before then resets the count.
func _purge_left_behind() -> void:
	for instance_name: String in sorted_names():
		if has_player(instances[instance_name]):
			var _entered: bool = left_at.erase(instance_name)
		elif not left_at.has(instance_name):
			left_at[instance_name] = tick
		elif instance_name != start_name and tick - left_at[instance_name] >= PURGE_TICKS:
			var _dropped: bool = instances.erase(instance_name)
			var _forgotten: bool = left_at.erase(instance_name)
			generations[instance_name] = generation(instance_name) + 1
			# Its region is arranged anew, so the layout is worked out again from it.
			var _arranged: bool = _regions.erase(instance_name)
			_offsets.clear()
			_layout_problem = ""


## The player in `slot`, in whichever instance they are, or null.
func player(slot: int) -> Entity:
	for instance_name: String in sorted_names():
		var found: Entity = instances[instance_name].player(slot)
		if found != null:
			return found
	return null


## The name of the instance the player in `slot` is in, or "".
func instance_of(slot: int) -> String:
	for instance_name: String in sorted_names():
		if instances[instance_name].player(slot) != null:
			return instance_name
	return ""


## Moves the player who took `taken` in `from` into the instance it leads to, onto the exit there
## that leads back: an east exit arrives from the west. They stay if that instance can't load or
## has no way back.
func _walk_through(from: String, taken: ExitTaken) -> void:
	var target: GameState = instance(taken.target)
	if target == null:
		return
	var arrival: Vector2i = Vector2i.ZERO
	var found: bool = false
	for i: int in target.region.exits.size():
		if target.region.exit_blueprints[i] == from and not found:
			arrival = Vector2i(target.region.exits[i].x, target.region.exits[i].y)
			found = true
	if not found:
		return
	instances[from].remove_entity(taken.entity_id)
	var _arrived: Entity = target.add_entity(taken.slot, arrival)


## A fingerprint of every loaded instance, in name order, each with its name and, if nobody is in
## it, when it was left behind; then every purged blueprint's generation.
func state_hash() -> int:
	var result: int = _mix(2_166_136_261, tick)
	for instance_name: String in sorted_names():
		result = _mix(result, name_code(instance_name))
		result = _mix(result, instances[instance_name].state_hash())
		if left_at.has(instance_name):
			result = _mix(result, left_at[instance_name])
	for purged: String in _sorted(generations.keys()):
		result = _mix(_mix(result, name_code(purged)), generations[purged])
	return result


## An empty world refused for `why`.
static func refused(why: String) -> World:
	var empty: World = World.new(0, "")
	empty.problem = why
	return empty


## A 32-bit number for a blueprint name, the same on every platform: its characters, mixed in.
static func name_code(instance_name: String) -> int:
	var code: int = 2_166_136_261
	for i: int in instance_name.length():
		code = _mix(code, instance_name.unicode_at(i))
	return code


## Every loaded instance's name, sorted: the order everything goes through them in.
func sorted_names() -> Array[String]:
	return _sorted(instances.keys())


static func _sorted(keys: Array) -> Array[String]:
	var names: Array[String] = []
	names.assign(keys)
	names.sort()
	return names


## Whether any player is in the instance `state`.
static func has_player(state: GameState) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) != null:
			return true
	return false


## One step of 32-bit FNV-1a, as GameState.state_hash mixes its values.
static func _mix(current: int, word: int) -> int:
	return ((current ^ (word & 0xffff_ffff)) * 16_777_619) & 0xffff_ffff
