class_name World
extends RefCounted
## The world (#139, #148): every instance it has loaded, by blueprint name, each a GameState of
## its own. Each tick it steps every instance a player is in, in name order, and leaves the others
## loaded but still, until one has been left behind for PURGE_TICKS: then it is purged (#212).
## Every instance's seed comes from the world's seed, its name and its generation, which goes up
## with each purge, so the same world loads the same instance the same way however and whenever
## it's reached, and a purged one comes back arranged anew. There are no runs (#183): the players
## roam this one persistent world, saved between sessions (WorldData). Players who walk out
## through an exit or are sent to the spawn are moved once every instance stepped, with whoever
## follows them (WorldTravel, #154, #457, #716). Each player has a world store (PlayerStore,
## #724), where features keep what the player brings along, like their companions (#338): every
## instance the world loads gets a copy, and what the instance the player is in changes in it is
## taken back into the world once that instance stepped, and handed to every other. The world keeps
## a set of flags (#529), a fresh world starting with its source's (#637), which choose each
## blueprint's variant (`InstanceSource.variant`): setting or clearing one purges every loaded
## instance whose variant it changes, once nobody is in it, so it comes back from its new variant
## and no player sees it change. Any rule can raise a named event (EventEmitted, #541), which sets
## the flag EVENT_FLAG + its name, so whatever happens in an instance can change the world: a story
## beat does, and the first time it sets its flag the world raises that it changed (WorldChanged,
## #499). A rule can also replace a kind of flag (FlagReplaced, #638), clearing the others of its
## kind in
## the same tick as it sets its own, like a territory changing hands.
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
## The blueprint the world starts in: the origin of the world's layout (#187). Always loaded: only
## a flag's variant change purges it (#727), and it's loaded again at once.
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
## Each player slot's world store (#724), which every instance gets a copy of (GameState.stores).
var stores: Array[PlayerStore] = []
## The world's own events of the last tick (#370): players who came into another instance
## (InstanceEntered) and world-changing moments (WorldChanged, #499), which no instance's features
## see. Like an instance's events, they're derived from what happened, so they're neither hashed
## nor saved.
var events: Array[RefCounted] = []


## A world that loads its instances from `instance_source` and starts in the blueprint `start` with
## `players` players in it, each with an empty world store; with no `start`, an empty one, which
## only a refused save gives (`WorldData.to_world`).
func _init(
	instance_source: InstanceSource,
	seed_value: int,
	start: String,
	players: int = 1,
) -> void:
	source = instance_source
	world_seed = seed_value
	start_name = start
	stores = PlayerStore.for_every_slot()
	if start.is_empty():
		return
	# Before the first instance loads: flags choose variants.
	for flag: String in instance_source.starting_flags():
		set_flag(flag)
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
	var stream: Rng = Rng.new(world_seed, StateHash.name_code(instance_name))
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
## with `players` players and a copy of every player's world store, not yet among the loaded ones,
## though its
## variant is noted; null when it can't load.
func create_instance(instance_name: String, players: int, variant: String) -> GameState:
	var created: GameState = source.create(instance_name, seed_for(instance_name), players, variant)
	if created != null:
		variants[instance_name] = variant
		created.stores = _copied_stores()
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
## nobody is in it (`_purge_left_behind`), or as someone walks in or is sent to the spawn. The
## starting instance too (#727), which is loaded again at once from its new variant.
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
## choose now.
func _outdated(instance_name: String) -> bool:
	return variant_of(instance_name) != _chosen_variant(instance_name)


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


## Sets the entry of the feature `feature_id` in the world store of the player in `slot` to
## `values` (#724), in the world and every instance it has loaded: for what a session's start
## decides, like who the players bring (#53), which the slices set through their own rules.
func set_entry(slot: int, feature_id: String, values: Dictionary) -> void:
	stores[slot].entries[feature_id] = values.duplicate(true)
	_hand_stores()


## The entry of the feature `feature_id` in the world store of the player in `slot`, to read only.
func stored(slot: int, feature_id: String) -> Dictionary:
	return stores[slot].stored(feature_id)


## Takes the world store of every player in `stepped` back into the world (#724), where its rules
## changed it this tick, and hands the world's stores to every loaded instance when any changed. A
## player is in one instance only, so no other instance changed theirs this tick; one who walked out
## this tick is still in it, since they're moved only once every instance stepped.
func _take_stores(stepped: GameState) -> void:
	var taken: bool = false
	for slot: int in GameState.MAX_PLAYERS:
		if stepped.player(slot) != null and not stepped.stores[slot].same_as(stores[slot]):
			stores[slot] = stepped.stores[slot].copied()
			taken = true
	if taken:
		_hand_stores()


## Hands every loaded instance a copy of every player's world store.
func _hand_stores() -> void:
	for instance_name: String in sorted_names():
		instances[instance_name].stores = _copied_stores()


## A copy of every player's world store, by slot.
func _copied_stores() -> Array[PlayerStore]:
	var copies: Array[PlayerStore] = []
	for each: PlayerStore in stores:
		copies.append(each.copied())
	return copies


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
## every player who walked out through an exit into the instance it leads to (#154). Each instance's
## players' world stores are taken back as soon as it stepped (#724). Moving players only after
## every
## instance has stepped means no one steps twice in a tick. Last, it purges what has been left
## behind long enough. On a fresh world's first tick, every player enters the
## instance they start in; a resumed world's players were already in theirs.
func step(commands: Array[Command]) -> void:
	events.clear()
	if tick == 0:
		for instance_name: String in active():
			WorldTravel.raise_entered(self, instance_name, instances[instance_name].entities)
	tick += 1
	var stepping: Array[String] = active()
	# An instance nobody is in doesn't step, so it raises nothing this tick: its last tick's events
	# would otherwise reach whoever walks into it as new (#386).
	for instance_name: String in sorted_names():
		if not stepping.has(instance_name):
			instances[instance_name].events.clear()
	var leaving: Array[Array] = []
	var emitted: Array[EventEmitted] = []
	var replaced: Array[FlagReplaced] = []
	for instance_name: String in stepping:
		var state: GameState = instances[instance_name]
		Simulation.step(state, commands)
		_take_stores(state)
		for event: RefCounted in state.events:
			if event is ExitTaken or event is SentToSpawn:
				leaving.append([instance_name, event])
			elif event is EventEmitted:
				emitted.append(event as EventEmitted)
			elif event is FlagReplaced:
				replaced.append(event as FlagReplaced)
	_hand_changed_ground(stepping)
	_set_emitted(emitted)
	_replace_flags(replaced)
	WorldTravel.move(self, leaving)
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


## Carries out every flag replacement in `replaced` (#638), raised this tick, in the order raised,
## like the emitted events' flags: each clears every flag of its kind but its own, then sets it.
func _replace_flags(replaced: Array[FlagReplaced]) -> void:
	for event: FlagReplaced in replaced:
		for held: String in flags.duplicate():
			if held.begins_with(event.kind) and held != event.flag:
				set_flag(held, false)
		set_flag(event.flag)


## That the event `event_name` changed the world by setting `flag`.
static func _changed_event(event_name: String, flag: String) -> WorldChanged:
	return WorldChanged.new(event_name, flag)


## Notes when each instance was left behind, and purges every one nobody is in that a flag
## outdated (#529; the starting instance too, #727), and every one but the starting instance that
## nobody has been in for PURGE_TICKS (#212).
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
## its next generation, from the variant the flags choose then. The starting instance is loaded
## again at once (#727): replays and the driver start from it, and a save always holds it.
func _purge(instance_name: String) -> void:
	var _dropped: bool = instances.erase(instance_name)
	var _forgotten: bool = left_at.erase(instance_name)
	var _unvaried: bool = variants.erase(instance_name)
	generations[instance_name] = generation(instance_name) + 1
	# Its region is arranged anew, so the layout is worked out again from it, and the instances next
	# to it see its new ground.
	_layout.forget(instance_name)
	refresh_next_door()
	if instance_name == start_name:
		var _reloaded: GameState = instance(start_name)


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


## The instance `instance_name`, which a player is about to enter, loading it if need be, or null
## when it can't load. One a flag outdated this tick is purged first, so whoever comes in finds its
## new variant. Only here (for WorldTravel) and in `_purge_left_behind`, inside a step, so an
## instance is purged at most once a tick.
func entering(instance_name: String) -> GameState:
	var loaded_before: GameState = instances.get(instance_name)
	if loaded_before != null and not has_player(loaded_before) and _outdated(instance_name):
		_purge(instance_name)
	return instance(instance_name)


## A fingerprint of every loaded instance, in name order, each with its name and, if nobody is in
## it, when it was left behind, and the variant it was loaded from unless it's the plain one; then
## every purged blueprint's generation, then the flags. What isn't there mixes in nothing, so a
## world without variants or flags hashes as it did before them.
func state_hash() -> int:
	var result: int = StateHash.mix(StateHash.OFFSET, tick)
	for instance_name: String in sorted_names():
		result = StateHash.mix(result, StateHash.name_code(instance_name))
		result = StateHash.mix(result, instances[instance_name].state_hash())
		if left_at.has(instance_name):
			result = StateHash.mix(result, left_at[instance_name])
		if not variant_of(instance_name).is_empty():
			result = StateHash.mix(result, StateHash.name_code(variant_of(instance_name)))
	for purged: String in StateHash.sorted(generations.keys()):
		result = StateHash.mix(
			StateHash.mix(result, StateHash.name_code(purged)),
			generations[purged],
		)
	for flag: String in flags:
		result = StateHash.mix(result, StateHash.name_code(flag))
	return result


## An empty world refused for `why`.
static func refused(why: String) -> World:
	var empty: World = World.new(null, 0, "")
	empty.problem = why
	return empty


## Every loaded instance's name, sorted: the order everything goes through them in.
func sorted_names() -> Array[String]:
	return StateHash.sorted(instances.keys())


## Whether any player is in the instance `state`.
static func has_player(state: GameState) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) != null:
			return true
	return false
