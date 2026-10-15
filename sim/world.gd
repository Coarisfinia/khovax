class_name World
extends RefCounted
## A run's world (#139, #148): every instance it has loaded, by blueprint name, each a GameState of
## its own. Each tick it steps every instance a player is in, in name order, and leaves the others
## loaded but still (until #119 purges them). Every instance's seed comes from the run's seed and
## its name, so the same run loads the same instance the same way however and whenever it's
## reached. Players walk from one instance into the next through exits (#154). Deterministic, like
## everything in sim/.

## The run's seed, which every instance's own seed is drawn from.
var run_seed: int = 0
## Ticks the world has run. An instance nobody is in doesn't step, so its own tick can lag behind.
var tick: int = 0
## Every loaded instance, by blueprint name.
var instances: Dictionary[String, GameState] = {}
## Why the world couldn't be set up, or "" when it could.
var problem: String = ""
## The blueprint the run started in: the origin of the world's layout (#187).
var start_name: String = ""
## Each reachable instance's place in the world, worked out once (`offset`).
var _offsets: Dictionary[String, Vector2i] = {}


## A world whose run starts in the blueprint `start` with `players` players in it.
func _init(seed_value: int, start: String, players: int = 1) -> void:
	run_seed = seed_value
	start_name = start
	var first: GameState = InstanceBlueprints.create(start, seed_for(start), players)
	if first == null:
		problem = "the starting instance %s doesn't load" % start
		return
	instances[start] = first


## The seed of the instance loaded from the blueprint `instance_name`: drawn from the run's seed,
## with the name as the stream.
func seed_for(instance_name: String) -> int:
	return Rng.new(run_seed, name_code(instance_name)).next_u32()


## The instance loaded from `instance_name`, loading it with nobody in it the first time, or null
## when it can't load.
func instance(instance_name: String) -> GameState:
	if not instances.has(instance_name):
		var loaded: GameState = InstanceBlueprints.create(instance_name, seed_for(instance_name), 0)
		if loaded == null:
			return null
		instances[instance_name] = loaded
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


## Why the web can't be laid out as one world, or "": two instances that would lie on the same
## tile (#187). The world flow checks it over many seeds, since arranged regions vary with them.
func layout_problem() -> String:
	if _offsets.is_empty():
		_lay_out()
	var taken: Dictionary[Vector2i, String] = {}
	var names: Array[String] = []
	names.assign(_offsets.keys())
	names.sort()
	for instance_name: String in names:
		var region: Region = InstanceBlueprints.region_of(instance_name, seed_for(instance_name))
		for tile: Vector2i in region.sorted_tiles():
			var placed: Vector2i = tile + _offsets[instance_name]
			if taken.has(placed):
				return "%s and %s would overlap on %s" % [taken[placed], instance_name, placed]
			taken[placed] = instance_name
	return ""


## Places every instance the web reaches, breadth first from the starting instance.
func _lay_out() -> void:
	_offsets[start_name] = Vector2i.ZERO
	var queue: Array[String] = [start_name]
	while not queue.is_empty():
		var from: String = queue.pop_front()
		var region: Region = InstanceBlueprints.region_of(from, seed_for(from))
		for i: int in region.exits.size():
			var target: String = region.exit_blueprints[i]
			if _offsets.has(target):
				continue
			var back: Vector2i = _way_back(target, from)
			var exit: Vector3i = region.exits[i]
			var outside: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
			_offsets[target] = _offsets[from] + outside - back
			queue.append(target)


## The tile of the exit in `instance_name` that leads back to `from`: its way back.
func _way_back(instance_name: String, from: String) -> Vector2i:
	var region: Region = InstanceBlueprints.region_of(instance_name, seed_for(instance_name))
	for i: int in region.exits.size():
		if region.exit_blueprints[i] == from:
			return Vector2i(region.exits[i].x, region.exits[i].y)
	return Vector2i.ZERO


## The names of the instances a player is in, in name order: the ones that step.
func active() -> Array[String]:
	var names: Array[String] = []
	for instance_name: String in _sorted_names():
		if _has_player(instances[instance_name]):
			names.append(instance_name)
	return names


## Advances every instance a player is in by one tick, with the tick's commands by slot, then moves
## every player who walked out through an exit into the instance it leads to (#154). Moving them
## only after every instance has stepped means no one steps twice in a tick.
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


## The player in `slot`, in whichever instance they are, or null.
func player(slot: int) -> Entity:
	for instance_name: String in _sorted_names():
		var found: Entity = instances[instance_name].player(slot)
		if found != null:
			return found
	return null


## The name of the instance the player in `slot` is in, or "".
func instance_of(slot: int) -> String:
	for instance_name: String in _sorted_names():
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


## A fingerprint of every loaded instance, in name order, each with its name.
func state_hash() -> int:
	var result: int = _mix(2_166_136_261, tick)
	for instance_name: String in _sorted_names():
		result = _mix(result, name_code(instance_name))
		result = _mix(result, instances[instance_name].state_hash())
	return result


## A 32-bit number for a blueprint name, the same on every platform: its characters, mixed in.
static func name_code(instance_name: String) -> int:
	var code: int = 2_166_136_261
	for i: int in instance_name.length():
		code = _mix(code, instance_name.unicode_at(i))
	return code


func _sorted_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(instances.keys())
	names.sort()
	return names


static func _has_player(state: GameState) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) != null:
			return true
	return false


## One step of 32-bit FNV-1a, as GameState.state_hash mixes its values.
static func _mix(current: int, word: int) -> int:
	return ((current ^ (word & 0xffff_ffff)) * 16_777_619) & 0xffff_ffff
