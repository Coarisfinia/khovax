extends RefCounted
## Replay flow: the simulation alone, without scenes, input or frames. The same start and the same
## commands must always give the same state, tick for tick; that is what makes replays and
## lockstep co-op possible. Also checks the game rules as features: movement in whole ticks, the
## trail, the feature order, and switching features off and on during a session.

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
		_check_rng_reference,
		_check_rng_ranges,
		_check_rng_rejection,
		_check_rng_bounds,
		_check_rolls_replay,
		_check_streams_apart,
		_check_rounding,
		_check_largest_amounts,
		_check_events_replay,
		_check_replay_round_trip,
		_check_replay_refusals,
		_check_replay_validation,
		_check_rehash,
		_check_golden_replays,
		_check_region_file,
		_check_arranged_regions,
		_check_terrain_blocks,
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
		Simulation.step(state, FlowSteps.command(EAST))
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
		Simulation.step(state, FlowSteps.command(direction))
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
		Simulation.step(last, FlowSteps.command(direction))
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
		"companion": func(state: GameState) -> void: state.companions[0] = "moss_toad",
		"terrain": func(state: GameState) -> void: state.region.terrain[START] = Region.WATER,
		"region tile": func(state: GameState) -> void: state.region.terrain[Vector2i(9, 9)] = 0,
		"region start": func(state: GameState) -> void: state.region.starts[0] += Vector2i.ONE,
		"next_entity_id": func(state: GameState) -> void: state.next_entity_id += 1,
		"entity id": func(state: GameState) -> void: state.player(0).id += 1,
		"entity slot": func(state: GameState) -> void: state.player(0).slot += 1,
		"entity tile.x": func(state: GameState) -> void: state.player(0).tile.x += 1,
		"entity tile.y": func(state: GameState) -> void: state.player(0).tile.y += 1,
		"an entity more": _add_unowned,
		"walk from.x": func(state: GameState) -> void: _player_walk(state).from.x += 1,
		"walk from.y": func(state: GameState) -> void: _player_walk(state).from.y += 1,
		"walk ticks_left": func(state: GameState) -> void: _player_walk(state).ticks_left += 1,
		"walk dropped": func(state: GameState) -> void: _movement(state).walks.clear(),
		"trail": func(state: GameState) -> void: _trail(state).tiles[Vector2i.ZERO] = 1,
		# Same size, other tile: the hash must see the coordinates, not only how many there are.
		"trail tile": func(state: GameState) -> void: _trail(state).tiles = { Vector2i.ZERO: 1 },
		# Same tile, someone else colored it (#87).
		"trail colorer": _recolor_trail,
		"trail dropped": func(state: GameState) -> void: _trail(state).tiles.clear(),
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
	var by: int = reordered.player(0).id
	_trail(reordered).tiles = {}
	for tile: Vector2i in shuffled:
		_trail(reordered).tiles[tile] = by
	var ordered: GameState = _state(42)
	_trail(ordered).tiles = {}
	for tile: Vector2i in after_two:
		_trail(ordered).tiles[tile] = by
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


## Rules can switch features during a session (e.g. a boss phase): off, a feature doesn't step and
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
	if InstanceBlueprints.basic(42, 1).feature(Features.TRAIL) == null:
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
	Simulation.step(state, FlowSteps.command(EAST))
	var first: Vector2i = _tile(state)
	for _tick: int in MovementFeature.MOVE_TICKS:
		Simulation.step(state, FlowSteps.command(EAST))
	if first != START + Hex.DIRECTIONS[EAST]:
		return "the player didn't move before the boss phase began"
	if _tile(state) != first or _movement(state).enabled:
		return "the boss phase didn't stop movement within its tick"
	return ""


## Co-op: every player is moved by the command in its own slot, all in the same tick, each with
## its own trail; a slot without a command stands still. Two players replay deterministically.
func _check_players_move_at_once() -> String:
	var state: GameState = InstanceBlueprints.basic(42, 2)
	var first: Entity = state.player(0)
	var second: Entity = state.player(1)
	var start_first: Vector2i = first.tile
	var start_second: Vector2i = second.tile
	Simulation.step(state, FlowSteps.commands([EAST, WEST]))
	if first.tile != start_first + Hex.DIRECTIONS[EAST]:
		return "the player in slot 0 didn't follow its own command"
	if second.tile != start_second + Hex.DIRECTIONS[WEST]:
		return "the player in slot 1 didn't move in the same tick by its own command"
	# Allies share one trail (#87), each tile remembering who colored it.
	var trail: Trail = _trails(state).shared
	if trail.tiles.get(first.tile, 0) != first.id or trail.tiles.get(second.tile, 0) != second.id:
		return "the players' tiles on the shared trail aren't their own"
	var only_first: Array[Command] = [Command.new(WEST)]
	for _tick: int in MovementFeature.MOVE_TICKS:
		Simulation.step(state, only_first)
	if second.tile != start_second + Hex.DIRECTIONS[WEST]:
		return "a slot without a command still moved its player"
	if _two_player_hash() != _two_player_hash():
		return "two players with the same commands gave different states"
	return ""


## The final state hash of two players replaying the scripted moves, each its own way.
func _two_player_hash() -> int:
	var state: GameState = InstanceBlueprints.basic(42, 2)
	for direction: int in _moves():
		var other: int = (direction + 2) % Hex.DIRECTIONS.size()
		Simulation.step(state, FlowSteps.commands([direction, other]))
	return state.state_hash()


## Entity ids are stable: removing an entity keeps the others' ids and drops every feature's data
## for it, and a new entity never gets a removed one's id.
func _check_entity_ids_stay() -> String:
	var state: GameState = InstanceBlueprints.basic(42, 3)
	var ids: Array[int] = []
	for each: Entity in state.entities:
		ids.append(each.id)
	# The player in slot 1, with entities before and after it (the wild monster, other players).
	var removed: int = state.player(1).id
	state.remove_entity(removed)
	if state.entity(removed) != null or ids.size() != state.entities.size() + 1:
		return "removing an entity took the wrong one or more than one"
	if _movement(state).walk(removed) != null:
		return "a removed entity's walk stayed behind"
	var added: Entity = state.add_entity(1, START)
	if ids.has(added.id):
		return "a new entity got the id %d again" % added.id
	if state.player(1) != added or _movement(state).walk(added.id) == null:
		return "a player added during a session doesn't walk in its slot"
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


## The generator is xoshiro128**: from a given state it gives the reference implementation's
## values, and seeding gives fixed values. A changed algorithm or seeding fails here, since it
## would change every replay.
func _check_rng_reference() -> String:
	var published: Array[int] = [11_520, 0, 5_927_040, 70_819_200, 2_031_721_883, 1_637_235_492]
	var state: Array[int] = [1, 2, 3, 4]
	if _draws(Rng.from_words(state), published.size()) != published:
		return "the generator doesn't match xoshiro128**'s reference values"
	var seeded: Dictionary[Vector2i, Array] = {
		Vector2i(42, 0): [110_243_625, 433_212_580, 1_876_866_330],
		Vector2i(42, 1): [4_072_672_004, 3_458_259_917, 3_159_487_900],
		Vector2i(-1, 7): [436_908_351, 602_727_565, 1_259_044_426],
	}
	for key: Vector2i in seeded:
		var expected: Array[int] = []
		expected.assign(seeded[key])
		if _seeded_draws(key.x, key.y, expected.size()) != expected:
			return "seed %d, stream %d gives other values than before" % [key.x, key.y]
	return ""


## Ranges stay in bounds and reach every value; chances and weighted picks respect their odds.
func _check_rng_ranges() -> String:
	var rng: Rng = Rng.new(42, 0)
	var seen: Dictionary[int, bool] = {}
	for _draw: int in 700:
		var value: int = rng.between(-3, 3)
		if value < -3 or value > 3:
			return "between(-3, 3) gave %d" % value
		seen[value] = true
	if seen.size() != 7:
		return "between(-3, 3) never gave some values: %s" % [seen.keys()]
	for _draw: int in 100:
		if rng.below(1) != 0 or rng.below(Rng.SPAN) >= Rng.SPAN:
			return "below() left its range at the edges"
		if rng.chance(0, 10) or not rng.chance(10, 10):
			return "a chance of 0 or 1 didn't hold"
	var picked: Dictionary[int, bool] = {}
	var weights: Array[int] = [0, 5, 0, 1]
	for _draw: int in 200:
		picked[rng.pick_weighted(weights)] = true
	if picked.has(0) or picked.has(2) or not picked.has(1) or not picked.has(3):
		return "weighted picks gave %s for weights %s" % [picked.keys(), weights]
	return ""


## below() draws again rather than folding a draw in with modulo: with 2^31 + 1 values, every draw
## at or above 2^31 + 1 (about half of them) is rejected, and the next draw is used.
func _check_rng_rejection() -> String:
	var count: int = (Rng.SPAN >> 1) + 1
	var rng: Rng = Rng.new(42, 0)
	var raw: Rng = Rng.new(42, 0)
	var rejected: int = 0
	for _draw: int in 20:
		var drawn: int = raw.next_u32()
		while drawn >= count:
			rejected += 1
			drawn = raw.next_u32()
		if rng.below(count) != drawn:
			return "below(2^31 + 1) didn't skip exactly the draws it must reject"
	if rejected == 0:
		return "no draw was rejected, so the check proves nothing"
	return ""


## The widest ranges, 2^32 values, work at both ends of the signed 64-bit integers.
func _check_rng_bounds() -> String:
	var rng: Rng = Rng.new(42, 0)
	var lowest: int = -9_223_372_036_854_775_807 - 1
	var highest: int = 9_223_372_036_854_775_807
	for _draw: int in 100:
		var low_end: int = rng.between(lowest, lowest + Rng.SPAN - 1)
		if low_end < lowest or low_end > lowest + Rng.SPAN - 1:
			return "between() at the lowest integers gave %d" % low_end
		var high_end: int = rng.between(highest - Rng.SPAN + 1, highest)
		if high_end < highest - Rng.SPAN + 1:
			return "between() at the highest integers gave %d" % high_end
	return ""


## A feature rolling from its own stream every tick replays to the same state, its stream is in
## the hash, and another seed rolls differently.
func _check_rolls_replay() -> String:
	if _dice_hash(42) != _dice_hash(42):
		return "rolls from the same seed gave different states"
	if _dice_hash(42) == _dice_hash(43):
		return "another seed rolled the same"
	var state: GameState = _dice_state(42)
	var before: int = state.state_hash()
	var dice: Dice = state.feature(Dice.ID) as Dice
	dice.rng.words[3] ^= 1
	if state.state_hash() == before:
		return "the generator's state isn't in the hash"
	return ""


## Streams keep systems apart: a feature rolling more often never changes another one's rolls.
func _check_streams_apart() -> String:
	var calm: GameState = _two_dice(1)
	var busy: GameState = _two_dice(3)
	for _tick: int in 50:
		Simulation.step(calm, FlowSteps.command(Command.NO_MOVE))
		Simulation.step(busy, FlowSteps.command(Command.NO_MOVE))
	var other: int = Dice.ID + 1
	if calm.feature(other).hash_values() != busy.feature(other).hash_values():
		return "more rolls in one feature shifted another feature's rolls"
	if calm.feature(Dice.ID).hash_values() == busy.feature(Dice.ID).hash_values():
		return "the busier dice didn't roll more"
	return ""


## A state with two dice features: the first rolls `rolls` times a tick, the second once.
func _two_dice(rolls: int) -> GameState:
	var ordered: Array[Feature] = [Dice.new(Dice.ID, rolls), Dice.new(Dice.ID + 1, 1)]
	return _state_with(ordered, 42)


## The first `count` values of a freshly seeded stream.
func _seeded_draws(seed_value: int, stream: int, count: int) -> Array[int]:
	return _draws(Rng.new(seed_value, stream), count)


## Every division rounds down, toward negative infinity, whatever the signs; ratios and scales
## are in thousandths.
func _check_rounding() -> String:
	# Dividend, divisor, quotient rounded down.
	var cases: Array[Vector3i] = [
		Vector3i(7, 2, 3),
		Vector3i(-7, 2, -4),
		Vector3i(7, -2, -4),
		Vector3i(-7, -2, 3),
		Vector3i(6, 3, 2),
		Vector3i(-6, 3, -2),
		Vector3i(0, 5, 0),
		Vector3i(-1, 1000, -1),
	]
	for each: Vector3i in cases:
		if Fixed.div_floor(each.x, each.y) != each.z:
			return "%d / %d gave %d, not %d" % [
				each.x,
				each.y,
				Fixed.div_floor(each.x, each.y),
				each.z,
			]
	if Fixed.ratio(1, 3) != 333 or Fixed.ratio(2, 3) != 666 or Fixed.ratio(-1, 3) != -334:
		return "ratios in thousandths don't round down"
	if Fixed.scale(10, 1500) != 15 or Fixed.scale(7, 500) != 3 or Fixed.scale(-7, 500) != -4:
		return "scaling by thousandths doesn't round down"
	# The design report's pressure: strength × hp / max_hp, here 300 × 2 / 3.
	if Fixed.mul_div(300, 2, 3) != 200 or Fixed.mul_div(1, 1, 3) != 0:
		return "multiply, then divide, lost or kept the wrong part"
	return ""


## The largest amounts the formulas can see multiply without overflowing.
func _check_largest_amounts() -> String:
	var most: int = Fixed.MAX_AMOUNT
	if Fixed.mul_div(most, most, most) != most:
		return "the largest amounts overflowed when multiplied"
	if Fixed.mul_div(-most, most, 1) != -most * most:
		return "the most negative product came out wrong"
	# 10^18 / 7, rounded down.
	if Fixed.mul_div(most, most, 7) != 142_857_142_857_142_857:
		return "a large product divided wrongly"
	# The design report's segment integrity: ring power × ONE / perimeter, at its extremes.
	if Fixed.mul_div(most, Fixed.ONE, 1) != most * Fixed.ONE:
		return "the largest ring power per segment overflowed"
	return ""


## Events are part of what a replay reproduces, though not of the hash: the same start and commands
## raise the same events, tick by tick.
func _check_events_replay() -> String:
	var first: Array = _event_log(42)
	if first.is_empty():
		return "the scripted moves raised no events, so the check proves little"
	if _event_log(42) != first:
		return "the same start and commands raised different events"
	return ""


## Every event of a replay, in order: its tick, its class and the values of its script variables,
## so any kind of event counts, not only the kinds that exist today.
func _event_log(seed_value: int) -> Array:
	var state: GameState = _state(seed_value)
	# Not "log": that would shadow the global log() and fail the script check.
	var raised: Array = []
	for direction: int in _moves():
		Simulation.step(state, FlowSteps.command(direction))
		for event: RefCounted in state.events:
			raised.append(state.tick)
			raised.append(_event_values(event))
	return raised


## An event's class and the values of its script variables, in declaration order.
func _event_values(event: RefCounted) -> Array:
	var script_of: Script = event.get_script()
	var values: Array = [script_of.get_global_name()]
	for property: Dictionary in event.get_property_list():
		var usage: int = property["usage"]
		var property_name: String = property["name"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values.append(event.get(property_name))
	return values


## A recorded session survives saving and loading, and plays back to exactly the same state; a
## changed command makes playback name the first checkpoint that differs.
func _check_replay_round_trip() -> String:
	var recorded: Replay = _recorded_run()
	var loaded: Replay = ReplayFile.parse(ReplayFile.to_text(recorded))
	var problem: String = loaded.play()
	if not problem.is_empty():
		return "a saved and loaded replay didn't play back: " + problem
	if loaded.played.state_hash() != recorded.played.state_hash():
		return "the played-back session ended in another state than the recorded one"
	var tampered: Replay = ReplayFile.parse(ReplayFile.to_text(recorded))
	# The first change is tick 1, slot 0: walking another way changes the game from there.
	tampered.changes[2] = (tampered.changes[2] + 2) % Hex.DIRECTIONS.size()
	if not tampered.play().begins_with("tick %d:" % Replay.CHECKPOINT_TICKS):
		return "a changed command played without a mismatch at the first checkpoint"
	# Who the players brought is part of the start (#338): other companions play another game.
	var swapped: Replay = ReplayFile.parse(ReplayFile.to_text(recorded))
	swapped.companions.reverse()
	if loaded.companions != recorded.companions or swapped.play().is_empty():
		return "the replay didn't keep its companions, or played with others all the same"
	return ""


## Playback refuses, with a clear message, what this build can't play as recorded.
func _check_replay_refusals() -> String:
	var text: String = ReplayFile.to_text(_recorded_run())
	var cases: Dictionary[String, String] = {
		"not json": "not a replay",
		"{}": "not a replay",
		text.replace("\"format\": %d" % ReplayFile.FORMAT, "\"format\": 99"): "replay format 99",
		text.replace(
			"\"rules\": %d" % Simulation.RULES_VERSION,
			"\"rules\": 0",
		): "recorded with rules",
		text.replace("\"basic\"", "\"nowhere\""): "instance nowhere",
		text.replace("\"players\": 2", "\"players\": 9"): "instance basic with 9 players",
	}
	for case: String in cases:
		var problem: String = ReplayFile.parse(case).play()
		if not problem.begins_with(cases[case]):
			return "expected a refusal starting %s, got: %s" % [cases[case], problem]
	return ""


## Playback refuses replays it can't verify or whose values are malformed, rather than reading
## them as zeros or playing commands a player can't give.
func _check_replay_validation() -> String:
	var recorded: Replay = _recorded_run()
	var text: String = ReplayFile.to_text(recorded)
	var unchecked: Replay = ReplayFile.parse(text)
	var _erased: bool = unchecked.checkpoints.erase(unchecked.ticks)
	var invalid_move: Replay = ReplayFile.parse(text)
	invalid_move.changes[2] = Hex.DIRECTIONS.size() + 3
	var cases: Dictionary[String, String] = {
		ReplayFile.to_text(unchecked): "the replay has no checkpoint at its last tick",
		ReplayFile.to_text(invalid_move): "a recorded command at tick 1 is invalid",
		text.replace("\"seed\": \"42\"", "\"seed\": \"x\""): "not a replay: its seed",
		text.replace("\"changes\": [", "\"changes\": [\"bad\","): "not a replay: its changes",
		text.replace("\"companions\": [", "\"companions\": [1,"): "not a replay: its companions",
		text.replace("\"ticks\": ", "\"ticks\": \"many\", \"was\": "): "not a replay: its ticks",
	}
	for case: String in cases:
		var problem: String = ReplayFile.parse(case).play()
		if not problem.begins_with(cases[case]):
			return "expected a refusal starting %s, got: %s" % [cases[case], problem]
	return ""


## Rehashing, as tests/replays/rehash.gd does for golden replays, fills in the checkpoints of a
## replay that has only its start and commands; under unchanged rules they are the recorded ones.
func _check_rehash() -> String:
	var recorded: Replay = _recorded_run()
	var bare: Replay = ReplayFile.parse(ReplayFile.to_text(recorded))
	bare.checkpoints.clear()
	var problem: String = bare.rehash()
	if not problem.is_empty():
		return "rehashing failed: " + problem
	if bare.checkpoints != recorded.checkpoints:
		return "rehashing under the same rules gave other checkpoints"
	if not ReplayFile.parse(ReplayFile.to_text(bare)).play().is_empty():
		return "a rehashed replay doesn't play back"
	return ""


## Every golden replay in tests/replays/ plays back to its recorded checkpoints. One that fails
## means the rules changed what it does: on purpose, bump Simulation.RULES_VERSION and rehash
## (tests/replays/rehash.gd), and say why in the pull request.
func _check_golden_replays() -> String:
	var folder: String = "res://tests/replays/"
	var played: int = 0
	for file_name: String in DirAccess.get_files_at(folder):
		if file_name.ends_with(".replay"):
			var text: String = FileAccess.get_file_as_string(folder + file_name)
			var problem: String = ReplayFile.parse(text).play()
			if not problem.is_empty():
				return "golden replay %s: %s" % [file_name, problem]
			played += 1
	if played == 0:
		return "no golden replays in " + folder
	return ""


## A session of two players walking the scripted moves, each with a companion (#338), recorded and
## played once.
func _recorded_run() -> Replay:
	var world: World = World.new(42, InstanceBlueprints.BASIC, 2, ["storm_finch", "moss_toad"])
	var recorded: Replay = Replay.new(InstanceBlueprints.BASIC, 42)
	recorded.begin(world)
	for direction: int in _moves():
		var commands: Array[Command] = FlowSteps.commands([direction, Command.NO_MOVE])
		world.step(commands)
		recorded.record(world, commands)
	recorded.finish(world)
	recorded.played = world
	return recorded


## The basic instance's region file reads as the disc it draws, with the players' starts and its
## wild monster, and a broken region file says what is wrong.
func _check_region_file() -> String:
	var region: Region = InstanceBlueprints.basic(42).region
	var starts: Array[Vector2i] = [
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
	]
	if region.sorted_tiles() != Region.disc(RADIUS).sorted_tiles() or region.starts != starts:
		return "regions/basic.md isn't the disc of radius 3 with its four starts"
	if region.wild_monsters != ([Vector2i(-2, 0)] as Array[Vector2i]):
		return "regions/basic.md's wild monster isn't on (-2, 0): %s" % [region.wild_monsters]
	var broken: Dictionary[String, String] = {
		". . .": "a region file starts with",
		"origin 0 0\n. .. .": "'.' in row 0 sits between two tiles",
		"origin 0 0\n. ? .": "'?' in row 0 isn't a region symbol",
		"origin 0 0\n. 2 .": "the player starts aren't numbered",
		"origin nope 3\n. .": "a region file starts with",
		"origin 0 0\n1 . 1": "player 1's start is marked twice",
		"origin 0 0\n. .\nconnector 0 0": "a connector line reads",
		"origin 0 0\n. .\nconnector 0 0 6": "connector side 6 isn't 0 to 5",
		"origin 0 0\n. .\nconnector 0 0 0": "connector (0, 0) doesn't open",
	}
	for text: String in broken:
		if not RegionFormat.parse(text).problem.begins_with(broken[text]):
			return "region file %s gave: %s" % [text.c_escape(), RegionFormat.parse(text).problem]
	# Tiles left of the origin and rows above it have negative coordinates.
	var left: Region = RegionFormat.parse("origin 4 1\n ~ ^\n1 . .")
	var expected: Dictionary[Vector2i, int] = {
		Vector2i(-1, -1): Region.WATER,
		Vector2i(0, -1): Region.BLOCKED,
		Vector2i(-2, 0): Region.GROUND,
		Vector2i(-1, 0): Region.GROUND,
		Vector2i(0, 0): Region.GROUND,
	}
	var start: Array[Vector2i] = [Vector2i(-2, 0)]
	if left.terrain != expected or left.starts != start:
		return "negative coordinates read as %s, starts %s" % [left.terrain, left.starts]
	return ""


## Region pieces (#57): the glade arranges for every seed, the same way for the same seed, from all
## its pieces without overlaps, with all its ground connected to the start. Turning off keeps the
## start piece as it is, and a piece without a fitting connector is refused.
func _check_arranged_regions() -> String:
	var pieces: Array[Region] = _glade_pieces()
	for seed_value: int in 40:
		var problem: String = _check_glade(seed_value, pieces)
		if not problem.is_empty():
			return problem
	for check: Callable in [_check_connector_fit, _check_turning]:
		var misfit: String = check.call()
		if not misfit.is_empty():
			return misfit
	if RegionArranger.arrange(pieces, 7, false).starts != pieces[0].starts:
		return "an unturned arrangement moved the start piece"
	if pieces[0].fits(pieces[0], Vector2i.ZERO):
		return "a piece fits onto tiles the region already has"
	var closed: Array[Region] = [pieces[0], Region.disc(1)]
	if not RegionArranger.arrange(closed, 7, true).problem.begins_with("region piece 1 fits"):
		return "a piece without connectors was placed"
	return ""


## Hex.turn goes round DIRECTIONS. Two one-tile pieces, each with one connector: the second lands
## right next to the first, on the side the first opens to, whichever way its own connector faces
## before it's turned (sides 3 and 0 need no turn and three turns). The first piece's player start
## stays where it was.
func _check_connector_fit() -> String:
	for turns: int in 6:
		if Hex.turn(Hex.DIRECTIONS[0], turns) != Hex.DIRECTIONS[turns]:
			return "Hex.turn doesn't follow DIRECTIONS round: %d turns" % turns
	var first: Region = RegionFormat.parse("origin 0 0\n1\nconnector 0 0 0")
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	for side: int in [3, 0]:
		var second: Region = RegionFormat.parse("origin 0 0\n.\nconnector 0 0 %d" % side)
		var pair: Array[Region] = [first, second]
		var region: Region = RegionArranger.arrange(pair, 1, false)
		var placed: bool = region.sorted_tiles() == expected and region.starts == first.starts
		if not placed or not region.connectors.is_empty():
			return "a piece opening to side %d landed on %s" % [side, region.sorted_tiles()]
	return ""


## Turning is the blueprint's switch (#127): the glade's pieces, arranged with turning on, turn
## more than one way, while the arena, one piece the seeds never turn, loads for every seed exactly
## as its file is drawn, and takes four players.
func _check_turning() -> String:
	var folder: String = InstanceBlueprints.REGIONS + InstanceBlueprints.ARENA + "/"
	var drawn: Region = RegionDocument.parse(FileAccess.get_file_as_string(folder + "start.md"))
	var pieces: Array[Region] = _glade_pieces()
	var glade_starts: Dictionary[Vector2i, bool] = {}
	for seed_value: int in 12:
		var glade: Region = RegionArranger.arrange(pieces, seed_value, true)
		glade_starts[glade.starts[1]] = true
		var arena: Region = InstanceBlueprints.region_of(InstanceBlueprints.ARENA, seed_value)
		if not arena.problem.is_empty() or arena.hash_values() != drawn.hash_values():
			return "seed %d loaded the arena unlike its file: %s" % [seed_value, arena.problem]
	if glade_starts.size() < 2:
		return "no seed turned the glade"
	if InstanceBlueprints.create(InstanceBlueprints.ARENA, 3, 4) == null:
		return "the arena doesn't take four players"
	return ""


## The glade arranged for one seed: every piece's tiles, the same twice, all ground reachable.
func _check_glade(seed_value: int, pieces: Array[Region]) -> String:
	var tiles: int = 0
	for piece: Region in pieces:
		tiles += piece.size()
	var region: Region = InstanceBlueprints.region_of(InstanceBlueprints.GLADE, seed_value)
	var again: Region = InstanceBlueprints.region_of(InstanceBlueprints.GLADE, seed_value)
	if not region.problem.is_empty() or region.size() != tiles:
		var found: Array = [seed_value, region.size(), tiles, region.problem]
		return "seed %d arranged %d of %d tiles: %s" % found
	if region.hash_values() != again.hash_values():
		return "seed %d arranged the glade two different ways" % seed_value
	var ground: int = region.sorted_tiles().filter(region.is_walkable).size()
	if region.reachable(region.starts[0]).size() != ground:
		return "seed %d left ground the start can't reach" % seed_value
	return ""


## The glade's region pieces, read straight from their files.
func _glade_pieces() -> Array[Region]:
	var folder: String = InstanceBlueprints.REGIONS + InstanceBlueprints.GLADE + "/"
	var pieces: Array[Region] = []
	for file: String in ["start.md", "pond.md", "thicket.md"]:
		pieces.append(RegionDocument.parse(FileAccess.get_file_as_string(folder + file)))
	return pieces


## Water and rock stop a walker like the region's edge does.
func _check_terrain_blocks() -> String:
	var state: GameState = _state(42)
	state.region.terrain[START + Hex.DIRECTIONS[EAST]] = Region.WATER
	state.region.terrain[START + Hex.DIRECTIONS[WEST]] = Region.BLOCKED
	_walk(state, EAST, 1)
	_walk(state, WEST, 1)
	if _tile(state) != START:
		return "the player walked onto water or rock, to %s" % _tile(state)
	return ""


## The next `count` 32-bit values.
func _draws(rng: Rng, count: int) -> Array[int]:
	var values: Array[int] = []
	for _draw: int in count:
		values.append(rng.next_u32())
	return values


## A state with movement and a feature rolling dice, one player on START.
func _dice_state(seed_value: int) -> GameState:
	var ordered: Array[Feature] = [MovementFeature.new(), Dice.new()]
	return _state_with(ordered, seed_value)


## The hash after a series of rolls.
func _dice_hash(seed_value: int) -> int:
	var state: GameState = _dice_state(seed_value)
	for direction: int in _moves():
		Simulation.step(state, FlowSteps.command(direction))
	return state.state_hash()


## Moves `moves` tiles in one direction, waiting for each move to arrive.
func _walk(state: GameState, direction: int, moves: int) -> void:
	for _move: int in moves:
		Simulation.step(state, FlowSteps.command(direction))
		while _player_walk(state).is_moving():
			Simulation.step(state, FlowSteps.command(Command.NO_MOVE))


## A state with movement and the trail, like the basic instance, on this flow's own region and
## start.
func _state(seed_value: int) -> GameState:
	var ordered: Array[Feature] = [MovementFeature.new(), TrailFeature.new()]
	return _state_with(ordered, seed_value)


## A state with these features and one player, in slot 0 on START.
func _state_with(ordered: Array[Feature], seed_value: int) -> GameState:
	var state: GameState = GameState.new(Region.disc(RADIUS), seed_value, ordered)
	var _player: Entity = state.add_entity(0, START)
	return state


## Adds an entity no player owns.
func _add_unowned(state: GameState) -> void:
	var _added: Entity = state.add_entity(Entity.NO_SLOT, START)


## The tile of the player in slot 0.
func _tile(state: GameState) -> Vector2i:
	return state.player(0).tile


func _movement(state: GameState) -> MovementFeature:
	return state.feature(Features.MOVEMENT) as MovementFeature


func _player_walk(state: GameState) -> Walk:
	return _movement(state).walk(state.player(0).id)


func _trails(state: GameState) -> TrailFeature:
	return state.feature(Features.TRAIL) as TrailFeature


## The allies' shared trail (#87).
func _trail(state: GameState) -> Trail:
	return _trails(state).shared


## Gives the start tile to another colorer than the player who colored it.
func _recolor_trail(state: GameState) -> void:
	_trail(state).tiles[START] = _trail(state).tiles[START] + 1


## The state hash after every tick.
func _replay(moves: Array[int], seed_value: int) -> Array[int]:
	var state: GameState = _state(seed_value)
	var hashes: Array[int] = []
	for direction: int in moves:
		Simulation.step(state, FlowSteps.command(direction))
		hashes.append(state.state_hash())
	return hashes


## A fixed mix of moves and pauses in every direction.
func _moves() -> Array[int]:
	var moves: Array[int] = []
	for tick: int in REPLAY_TICKS:
		moves.append(posmod(tick * 3 + tick % 11, Hex.DIRECTIONS.size() + 1) - 1)
	return moves


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


## A test rule that rolls a die `rolls` times every tick from its own stream, like monster
## behavior will.
class Dice:
	extends Feature

	const ID: int = 1001

	var feature_id: int = ID
	var rolls: int = 1
	var rng: Rng
	var last: int = 0

	func _init(id_value: int = ID, rolls_per_tick: int = 1) -> void:
		feature_id = id_value
		rolls = rolls_per_tick

	func id() -> int:
		return feature_id

	func start(state: GameState) -> void:
		rng = Rng.new(state.rng_seed, feature_id)

	func step(_state: GameState, _commands: Array[Command]) -> void:
		for _roll: int in rolls:
			last = rng.between(1, 6)

	func hash_values() -> Array[int]:
		var values: Array[int] = [last]
		values.append_array(rng.hash_values())
		return values
