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
## (SentToSpawn, #457) is moved onto their start in the starting instance. A player who chooses
## another carried monster as their companion (CompanionChosen, #55) has it as their companion in
## every instance from then on. The world keeps a set of flags (#529), which choose each blueprint's
## variant (`InstanceSource.variant`): setting or clearing one purges every loaded instance whose
## variant it changes, once nobody is in it, so it comes back from its new variant and no player
## sees it change. Any rule can raise a named event (EventEmitted, #541), which sets the flag
## EVENT_FLAG + its name, so whatever happens in an instance can change the world: a story beat
## does, and the first time it sets its flag the world raises that it changed (WorldChanged, #499).
## Deterministic, like everything in core/.

## How long an instance nobody is in stays loaded (#212): an hour of play, counted in the world's
## ticks, which only pass while the game is played, never while it's closed.
const PURGE_TICKS: int = 60 * 60 * Simulation.TICKS_PER_SECOND
## What the flag a named event sets begins with (#541): EVENT_EMITTED_<the event's name>.
const EVENT_FLAG: String = "EVENT_EMITTED_"

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
## The world's flags (#529), sorted: ids that story beats and rules set, each choosing blueprints'
## variants.
var flags: Array[String] = []
## The variant each loaded instance was loaded from, by name ("" for a blueprint's plain one): it
## keeps it until it's purged, even after a flag chose another.
var variants: Dictionary[String, String] = {}
## What the world loads its instances from (#396), handed in, so the core names no blueprint.
var source: InstanceSource = null
## Where each instance lies in the world, worked out once (#187, #282).
var _layout: WorldLayout = WorldLayout.new()
## Each player slot's companion species, or "" for none (#338): which of their carried monsters
## walks beside them, which every instance the world loads is handed (GameState.companions). The
## first they carry when the session starts, until they choose another (#55).
var companions: Array[String] = []
## Each player slot's carried monsters' species, in their carried order (#53), empty for none:
## who the players bring, which every instance the world loads is handed (GameState.carried). Set
## when the session starts.
var carried: Array[PackedStringArray] = []
## The world's own events of the last tick (#370): players who came into another instance
## (InstanceEntered) and world-changing moments (WorldChanged, #499), which no instance's features
## see. Like an instance's events, they're derived from what happened, so they're neither hashed
## nor saved.
var events: Array[RefCounted] = []


## A world that loads its instances from `instance_source` and starts in the blueprint `start` with
## `players` players in it, each slot carrying just its companion from `companion_species` (by slot;
## none past its end); with no `start`, an empty one, which only a refused save gives
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
	set_carried(_parties_of(companion_species))
	if start.is_empty():
		return
	var first: GameState = create_instance(start, players, _chosen_variant(start))
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
		var loaded: GameState = create_instance(instance_name, 0, _chosen_variant(instance_name))
		if loaded == null:
			return null
		instances[instance_name] = loaded
		left_at[instance_name] = tick
	return instances[instance_name]


## A fresh instance of the blueprint `instance_name`'s `variant` at its current generation's seed,
## with `players` players and the world's companions, not yet among the loaded ones, though its
## variant is noted; null when it can't load.
func create_instance(instance_name: String, players: int, variant: String) -> GameState:
	var created: GameState = source.create(instance_name, seed_for(instance_name), players, variant)
	if created != null:
		variants[instance_name] = variant
		created.companions = companions.duplicate()
		created.carried = carried.duplicate()
		_hand_next_door(instance_name, created)
	return created


## The variant of the blueprint `instance_name` the world's flags choose now (#529).
func _chosen_variant(instance_name: String) -> String:
	return source.variant(instance_name, flags)


## The variant of the blueprint `instance_name` as it is in the world: the one it was loaded from
## while it's loaded, else the one the flags choose. Its region is read from it.
func variant_of(instance_name: String) -> String:
	if variants.has(instance_name):
		return variants[instance_name]
	return _chosen_variant(instance_name)


## Sets the flag `flag` (#529), or clears it when `on` is false: for story beats and the rules that
## change the world. Every loaded instance whose variant that changes is outdated: purged once
## nobody is in it (`_purge_left_behind`), or as someone walks in. The starting instance is never
## purged, so it keeps the variant it was loaded from.
func set_flag(flag: String, on: bool = true) -> void:
	if flags.has(flag) == on:
		return
	if on:
		flags.append(flag)
		flags.sort()
	else:
		flags.erase(flag)
	# The instances not loaded may now have other regions: the layout is worked out again, and the
	# loaded ones see their neighbours' new ground.
	_layout = WorldLayout.new()
	refresh_next_door()


## Whether the loaded instance `instance_name` was loaded from another variant than the flags
## choose now; never the starting instance, which is never purged.
func _outdated(instance_name: String) -> bool:
	var chosen: String = _chosen_variant(instance_name)
	return instance_name != start_name and variant_of(instance_name) != chosen


## Hands every loaded instance the ground next door again (`_hand_next_door`), in name order: once
## it changed, or once every saved instance is back with its tiles changed in place (WorldData).
func refresh_next_door() -> void:
	for loaded: String in sorted_names():
		_hand_next_door(loaded, instances[loaded])


## Hands `state`, the instance `instance_name`, the ground of every instance its exits lead to
## (#191), shifted into its coordinates as the views place them (`offset`): a loaded one's region as
## it is, with its tiles changed in place (#538), or else as it would be arranged.
func _hand_next_door(instance_name: String, state: GameState) -> void:
	var next_door: Dictionary[Vector2i, int] = {}
	for target: String in state.region.exit_blueprints:
		var shift: Vector2i = offset(target) - offset(instance_name)
		var ground: Region = _layout.region_for(self, target)
		if instances.has(target):
			ground = instances[target].region
		for tile: Vector2i in ground.sorted_tiles():
			if not state.region.has_tile(tile + shift):
				next_door[tile + shift] = ground.terrain[tile]
	state.hand_next_door(next_door)


## Each slot's party from its companion species, by slot: the companion alone, or none for "".
static func _parties_of(companion_species: Array[String]) -> Array[PackedStringArray]:
	var parties: Array[PackedStringArray] = []
	for species: String in companion_species:
		parties.append(PackedStringArray([species] if not species.is_empty() else []))
	return parties


## Sets every slot's carried species, by slot, in carried order (empty or nothing for none), in the
## world and every instance it has loaded, each slot's first the companion: a session's start
## decides who the players bring (#338, #53).
func set_carried(parties: Array[PackedStringArray]) -> void:
	carried.clear()
	companions.clear()
	for slot: int in GameState.MAX_PLAYERS:
		var party: PackedStringArray = PackedStringArray()
		if slot < parties.size():
			party = parties[slot]
		carried.append(party)
		companions.append(party[0] if not party.is_empty() else "")
	_hand_companions()


## Makes the monster at `place` in the carried order of the player in `slot` their companion (#55),
## in the world and every instance it has loaded.
func choose_companion(slot: int, place: int) -> void:
	companions[slot] = carried[slot][place]
	_hand_companions()


## Hands every loaded instance the world's companions and carried species.
func _hand_companions() -> void:
	for instance_name: String in sorted_names():
		instances[instance_name].companions = companions.duplicate()
		instances[instance_name].carried = carried.duplicate()


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
## every player who walked out through an exit into the instance it leads to (#154) and gives every
## player who chose another companion (#55) theirs. Moving them only after every instance has
## stepped
## means no one steps twice in a tick. Last, it purges what
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
	var emitted: Array[EventEmitted] = []
	for instance_name: String in stepping:
		var state: GameState = instances[instance_name]
		Simulation.step(state, commands)
		for event: RefCounted in state.events:
			if event is ExitTaken or event is SentToSpawn:
				leaving.append([instance_name, event])
			elif event is CompanionChosen:
				choose_companion((event as CompanionChosen).slot, (event as CompanionChosen).place)
			elif event is EventEmitted:
				emitted.append(event as EventEmitted)
	_hand_changed_ground(stepping)
	_set_emitted(emitted)
	# A player sent to the spawn in the tick they took an exit goes to the spawn only.
	var sent: Array[int] = []
	for move: Array in leaving:
		var event: RefCounted = move[1]
		if event is SentToSpawn:
			sent.append((event as SentToSpawn).entity_id)
	for move: Array in leaving:
		var from: String = move[0]
		var event: RefCounted = move[1]
		if event is SentToSpawn:
			_send_to_spawn(from, event as SentToSpawn)
		elif not sent.has((event as ExitTaken).entity_id):
			_walk_through(from, event as ExitTaken)
	_purge_left_behind()


## Hands the instances next door to any of `stepped` that changed a tile in place this tick (#538)
## their new ground, so sight across the seam sees it at once.
func _hand_changed_ground(stepped: Array[String]) -> void:
	var changed: Array[String] = []
	for instance_name: String in stepped:
		for event: RefCounted in instances[instance_name].events:
			if event is TileChanged and not changed.has(instance_name):
				changed.append(instance_name)
	for loaded: String in sorted_names():
		var state: GameState = instances[loaded]
		for target: String in changed:
			if state.region.exit_blueprints.has(target):
				_hand_next_door(loaded, state)
				break


## Sets the flag of every event in `emitted` (#541), raised this tick, once every instance has
## stepped, so no instance's step sees another's events change the world mid-tick; before anyone
## walks through an exit, so whoever walks into an instance one outdated finds its new variant.
## The first time an event sets its flag, the world raises that it changed (WorldChanged, #499).
func _set_emitted(emitted: Array[EventEmitted]) -> void:
	for event: EventEmitted in emitted:
		var flag: String = EVENT_FLAG + event.event_name
		if not flags.has(flag):
			set_flag(flag)
			events.append(_changed_event(event.event_name, flag))


## That the event `event_name` changed the world by setting `flag`.
static func _changed_event(event_name: String, flag: String) -> WorldChanged:
	return WorldChanged.new(event_name, flag)


## Notes when each instance was left behind, and purges every one but the starting instance that
## nobody has been in for PURGE_TICKS (#212), or that nobody is in and a flag outdated (#529).
## Anyone entering it before then resets the count. Each instance is purged at most once a tick.
func _purge_left_behind() -> void:
	for instance_name: String in sorted_names():
		if has_player(instances[instance_name]):
			var _entered: bool = left_at.erase(instance_name)
		elif _outdated(instance_name):
			_purge(instance_name)
		elif not left_at.has(instance_name):
			left_at[instance_name] = tick
		elif instance_name != start_name and tick - left_at[instance_name] >= PURGE_TICKS:
			_purge(instance_name)


## Purges the instance `instance_name` (#212): it is dropped, and its next visit loads it fresh at
## its next generation, from the variant the flags choose then.
func _purge(instance_name: String) -> void:
	var _dropped: bool = instances.erase(instance_name)
	var _forgotten: bool = left_at.erase(instance_name)
	var _unvaried: bool = variants.erase(instance_name)
	generations[instance_name] = generation(instance_name) + 1
	# Its region is arranged anew, so the layout is worked out again from it, and the instances next
	# to it see its new ground.
	_layout.forget(instance_name)
	refresh_next_door()


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
	# One a flag outdated this tick is purged first, so whoever walks in finds its new variant. Only
	# here and in `_purge_left_behind`, inside a step, so an instance is purged at most once a tick.
	var loaded_before: GameState = instances.get(taken.target)
	if loaded_before != null and not has_player(loaded_before) and _outdated(taken.target):
		_purge(taken.target)
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
## it, when it was left behind, and the variant it was loaded from unless it's the plain one; then
## every purged blueprint's generation, then the flags. What isn't there mixes in nothing, so a
## world without variants or flags hashes as it did before them.
func state_hash() -> int:
	var result: int = _mix(2_166_136_261, tick)
	for instance_name: String in sorted_names():
		result = _mix(result, name_code(instance_name))
		result = _mix(result, instances[instance_name].state_hash())
		if left_at.has(instance_name):
			result = _mix(result, left_at[instance_name])
		if not variant_of(instance_name).is_empty():
			result = _mix(result, name_code(variant_of(instance_name)))
	for purged: String in _sorted(generations.keys()):
		result = _mix(_mix(result, name_code(purged)), generations[purged])
	for flag: String in flags:
		result = _mix(result, name_code(flag))
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
