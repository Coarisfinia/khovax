extends RefCounted
## Replay flow: the simulation alone, without scenes, input or frames. The same start and the same
## commands must always give the same state, tick for tick; that is what makes replays and
## lockstep co-op possible. Also checks the game rules as features: movement in whole ticks, the
## trail, the feature order, and switching features off and on during a run.

const START: Vector2i = Vector2i(1, -1)
const RADIUS: int = 3
const EAST: int = 0
const WEST: int = 3
## Long enough for the scripted commands to walk around the grid several times.
const REPLAY_TICKS: int = 600


func run(_tree: SceneTree) -> String:
	var steps: Array[Callable] = [
		_check_move_timing,
		_check_invalid_commands,
		_check_same_commands_same_state,
		_check_hash_sees_changes,
		_check_hash_covers_fields,
		_check_trail,
		_check_feature_order,
		_check_switching_features,
		_check_instance_without_trail,
		_check_invalid_order_state,
		_check_switch_within_tick,
		_check_players_move_at_once,
		_check_entity_ids_stay,
		_check_player_slots,
	]
	for step: Callable in steps:
		var result: String = step.call()
		if not result.is_empty():
			return result
	return ""


## Holding east: the first move starts at once, the next one exactly MOVE_TICKS later, and the
## grid's edge stops the player.
func _check_move_timing() -> String:
	var state: GameState = _state(1)
	var arrivals: Array[Vector2i] = []
	for _tick: int in 3 * MovementFeature.MOVE_TICKS + 1:
		Simulation.step(state, _commands(EAST))
		arrivals.append(_tile(state))
	var expected_second: Vector2i = START + 2 * Hex.DIRECTIONS[EAST]
	if arrivals[0] != START + Hex.DIRECTIONS[EAST]:
		return "the first move didn't start on the first tick"
	if arrivals[MovementFeature.MOVE_TICKS - 1] != arrivals[0]:
		return "the second move started before the first one arrived"
	if arrivals[MovementFeature.MOVE_TICKS] != expected_second:
		return "the second move didn't start right as the first one arrived"
	if _tile(state) != expected_second or _player_walk(state).is_moving():
		return "the player didn't stop at the grid's edge, at %s" % _tile(state)
	return ""


func _check_invalid_commands() -> String:
	var state: GameState = _state(1)
	var invalid: Array[int] = [-5, Command.NO_MOVE, Hex.DIRECTIONS.size(), 99]
	for direction: int in invalid:
		Simulation.step(state, _commands(direction))
	if _tile(state) != START or _player_walk(state).is_moving():
		return "an invalid or empty command moved the player"
	return ""


func _check_same_commands_same_state() -> String:
	var first: Array[int] = _replay(_moves(), 42)
	var second: Array[int] = _replay(_moves(), 42)
	if first != second:
		return "the same seed and commands gave different states"
	var last: GameState = _state(42)
	for direction: int in _moves():
		Simulation.step(last, _commands(direction))
	if _tile(last) == START and not _player_walk(last).is_moving():
		return "the scripted commands never moved the player, so the replay proves little"
	return ""


## Changing one command, or the seed, must change the hashes.
func _check_hash_sees_changes() -> String:
	var moves: Array[int] = _moves()
	var baseline: Array[int] = _replay(moves, 42)
	var changed: Array[int] = []
	changed.assign(moves)
	# The first command: the player stands still then, so it is never ignored like a command
	# that arrives mid-move.
	changed[0] = (changed[0] + 1) % Hex.DIRECTIONS.size()
	var last: int = baseline.size() - 1
	if _replay(changed, 42)[last] == baseline[last]:
		return "changing one command didn't change the final state hash"
	if _replay(moves, 43)[0] == baseline[0]:
		return "a different seed didn't change the state hash"
	return ""


## Changing any single value, in the core or in a feature, changes the hash, including bits above
## the lowest 32 and whether a feature is on.
func _check_hash_covers_fields() -> String:
	var base: int = _state(42).state_hash()
	var changes: Dictionary[String, Callable] = {
		"tick": func(state: GameState) -> void: state.tick += 1,
		"rng_seed": func(state: GameState) -> void: state.rng_seed += 1,
		"rng_seed above bit 31": func(state: GameState) -> void: state.rng_seed += 1 << 40,
		"grid_radius": func(state: GameState) -> void: state.grid_radius += 1,
		"next_entity_id": func(state: GameState) -> void: state.next_entity_id += 1,
		"entity id": func(state: GameState) -> void: state.player(0).id += 1,
		"entity slot": func(state: GameState) -> void: state.player(0).slot += 1,
		"entity tile.x": func(state: GameState) -> void: state.player(0).tile.x += 1,
		"entity tile.y": func(state: GameState) -> void: state.player(0).tile.y += 1,
		"an entity more": func(state: GameState) -> void: state.add_entity(Entity.NO_SLOT, START),
		"walk from.x": func(state: GameState) -> void: _player_walk(state).from.x += 1,
		"walk from.y": func(state: GameState) -> void: _player_walk(state).from.y += 1,
		"walk ticks_left": func(state: GameState) -> void: _player_walk(state).ticks_left += 1,
		"walk dropped": func(state: GameState) -> void: _movement(state).walks.clear(),
		"trail": func(state: GameState) -> void: _trail(state).tiles[Vector2i.ZERO] = true,
		# Same size, other tile: the hash must see the coordinates, not only how many there are.
		"trail tile": func(state: GameState) -> void: _trail(state).tiles = { Vector2i.ZERO: true },
		"trail dropped": func(state: GameState) -> void: _trails(state).trails.clear(),
		"movement off": func(state: GameState) -> void: state.set_enabled(Features.MOVEMENT, false),
		"trail off": func(state: GameState) -> void: state.set_enabled(Features.TRAIL, false),
	}
	for field: String in changes:
		var state: GameState = _state(42)
		changes[field].call(state)
		if state.state_hash() == base:
			return "changing %s didn't change the state hash" % field
	return ""


## The trail starts with the start tile, gains every tile moved onto, and walking back over it
## changes nothing. Its hash doesn't depend on the order it was walked in.
func _check_trail() -> String:
	var state: GameState = _state(42)
	var only_start: Array[Vector2i] = [START]
	if _trail(state).sorted_tiles() != only_start:
		return "a new trail is %s, not just the start tile" % [_trail(state).sorted_tiles()]
	var east: Vector2i = Hex.DIRECTIONS[EAST]
	_walk(state, EAST, 2)
	var after_two: Array[Vector2i] = [START, START + east, START + 2 * east]
	after_two.sort()
	if _trail(state).sorted_tiles() != after_two:
		return "after two moves the trail is %s" % [_trail(state).sorted_tiles()]
	_walk(state, WEST, 1)
	if _trail(state).sorted_tiles() != after_two:
		return "walking back over the trail changed it to %s" % [_trail(state).sorted_tiles()]
	var reordered: GameState = _state(42)
	var shuffled: Array[Vector2i] = [START + 2 * east, START, START + east]
	_trail(reordered).tiles = {}
	for tile: Vector2i in shuffled:
		_trail(reordered).tiles[tile] = true
	var ordered: GameState = _state(42)
	_trail(ordered).tiles = {}
	for tile: Vector2i in after_two:
		_trail(ordered).tiles[tile] = true
	if reordered.state_hash() != ordered.state_hash():
		return "the same trail walked in a different order hashes differently"
	return ""


## A feature can't come before a feature it requires, or appear twice.
func _check_feature_order() -> String:
	var trail_first: Array[Feature] = [TrailFeature.new(), MovementFeature.new()]
	var twice: Array[Feature] = [MovementFeature.new(), MovementFeature.new()]
	var valid: Array[Feature] = [MovementFeature.new(), TrailFeature.new()]
	if GameState.order_problem(trail_first).is_empty():
		return "the trail before movement passed as a valid order"
	if GameState.order_problem(twice).is_empty():
		return "a feature appearing twice passed as a valid order"
	if not GameState.order_problem(valid).is_empty():
		return "movement then trail was rejected: " + GameState.order_problem(valid)
	return ""


## Rules can switch features during a run (e.g. a boss phase): off, a feature doesn't step and
## keeps its state; on again, it continues.
func _check_switching_features() -> String:
	var state: GameState = _state(42)
	state.set_enabled(Features.MOVEMENT, false)
	_walk(state, EAST, 1)
	if _tile(state) != START:
		return "the player moved with movement switched off"
	state.set_enabled(Features.MOVEMENT, true)
	state.set_enabled(Features.TRAIL, false)
	_walk(state, EAST, 1)
	var moved_to: Vector2i = START + Hex.DIRECTIONS[EAST]
	if _tile(state) != moved_to:
		return "movement didn't come back when switched on again"
	if _trail(state).tiles.has(moved_to):
		return "the trail grew while switched off"
	state.set_enabled(Features.TRAIL, true)
	# Back over the start tile to a new one: the trail kept its start tile and grows again.
	_walk(state, WEST, 2)
	var beyond_start: Vector2i = START + Hex.DIRECTIONS[WEST]
	if not _trail(state).tiles.has(START) or not _trail(state).tiles.has(beyond_start):
		return "the switched-off trail lost its state or missed the next move"
	return ""


## An instance without the trail still walks, and simply has no trail.
func _check_instance_without_trail() -> String:
	var ordered: Array[Feature] = [MovementFeature.new()]
	var state: GameState = _state_with(ordered, 42)
	_walk(state, EAST, 1)
	if state.feature(Features.TRAIL) != null:
		return "an instance without the trail has one"
	if _tile(state) != START + Hex.DIRECTIONS[EAST]:
		return "an instance without the trail didn't walk"
	if Instances.basic(42, 1).feature(Features.TRAIL) == null:
		return "the basic instance lost its trail"
	return ""


## A state built with an invalid order says why, has no features to run, and the instance factory
## refuses unknown instances.
func _check_invalid_order_state() -> String:
	var trail_first: Array[Feature] = [TrailFeature.new(), MovementFeature.new()]
	var state: GameState = _state_with(trail_first, 42)
	if state.problem.is_empty() or not state.features.is_empty():
		return "a state with an invalid feature order looks runnable"
	var valid: GameState = _state(42)
	if not valid.problem.is_empty():
		return "a valid state reports a problem: " + valid.problem
	return ""


## A rule switching a feature inside a tick applies to that feature's next step in the same tick:
## a boss phase stepping before movement stops the player from moving on that very tick.
func _check_switch_within_tick() -> String:
	# Holding east, the first move arrives on tick 1 + MOVE_TICKS and the next one would start on
	# that same tick. The boss phase begins exactly then: had the switch waited for the next tick,
	# the second move would have started.
	var ordered: Array[Feature] = [
		BossPhase.new(1 + MovementFeature.MOVE_TICKS),
		MovementFeature.new(),
		TrailFeature.new(),
	]
	var state: GameState = _state_with(ordered, 42)
	Simulation.step(state, _commands(EAST))
	var first: Vector2i = _tile(state)
	for _tick: int in MovementFeature.MOVE_TICKS:
		Simulation.step(state, _commands(EAST))
	if first != START + Hex.DIRECTIONS[EAST]:
		return "the player didn't move before the boss phase began"
	if _tile(state) != first or _movement(state).enabled:
		return "the boss phase didn't stop movement within its tick"
	return ""


## Co-op: every player is moved by the command in its own slot, all in the same tick, each with
## its own trail; a slot without a command stands still. Two players replay deterministically.
func _check_players_move_at_once() -> String:
	var state: GameState = Instances.basic(42, 2)
	var first: Entity = state.player(0)
	var second: Entity = state.player(1)
	var start_first: Vector2i = first.tile
	var start_second: Vector2i = second.tile
	Simulation.step(state, _slot_commands(EAST, WEST))
	if first.tile != start_first + Hex.DIRECTIONS[EAST]:
		return "the player in slot 0 didn't follow its own command"
	if second.tile != start_second + Hex.DIRECTIONS[WEST]:
		return "the player in slot 1 didn't move in the same tick by its own command"
	var trails: TrailFeature = _trails(state)
	var shared: bool = trails.trail(first.id).tiles.has(second.tile)
	if shared or trails.trail(second.id).tiles.has(first.tile):
		return "the players share a trail"
	var only_first: Array[Command] = [Command.new(WEST)]
	for _tick: int in MovementFeature.MOVE_TICKS:
		Simulation.step(state, only_first)
	if second.tile != start_second + Hex.DIRECTIONS[WEST]:
		return "a slot without a command still moved its player"
	var hashes: Array[int] = []
	for _run: int in 2:
		var run: GameState = Instances.basic(42, 2)
		for direction: int in _moves():
			Simulation.step(run, _slot_commands(direction, (direction + 2) % Hex.DIRECTIONS.size()))
		hashes.append(run.state_hash())
	if hashes[0] != hashes[1]:
		return "two players with the same commands gave different states"
	return ""


## Entity ids are stable: removing an entity keeps the others' ids and drops every feature's data
## for it, and a new entity never gets a removed one's id.
func _check_entity_ids_stay() -> String:
	var state: GameState = Instances.basic(42, 3)
	var ids: Array[int] = []
	for each: Entity in state.entities:
		ids.append(each.id)
	var removed: int = ids[1]
	state.remove_entity(removed)
	if state.entity(removed) != null or state.entity(ids[0]) == null:
		return "removing an entity took the wrong one"
	if state.entity(ids[2]) == null:
		return "removing an entity took the wrong one"
	if _movement(state).walk(removed) != null or _trails(state).trail(removed) != null:
		return "a removed entity's walk or trail stayed behind"
	var added: Entity = state.add_entity(1, START)
	if ids.has(added.id):
		return "a new entity got the id %d again" % added.id
	if state.player(1) != added or _movement(state).walk(added.id) == null:
		return "a player added during a run doesn't walk in its slot"
	return _check_id_order(state)


func _check_id_order(state: GameState) -> String:
	var order: Array[int] = []
	for each: Entity in state.entities:
		order.append(each.id)
	var sorted: Array[int] = []
	sorted.assign(order)
	sorted.sort()
	if order != sorted:
		return "the entities aren't in id order: %s" % [order]
	return ""


## Each slot has at most one player: a taken or out-of-range slot adds nothing, while any number
## of entities can belong to no player.
func _check_player_slots() -> String:
	var state: GameState = _state(42)
	var before: int = state.state_hash()
	var refused: Array[int] = [0, -2, GameState.MAX_PLAYERS]
	for slot: int in refused:
		if state.add_entity(slot, START) != null:
			return "slot %d took another entity" % slot
	if state.state_hash() != before:
		return "a refused entity still changed the state"
	var unowned: Entity = state.add_entity(Entity.NO_SLOT, START)
	if unowned == null or state.add_entity(Entity.NO_SLOT, START) == null:
		return "entities without a player were refused"
	if _movement(state).walk(unowned.id) != null:
		return "an entity without a player got a walk"
	return ""


## Moves `moves` tiles in one direction, waiting for each move to arrive.
func _walk(state: GameState, direction: int, moves: int) -> void:
	for _move: int in moves:
		Simulation.step(state, _commands(direction))
		while _player_walk(state).is_moving():
			Simulation.step(state, _commands(Command.NO_MOVE))


## A state with movement and the trail, like the basic instance, on this flow's own map and start.
func _state(seed_value: int) -> GameState:
	var ordered: Array[Feature] = [MovementFeature.new(), TrailFeature.new()]
	return _state_with(ordered, seed_value)


## A state with these features and one player, in slot 0 on START.
func _state_with(ordered: Array[Feature], seed_value: int) -> GameState:
	var state: GameState = GameState.new(RADIUS, seed_value, ordered)
	state.add_entity(0, START)
	return state


## The tile of the player in slot 0.
func _tile(state: GameState) -> Vector2i:
	return state.player(0).tile


func _movement(state: GameState) -> MovementFeature:
	return state.feature(Features.MOVEMENT) as MovementFeature


func _player_walk(state: GameState) -> Walk:
	return _movement(state).walk(state.player(0).id)


func _trails(state: GameState) -> TrailFeature:
	return state.feature(Features.TRAIL) as TrailFeature


## The trail of the player in slot 0.
func _trail(state: GameState) -> Trail:
	return _trails(state).trail(state.player(0).id)


## The state hash after every tick.
func _replay(moves: Array[int], seed_value: int) -> Array[int]:
	var state: GameState = _state(seed_value)
	var hashes: Array[int] = []
	for direction: int in moves:
		Simulation.step(state, _commands(direction))
		hashes.append(state.state_hash())
	return hashes


## A fixed mix of moves and pauses in every direction.
func _moves() -> Array[int]:
	var moves: Array[int] = []
	for tick: int in REPLAY_TICKS:
		moves.append(posmod(tick * 3 + tick % 11, Hex.DIRECTIONS.size() + 1) - 1)
	return moves


## One tick's commands with one player, in slot 0.
func _commands(direction: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(direction)]
	return commands


## One tick's commands for slots 0 and 1.
func _slot_commands(first: int, second: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(first), Command.new(second)]
	return commands


## A test rule like a boss phase: from tick `from_tick` on, it switches movement off, inside the
## tick and before movement steps.
class BossPhase:
	extends Feature

	var from_tick: int = 0

	func _init(start_tick: int) -> void:
		from_tick = start_tick

	func id() -> int:
		return 1000

	func step(state: GameState, _commands: Array[Command]) -> void:
		if state.tick >= from_tick:
			state.set_enabled(Features.MOVEMENT, false)

	func hash_values() -> Array[int]:
		var values: Array[int] = [from_tick]
		return values
