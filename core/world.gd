class_name World
extends RefCounted
## The world (#139, #148): every instance it has loaded, by blueprint name, each a GameState of
## its own. Each tick it steps every instance a player is in, in name order, and leaves the others
## loaded but still, until one has been left behind for PURGE_TICKS: then it is purged (#212).
## Every instance's seed comes from the world's seed, its name and its generation, which goes up
## with each purge, so the same world loads the same instance the same way however and whenever
## it's reached, and a purged one comes back arranged anew. There are no runs (#183): the players
## roam this one persistent world, saved between sessions (WorldData). A player who walks out
## through an exit (ExitFeature raises ExitTaken) is moved into the instance it leads to, onto its
## way back (#154), and the world raises that they entered it (#370). A player sent to the spawn
## (SentToSpawn, #457) is moved onto their start in the starting instance. Deterministic, like
## everything in core/.

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
## What the world loads its instances from (#396), handed in, so the core names no blueprint.
var source: InstanceSource = null
## Where each instance lies in the world, worked out once (#187, #282).
var _layout: WorldLayout = WorldLayout.new()
## Each player slot's companion species, or "" for none (#338): who the players bring, which
## every instance the world loads is handed (GameState.companions). Set when the session starts.
var companions: Array[String] = []
## The world's own events of the last tick (#370): players who came into another instance
## (InstanceEntered), which no instance's features see. Like an instance's events, they're derived
## from what happened, so they're neither hashed nor saved.
var events: Array[RefCounted] = []


## A world that loads its instances from `instance_source` and starts in the blueprint `start` with
## `players` players in it, each slot bringing its companion from `companion_species` (by slot; none
## past its end); with no `start`, an empty one, which only a refused save gives
## (`WorldData.to_world`).
func _init(
	instance_source: InstanceSource,
	seed_value: int,
	start: String,
	players: int = 1,
	companion_species: Array[String] = [],
) -> void:
	source = instance_source
	world_seed = seed_value
	start_name = start
	set_companions(companion_species)
	if start.is_empty():
		return
	var first: GameState = create_instance(start, players)
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
		var loaded: GameState = create_instance(instance_name, 0)
		if loaded == null:
			return null
		instances[instance_name] = loaded
		left_at[instance_name] = tick
	return instances[instance_name]


## A fresh instance of the blueprint `instance_name` at its current generation's seed, with
## `players` players and the world's companions, not yet among the loaded ones; null when it can't
## load.
func create_instance(instance_name: String, players: int) -> GameState:
	var created: GameState = source.create(instance_name, seed_for(instance_name), players)
	if created != null:
		created.companions = companions.duplicate()
		_hand_next_door(instance_name, created)
	return created


## Hands `state`, the instance `instance_name`, the ground of every instance its exits lead to
## (#191), shifted into its coordinates as the views place them (`offset`).
func _hand_next_door(instance_name: String, state: GameState) -> void:
	state.next_door = {}
	for target: String in state.region.exit_blueprints:
		var shift: Vector2i = offset(target) - offset(instance_name)
		var ground: Region = _layout.region_for(self, target)
		for tile: Vector2i in ground.sorted_tiles():
			if not state.region.has_tile(tile + shift):
				state.next_door[tile + shift] = ground.terrain[tile]
	state.next_door_version += 1


## Sets every slot's companion species, by slot ("" or nothing for none), in the world and every
## instance it has loaded: a session's start decides who the players bring (#338).
func set_companions(companion_species: Array[String]) -> void:
	companions.clear()
	for slot: int in GameState.MAX_PLAYERS:
		companions.append(companion_species[slot] if slot < companion_species.size() else "")
	for instance_name: String in sorted_names():
		instances[instance_name].companions = companions.duplicate()


## Where tile (0, 0) of the instance `instance_name` lies in the world (#187); see WorldLayout.
func offset(instance_name: String) -> Vector2i:
	return _layout.offset(self, instance_name)


## Why the web can't be laid out as one world, or "" (#187); see WorldLayout.
func layout_problem() -> String:
	return _layout.problem(self)


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
## has been left behind long enough. On a fresh world's first tick, every player enters the
## instance they start in; a resumed world's players were already in theirs.
func step(commands: Array[Command]) -> void:
	events.clear()
	if tick == 0:
		for instance_name: String in active():
			_raise_entered(instance_name, instances[instance_name].entities)
	tick += 1
	var stepping: Array[String] = active()
	# An instance nobody is in doesn't step, so it raises nothing this tick: its last tick's events
	# would otherwise reach whoever walks into it as new (#386).
	for instance_name: String in sorted_names():
		if not stepping.has(instance_name):
			instances[instance_name].events.clear()
	var leaving: Array[Array] = []
	for instance_name: String in stepping:
		var state: GameState = instances[instance_name]
		Simulation.step(state, commands)
		for event: RefCounted in state.events:
			if event is ExitTaken or event is SentToSpawn:
				leaving.append([instance_name, event])
	for move: Array in leaving:
		var from: String = move[0]
		var event: RefCounted = move[1]
		if event is SentToSpawn:
			_send_to_spawn(from, event as SentToSpawn)
		else:
			_walk_through(from, event as ExitTaken)
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
			# Its region is arranged anew, so the layout is worked out again from it, and the
			# instances next to it see its new ground.
			_layout.forget(instance_name)
			for loaded: String in sorted_names():
				_hand_next_door(loaded, instances[loaded])


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
	var arrived: Array[Entity] = [target.add_entity(taken.slot, arrival)]
	if arrived[0] != null:
		_raise_entered(taken.target, arrived)


## Moves the player `sent` names from `from` onto their start in the starting instance (#457), as a
## new entity, so at full HP: back at the world's spawn.
func _send_to_spawn(from: String, sent: SentToSpawn) -> void:
	var spawn: GameState = instance(start_name)
	if spawn == null or spawn.region.starts.is_empty():
		return
	var starts: Array[Vector2i] = spawn.region.starts
	instances[from].remove_entity(sent.entity_id)
	var start: Vector2i = starts[mini(sent.slot, starts.size() - 1)]
	var arrived: Array[Entity] = [spawn.add_entity(sent.slot, start)]
	if arrived[0] != null:
		_raise_entered(start_name, arrived)


## Raises that each player among `entities` entered the instance `instance_name`.
func _raise_entered(instance_name: String, entities: Array[Entity]) -> void:
	for entering: Entity in entities:
		if entering.slot != Entity.NO_SLOT:
			events.append(_entered_event(instance_name, entering))


## That `entering` entered the instance `instance_name`.
static func _entered_event(instance_name: String, entering: Entity) -> InstanceEntered:
	return InstanceEntered.new(instance_name, entering.id, entering.slot)


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
	var empty: World = World.new(null, 0, "")
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
