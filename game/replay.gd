class_name Replay
extends RefCounted
## A recorded session: how it started and every tick's commands for every player, enough to play it
## again and end in exactly the same state (#35). A session plays one world (#158): it starts in one
## instance and steps every instance a player walks into. The driver records every session; golden
## replays in tests/replays/ hold only their inputs, which CI plays on each commit and its parent
## (tests/replays/outcomes.gd, #876). Saved as JSON text by ReplayFile (#281). A session
## that resumed a saved world (#119) starts from that world, which the replay holds as its starting
## world.

## A checkpoint (the state hash) every this many ticks, and one at the end.
const CHECKPOINT_TICKS: int = 100
## One recorded change: the tick, the player slot, then the command's values.
const STRIDE: int = 2 + Command.VALUE_COUNT

var instance: String = ""
var seed_value: int = 0
## The world the session resumed (WorldData.of), or empty for one that started a fresh world from
## the instance and the seed.
var start_world: Dictionary = {}
var players: int = 1
## Each slot's carried monsters, in carried order, empty or null for none (#338, #53, #700): who
## the players brought, part of the start. The first a slot carries is its companion when the
## session starts.
var carried: Array[CarriedMonsters] = []
## The rules' id (RulesChanges) and the instance's feature ids when it was recorded: a replay of
## other rules would play out differently, so playback refuses it with a clear message. Both are
## empty in a replay of inputs only.
var rules: String = RulesChanges.id()
var features: Array[String] = []
var ticks: int = 0
## Every change of a slot's command, STRIDE integers each, in tick and slot order. A slot keeps its
## last command until it changes, so standing still or holding a direction costs nothing.
var changes: Array[int] = []
## The world's hash at checkpoint ticks, by tick.
var checkpoints: Dictionary[int, int] = {}
## Why the replay can't be read or played, or "" when it can.
var problem: String = ""
## The world at the end of the last play() or rehash().
var played: World
## Each slot's last recorded command values, while recording.
var _last: Dictionary[int, Array] = {}


## A replay of a session that starts in this instance, with this seed.
func _init(instance_name: String = "", seed_number: int = 0) -> void:
	instance = instance_name
	seed_value = seed_number


## Starts recording from `world` at its start: its players, what they carry and its starting
## instance's features.
func begin(world: World) -> void:
	features = _feature_ids(world.instances[instance])
	carried = CompanionParty.carried_in(world)
	players = 0
	for slot: int in GameState.MAX_PLAYERS:
		if world.player(slot) != null:
			players += 1


## Records one tick, right after `world` ran it with `commands`.
func record(world: World, commands: Array[Command]) -> void:
	ticks = world.tick
	var idle: Command = Command.new()
	for slot: int in players:
		var command: Command = Command.of(commands, slot)
		if command == null:
			command = idle
		var values: Array[int] = command.to_values()
		var previous: Array = _last.get(slot, [])
		if previous != values:
			_last[slot] = values
			changes.append(ticks)
			changes.append(slot)
			changes.append_array(values)
	if ticks % CHECKPOINT_TICKS == 0:
		checkpoints[ticks] = world.state_hash()


## Ends recording: the world's final hash becomes the last checkpoint.
func finish(world: World) -> void:
	checkpoints[world.tick] = world.state_hash()


## Plays the replay from its start, as fast as possible, and checks every checkpoint. Returns why
## it doesn't match, or "" when it does; `played` holds the final state.
func play() -> String:
	if problem.is_empty() and rules.is_empty():
		problem = "the replay holds only its inputs, with nothing recorded to check"
	if problem.is_empty() and rules != RulesChanges.id():
		problem = "recorded with rules %s, this build has %s" % [rules, RulesChanges.id()]
	if problem.is_empty():
		problem = _setup_problem()
	# Without a final checkpoint, a cut-off replay would pass without any state being compared.
	if problem.is_empty() and not checkpoints.has(ticks):
		problem = "the replay has no checkpoint at its last tick %d" % ticks
	if problem.is_empty():
		problem = _run(true)
	return problem


## Plays the replay under the current rules and takes them over, with fresh checkpoints: what a
## replay of inputs only plays out to in this build. Returns why it can't, or "".
func rehash() -> String:
	if problem.is_empty():
		problem = _setup_problem()
	if problem.is_empty():
		checkpoints.clear()
		problem = _run(false)
	# A replay that couldn't be played must never be written with empty checkpoints.
	if problem.is_empty() and (played == null or not checkpoints.has(ticks)):
		problem = "the replay couldn't be played under the current rules"
	if problem.is_empty():
		rules = RulesChanges.id()
		features = _feature_ids(played.instances[instance])
	return problem


## Why the replay can't be set up in this build, or "".
func _setup_problem() -> String:
	if not InstanceBlueprints.exists(instance) or players < 1 or players > GameState.MAX_PLAYERS:
		return "instance %s with %d players doesn't exist in this build" % [instance, players]
	if changes.size() % STRIDE != 0:
		return "the recorded commands are cut off"
	if carried.size() > GameState.MAX_PLAYERS:
		return "the replay has carried monsters for %d slots" % carried.size()
	for i: int in range(0, changes.size(), STRIDE):
		var after_previous: bool = i == 0 or changes[i] >= changes[i - STRIDE]
		if changes[i] < 1 or changes[i] > ticks or not after_previous:
			return "a recorded command is out of order or outside the session"
		if changes[i + 1] < 0 or changes[i + 1] >= players:
			return "a recorded command is for slot %d of %d players" % [changes[i + 1], players]
		var values: Array[int] = []
		values.assign(changes.slice(i + 2, i + STRIDE))
		if not Command.is_valid_values(values):
			return "a recorded command at tick %d is invalid: %s" % [changes[i], values]
	return ""


## Steps through every tick with the recorded commands. With `check`, compares the checkpoints
## and returns the first mismatch; without, records new ones.
func _run(check: bool) -> String:
	if start_world.is_empty():
		played = World.new(BlueprintSource.new(), seed_value, instance, players)
		CompanionParty.bring(played, carried)
	else:
		played = WorldData.to_world(start_world, BlueprintSource.new())
	if not played.problem.is_empty():
		return played.problem
	# An older replay names only the slots up to the last that brings one; the world names every
	# slot.
	var brought: Array[CarriedMonsters] = CompanionParty.carried_in(played)
	for slot: int in GameState.MAX_PLAYERS:
		var named: CarriedMonsters = carried[slot] if slot < carried.size() else null
		if not brought[slot].same_as(named):
			return "the replay's carried monsters of slot %d aren't its world's" % slot
	if not played.instances.has(instance):
		return "the replay's starting world doesn't hold its instance %s" % instance
	var start: Array[String] = _feature_ids(played.instances[instance])
	if check and start != features:
		return "the instance's features are now %s, recorded with %s" % [start, features]
	# Every slot starts idle; a recorded change replaces its command rather than changing it.
	var idle: Command = Command.new()
	var commands: Array[Command] = []
	for _slot: int in players:
		commands.append(idle)
	var next: int = 0
	while played.tick < ticks:
		while next < changes.size() and changes[next] == played.tick + 1:
			var values: Array[int] = []
			values.assign(changes.slice(next + 2, next + STRIDE))
			commands[changes[next + 1]] = Command.from_values(values)
			next += STRIDE
		played.step(commands)
		var mismatch: String = _checkpoint(check)
		if not mismatch.is_empty():
			return mismatch
	return ""


## Compares or records the checkpoint at the played world's tick, if there is one.
func _checkpoint(check: bool) -> String:
	var tick: int = played.tick
	var current: int = played.state_hash()
	if not check:
		if tick % CHECKPOINT_TICKS == 0 or tick == ticks:
			checkpoints[tick] = current
	elif checkpoints.has(tick) and checkpoints[tick] != current:
		return "tick %d: state hash %d, the replay expects %d" % [tick, current, checkpoints[tick]]
	return ""


static func _feature_ids(state: GameState) -> Array[String]:
	var ids: Array[String] = []
	for each: Feature in state.features:
		ids.append(each.id())
	return ids
