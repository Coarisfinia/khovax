class_name WorldTravel
extends RefCounted
## How players travel between the world's instances (#154, #457, #716), split out of World (#828).
## A player who walks out through an exit (ExitFeature raises ExitTaken) is moved into the instance
## it leads to, onto its way back, and the world raises that they entered it (InstanceEntered,
## #370). A player sent to the spawn (SentToSpawn, #457) is moved beside their respawn point
## (RespawnPoint, #1890), or else onto their start in the starting instance. Whoever follows a
## player (Feature.followers_of, #716), like their companion, moves with
## them, carrying its data along. It keeps nothing: the world is handed in, as to WorldLayout.
## Deterministic, like everything in core/.


## Moves every player in `leaving` out of the instance they left this tick (#154, #457): each entry
## is the name of that instance and the ExitTaken or SentToSpawn raised there, in the order raised.
## A player sent to the spawn in the tick they took an exit goes to the spawn only.
static func move(world: World, leaving: Array[Array]) -> void:
	var sent: Array[int] = []
	for move_out: Array in leaving:
		var event: RefCounted = move_out[1]
		if event is SentToSpawn:
			sent.append((event as SentToSpawn).entity_id)
	for move_out: Array in leaving:
		var from: String = move_out[0]
		var event: RefCounted = move_out[1]
		if event is SentToSpawn:
			_send_to_spawn(world, from, event as SentToSpawn)
		elif not sent.has((event as ExitTaken).entity_id):
			_walk_through(world, from, event as ExitTaken)


## Moves the player who took `taken` in `from` into the instance it leads to, onto the exit there
## that leads back: an east exit arrives from the west. They stay if that instance can't load or
## has no way back.
static func _walk_through(world: World, from: String, taken: ExitTaken) -> void:
	var target: GameState = world.entering(taken.target)
	if target == null:
		return
	if not target.region.exit_blueprints.has(from):
		return
	var arrival: Vector2i = _arrival(world, from, taken, target.region)
	var left: GameState = world.instances[from]
	# Who follows them is asked while they're still there, so a feature may find them by their
	# player.
	var leaders: Dictionary[int, Array] = _followers(left, taken.slot)
	left.remove_entity(taken.entity_id)
	var arrived: Array[Entity] = [target.add_entity(taken.slot, arrival)]
	if arrived[0] != null:
		_bring_followers(left, leaders, target, arrival)
		raise_entered(world, taken.target, arrived)


## Where the player who took `taken` out of `from` lands in `region`, the instance it leads to,
## which has a way back to `from` (#930): on the way back right across from the exit's tile, where
## the layout puts the two side by side, so an exit many tiles wide (#689) lands each one beside its
## own; else on its first way back.
static func _arrival(world: World, from: String, taken: ExitTaken, region: Region) -> Vector2i:
	var across: Vector2i = taken.tile + Hex.DIRECTIONS[taken.side] + world.offset(from)
	across -= world.offset(taken.target)
	for i: int in region.exits.size():
		var back: Vector3i = region.exits[i]
		if region.exit_blueprints[i] == from and Vector2i(back.x, back.y) == across:
			return across
	var first: Vector3i = region.exits[region.exit_blueprints.find(from)]
	return Vector2i(first.x, first.y)


## Moves the player `sent` names from `from` back, as a new entity, so at full HP: beside their
## respawn point (#1890, RespawnPoint) while it's still there, else onto their start in the
## starting instance (#457), the world's spawn.
static func _send_to_spawn(world: World, from: String, sent: SentToSpawn) -> void:
	var landing: Array = _respawn_landing(world, sent.slot)
	if landing.is_empty():
		landing = _spawn_landing(world, sent.slot)
	if landing.is_empty():
		return
	var target_name: String = landing[0]
	var arrival: Vector2i = landing[1]
	var target: GameState = world.instances[target_name]
	var left: GameState = world.instances[from]
	var leaders: Dictionary[int, Array] = _followers(left, sent.slot)
	left.remove_entity(sent.entity_id)
	var arrived: Array[Entity] = [target.add_entity(sent.slot, arrival)]
	if arrived[0] != null:
		_bring_followers(left, leaders, target, arrival)
		raise_entered(world, target_name, arrived)


## Where the player in `slot` lands at the world's spawn: `[instance, tile]`, their start in the
## starting instance, or empty when it can't load.
static func _spawn_landing(world: World, slot: int) -> Array:
	var spawn: GameState = world.entering(world.start_name)
	if spawn == null or spawn.region.starts.is_empty():
		return []
	var starts: Array[Vector2i] = spawn.region.starts
	return [world.start_name, starts[mini(slot, starts.size() - 1)]]


## Where the player in `slot` lands at their respawn point (#1890): `[instance, tile]`, the first
## walkable tile beside it, or empty for none, or one whose instance can't load, whose tile no
## longer holds what it was set on, or with nowhere to stand beside it.
static func _respawn_landing(world: World, slot: int) -> Array:
	var entry: Dictionary = world.stored(slot, RespawnPoint.ENTRY)
	var point: Array = RespawnPoint.of(entry)
	if point.is_empty():
		return []
	var instance_name: String = point[0]
	var tile: Vector2i = point[1]
	if not world.source.exists(instance_name):
		return []
	var target: GameState = world.entering(instance_name)
	if target == null or not RespawnPoint.still_there(entry, target.region, tile):
		return []
	var beside: Vector2i = _beside(target.region, tile)
	return [instance_name, beside] if beside != tile else []


## Moves the followers `leaders` names (`_followers`, #716) out of `left` into `target` along with
## their player: each as a new entity on the first walkable tile beside `beside`, in direction order
## (or on it), and each feature there restores what it kept on it (`carry_out`, `carry_in`).
## Followers walk through with their player rather than being made anew, so nothing is left behind
## and what they had (HP, a wait) comes along. Every exit leads to another instance, so `left` is
## `target` only for one sent to the spawn of the instance they're in: their followers stay, and
## rejoin them by walking.
static func _bring_followers(
	left: GameState,
	leaders: Dictionary[int, Array],
	target: GameState,
	beside: Vector2i,
) -> void:
	if left == target:
		return
	var ids: Array[int] = []
	ids.assign(leaders.keys())
	ids.sort()
	for follower_id: int in ids:
		var carried: Dictionary[String, Dictionary] = {}
		for each: Feature in left.features:
			var values: Dictionary = each.carry_out(left, follower_id)
			if not values.is_empty():
				carried[each.id()] = values
		left.remove_entity(follower_id)
		# One whose leading feature the instance next door lacks goes, as every companion did before
		# #716: it would arrive as no one's there, and staying would leave it behind.
		var welcome: bool = true
		for feature_id: String in leaders[follower_id]:
			welcome = welcome and target.feature(feature_id) != null
		if not welcome:
			continue
		# Never refused: an entity without a slot is always added.
		var arrived: Entity = target.add_entity(Entity.NO_SLOT, _beside(target.region, beside))
		for each: Feature in target.features:
			if carried.has(each.id()):
				each.carry_in(target, arrived, carried[each.id()])


## Every entity in `state` that follows the player in `slot`, with the ids of the features that
## lead it (`Feature.followers_of`).
static func _followers(state: GameState, slot: int) -> Dictionary[int, Array]:
	var found: Dictionary[int, Array] = {}
	for each: Feature in state.features:
		for follower_id: int in each.followers_of(state, slot):
			if state.entity(follower_id) == null:
				continue
			if not found.has(follower_id):
				found[follower_id] = []
			found[follower_id].append(each.id())
	return found


## The first walkable tile next to `tile` in `region`, in direction order, or `tile` itself.
static func _beside(region: Region, tile: Vector2i) -> Vector2i:
	for direction: Vector2i in Hex.DIRECTIONS:
		if region.is_walkable(tile + direction):
			return tile + direction
	return tile


## Raises in `world` that each player among `entities` entered the instance `instance_name`.
static func raise_entered(world: World, instance_name: String, entities: Array[Entity]) -> void:
	for entering: Entity in entities:
		if entering.slot != Entity.NO_SLOT:
			world.events.append(_entered_event(instance_name, entering))


## That `entering` entered the instance `instance_name`.
static func _entered_event(instance_name: String, entering: Entity) -> InstanceEntered:
	return InstanceEntered.new(instance_name, entering.id, entering.slot)
