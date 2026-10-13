class_name Replay
extends RefCounted
## A recorded run: how it started and every tick's commands for every player, enough to play it
## again and end in exactly the same state (#35). The driver records every run; golden replays in
## tests/replays/ are played by CI. Saved as JSON text, with the seed and the hashes as strings,
## since JSON numbers can't hold every 64-bit integer exactly.

## The file format; a replay in another format is refused, not misread.
const FORMAT: int = 1
## A checkpoint (the state hash) every this many ticks, and one at the end.
const CHECKPOINT_TICKS: int = 100
## One recorded change: the tick, the player slot, then the command's values.
const STRIDE: int = 2 + Command.VALUE_COUNT
const REQUIRED: Array[String] = ["format", "rules", "instance", "seed", "players", "ticks"]

var instance: String = ""
var seed_value: int = 0
var players: int = 1
## The rules version and the instance's feature ids when it was recorded: a replay of other rules
## would play out differently, so playback refuses it with a clear message.
var rules: int = Simulation.RULES_VERSION
var features: Array[int] = []
var ticks: int = 0
## Every change of a slot's command, STRIDE integers each, in tick and slot order. A slot keeps its
## last command until it changes, so standing still or holding a direction costs nothing.
var changes: Array[int] = []
## The state hash at checkpoint ticks, by tick.
var checkpoints: Dictionary[int, int] = {}
## Why the replay can't be read or played, or "" when it can.
var problem: String = ""
## The state at the end of the last play() or rehash().
var played: GameState
## Each slot's last recorded command values, while recording.
var _last: Dictionary[int, Array] = {}


## A replay of a run of this instance, seed and player count.
func _init(instance_name: String = "", seed_number: int = 0, player_count: int = 1) -> void:
	instance = instance_name
	seed_value = seed_number
	players = player_count


## Starts recording from `state`, the run's starting state.
func begin(state: GameState) -> void:
	features = _feature_ids(state)


## Records one tick, right after it ran with `commands`.
func record(state: GameState, commands: Array[Command]) -> void:
	ticks = state.tick
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
		checkpoints[ticks] = state.state_hash()


## Ends recording: the final state's hash becomes the last checkpoint.
func finish(state: GameState) -> void:
	checkpoints[state.tick] = state.state_hash()


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
	if problem.is_empty():
		rules = Simulation.RULES_VERSION
		features = _feature_ids(played)
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
	if not data.has_all(REQUIRED) or not data.get("changes") is Array:
		replay.problem = "not a replay: it lacks one of %s or its changes" % [REQUIRED]
		return replay
	var format: int = _int(data["format"])
	if format != FORMAT:
		replay.problem = "replay format %d, this build reads format %d" % [format, FORMAT]
		return replay
	replay.rules = _int(data["rules"])
	replay.instance = str(data["instance"])
	replay.seed_value = str(data["seed"]).to_int()
	replay.players = _int(data["players"])
	replay.ticks = _int(data["ticks"])
	replay.features = _ints(data.get("features"))
	replay.changes = _ints(data.get("changes"))
	var hashes: Variant = data.get("checkpoints")
	if hashes is Dictionary:
		var by_tick: Dictionary = hashes
		for tick: Variant in by_tick:
			replay.checkpoints[str(tick).to_int()] = str(by_tick[tick]).to_int()
	return replay


## Why the replay can't be set up in this build, or "".
func _setup_problem() -> String:
	if not Instances.exists(instance) or players < 1 or players > GameState.MAX_PLAYERS:
		return "instance %s with %d players doesn't exist in this build" % [instance, players]
	if changes.size() % STRIDE != 0:
		return "the recorded commands are cut off"
	for i: int in range(0, changes.size(), STRIDE):
		var after_previous: bool = i == 0 or changes[i] >= changes[i - STRIDE]
		if changes[i] < 1 or changes[i] > ticks or not after_previous:
			return "a recorded command is out of order or outside the run"
		if changes[i + 1] < 0 or changes[i + 1] >= players:
			return "a recorded command is for slot %d of %d players" % [changes[i + 1], players]
	return ""


## Steps through every tick with the recorded commands. With `check`, compares the checkpoints
## and returns the first mismatch; without, records new ones.
func _run(check: bool) -> String:
	played = Instances.create(instance, seed_value, players)
	if check and _feature_ids(played) != features:
		return "the instance's features are now %s, recorded with %s" % [
			_feature_ids(played),
			features,
		]
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
		Simulation.step(played, commands)
		var mismatch: String = _checkpoint(check)
		if not mismatch.is_empty():
			return mismatch
	return ""


## Compares or records the checkpoint at the played state's tick, if there is one.
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
