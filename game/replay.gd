class_name Replay
extends RefCounted
## A recorded session: how it started and every tick's commands for every player, enough to play it
## again and end in exactly the same state (#35). A session plays one world (#158): it starts in one
## instance and steps every instance a player walks into. The driver records every session; golden
## replays in tests/replays/ are played by CI. Saved as JSON text, with the seed and the hashes as
## strings, since JSON numbers can't hold every 64-bit integer exactly. A session that resumed a
## saved world (#119) starts from that world, which the replay holds as its starting world.

## The file format; a replay in another format is refused, not misread. Format 2 added the starting
## world; a format 1 replay has none and still plays.
const FORMAT: int = 2
## A checkpoint (the state hash) every this many ticks, and one at the end.
const CHECKPOINT_TICKS: int = 100
## One recorded change: the tick, the player slot, then the command's values.
const STRIDE: int = 2 + Command.VALUE_COUNT
const REQUIRED: Array[String] = ["format", "rules", "instance", "seed", "players", "ticks"]

var instance: String = ""
var seed_value: int = 0
## The world the session resumed (World.to_data), or empty for one that started a fresh world from
## the instance and the seed.
var start_world: Dictionary = {}
var players: int = 1
## The rules version and the instance's feature ids when it was recorded: a replay of other rules
## would play out differently, so playback refuses it with a clear message.
var rules: int = Simulation.RULES_VERSION
var features: Array[int] = []
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


## Starts recording from `world` at its start: its players and its starting instance's features.
func begin(world: World) -> void:
	features = _feature_ids(world.instances[instance])
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
	if problem.is_empty() and rules != Simulation.RULES_VERSION:
		problem = (
			"recorded with rules version %d, this build has %d; if the rules changed on purpose, "
			% [rules, Simulation.RULES_VERSION]
			+ "rehash the golden replays (tests/replays/rehash.gd)"
		)
	if problem.is_empty():
		problem = _setup_problem()
	# Without a final checkpoint, a cut-off replay would pass without any state being compared.
	if problem.is_empty() and not checkpoints.has(ticks):
		problem = "the replay has no checkpoint at its last tick %d" % ticks
	if problem.is_empty():
		problem = _run(true)
	return problem


## Plays the replay under the current rules and takes them over, with fresh checkpoints: for golden
## replays after a rules change made on purpose. Returns why it can't, or "".
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
		rules = Simulation.RULES_VERSION
		features = _feature_ids(played.instances[instance])
	return problem


func to_text() -> String:
	var hashes: Dictionary[String, String] = {}
	var sorted: Array[int] = []
	sorted.assign(checkpoints.keys())
	sorted.sort()
	for tick: int in sorted:
		hashes[str(tick)] = str(checkpoints[tick])
	var data: Dictionary[String, Variant] = {
		"format": FORMAT,
		"rules": rules,
		"instance": instance,
		"seed": str(seed_value),
		"players": players,
		"features": features,
		"ticks": ticks,
		"changes": changes,
		"checkpoints": hashes,
	}
	if not start_world.is_empty():
		data["world"] = start_world
	return JSON.stringify(data, "\t", false)


## A replay read from `text`; its `problem` says why when the text isn't a playable replay.
static func parse(text: String) -> Replay:
	var replay: Replay = Replay.new()
	# A JSON object reports a parse error through its result instead of logging it.
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		replay.problem = "not a replay"
		return replay
	var data: Dictionary = parsed
	replay.problem = _shape_problem(data)
	if not replay.problem.is_empty():
		return replay
	var format: int = _int(data["format"])
	if format < 1 or format > FORMAT:
		replay.problem = "replay format %d, this build reads up to format %d" % [format, FORMAT]
		return replay
	replay.start_world = _start_world(data.get("world", {}))
	if data.has("world") and replay.start_world.is_empty():
		replay.problem = "not a replay: its starting world isn't a world's data"
		return replay
	replay.rules = _int(data["rules"])
	replay.instance = str(data["instance"])
	replay.seed_value = str(data["seed"]).to_int()
	replay.players = _int(data["players"])
	replay.ticks = _int(data["ticks"])
	replay.features = _ints(data.get("features"))
	replay.changes = _ints(data.get("changes"))
	var by_tick: Dictionary = data.get("checkpoints", {})
	for tick: Variant in by_tick:
		replay.checkpoints[str(tick).to_int()] = str(by_tick[tick]).to_int()
	return replay


## The starting world in a replay's data, with JSON's numbers whole again; empty for none, or for
## one that isn't a world's data, which then fails to set up.
static func _start_world(saved: Variant) -> Dictionary:
	var none: Dictionary = {}
	if not saved is Dictionary or not WorldSave.has_whole_numbers(saved):
		return none
	var world: Dictionary = WorldSave.whole_numbers(saved)
	return world


## Why `data` doesn't have a replay's shape, or "": every field there and of its type, rather than
## silently read as 0.
static func _shape_problem(data: Dictionary) -> String:
	if not data.has_all(REQUIRED):
		return "not a replay: it lacks one of %s" % [REQUIRED]
	for key: String in ["format", "rules", "players", "ticks"]:
		if not _is_number(data[key]):
			return "not a replay: its %s isn't a number" % key
	if not data["seed"] is String or not str(data["seed"]).is_valid_int():
		return "not a replay: its seed isn't a whole number"
	for key: String in ["changes", "features"]:
		if not _all_numbers(data.get(key)):
			return "not a replay: its %s aren't a list of numbers" % key
	var hashes: Variant = data.get("checkpoints", {})
	if not _valid_checkpoints(hashes):
		return "not a replay: its checkpoints aren't ticks with hashes"
	return ""


static func _valid_checkpoints(hashes: Variant) -> bool:
	if not hashes is Dictionary:
		return false
	var by_tick: Dictionary = hashes
	for tick: Variant in by_tick:
		if not str(tick).is_valid_int() or not str(by_tick[tick]).is_valid_int():
			return false
	return true


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _all_numbers(values: Variant) -> bool:
	if not values is Array:
		return false
	var items: Array = values
	for item: Variant in items:
		if not _is_number(item):
			return false
	return true


## Why the replay can't be set up in this build, or "".
func _setup_problem() -> String:
	if not InstanceBlueprints.exists(instance) or players < 1 or players > GameState.MAX_PLAYERS:
		return "instance %s with %d players doesn't exist in this build" % [instance, players]
	if changes.size() % STRIDE != 0:
		return "the recorded commands are cut off"
	for i: int in range(0, changes.size(), STRIDE):
		var after_previous: bool = i == 0 or changes[i] >= changes[i - STRIDE]
		if changes[i] < 1 or changes[i] > ticks or not after_previous:
			return "a recorded command is out of order or outside the session"
		if changes[i + 1] < 0 or changes[i + 1] >= players:
			return "a recorded command is for slot %d of %d players" % [changes[i + 1], players]
		var values: Array[int] = []
		values.assign(changes.slice(i + 2, i + STRIDE))
		if not Command.from_values(values).is_valid():
			return "a recorded command at tick %d is invalid: %s" % [changes[i], values]
	return ""


## Steps through every tick with the recorded commands. With `check`, compares the checkpoints
## and returns the first mismatch; without, records new ones.
func _run(check: bool) -> String:
	if start_world.is_empty():
		played = World.new(seed_value, instance, players)
	else:
		played = World.from_data(start_world)
	if not played.problem.is_empty():
		return played.problem
	if not played.instances.has(instance):
		return "the replay's starting world doesn't hold its instance %s" % instance
	var start: Array[int] = _feature_ids(played.instances[instance])
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


static func _feature_ids(state: GameState) -> Array[int]:
	var ids: Array[int] = []
	for each: Feature in state.features:
		ids.append(each.id())
	return ids


## A JSON number (or anything else) as an integer.
static func _int(value: Variant) -> int:
	var number: int = type_convert(value, TYPE_INT)
	return number


## A JSON array as integers; empty for anything that isn't an array.
static func _ints(values: Variant) -> Array[int]:
	var result: Array[int] = []
	if values is Array:
		var items: Array = values
		for item: Variant in items:
			result.append(_int(item))
	return result
