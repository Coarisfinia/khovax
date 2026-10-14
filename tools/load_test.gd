# gdstyle:ignore-file=quality/no-debug-print
# The tool reports its measurements on stdout; that is what it is for.
extends SceneTree
## The load test (#101): the load instance (maps/load.map, a big map full of wild monsters, with
## the same rules as every instance) under four players walking by script.
##
## Headless, it times the simulation: every tick and every feature's share, and runs twice to
## check both end in the same state hash:
##   godot --headless --path . -s res://tools/load_test.gd -- ticks=2000
## Rendered, it runs the real main scene on the load instance and times frames:
##   godot --path . -s res://tools/load_test.gd -- rendered seconds=20
## The numbers belong in the PR or issue that measured them, never in docs.

const SEED: int = 101
const PLAYERS: int = 4
## Ticks each scripted walk keeps one direction before turning.
const LEG_TICKS: int = 12
const ACTIONS: Array[String] = ["move_right", "move_up", "move_left", "move_down"]

var _ticks: int = 2000
var _seconds: float = 20.0
## Rendered: when the run started, and each frame's duration in microseconds.
var _started_usec: int = 0
var _last_usec: int = 0
var _frames: Array[int] = []


func _process(_delta: float) -> bool:
	if _started_usec == 0:
		return false
	var now: int = Time.get_ticks_usec()
	_frames.append(now - _last_usec)
	_last_usec = now
	# One action held at a time, turning every LEG_TICKS ticks' worth of time.
	var ticks_so_far: float = (now - _started_usec) / 1_000_000.0 * Simulation.TICKS_PER_SECOND
	var leg: int = floori(ticks_so_far / LEG_TICKS)
	for i: int in ACTIONS.size():
		if i == leg % ACTIONS.size():
			Input.action_press(ACTIONS[i])
		else:
			Input.action_release(ACTIONS[i])
	if now - _started_usec < _seconds * 1_000_000.0:
		return false
	_report_rendered()
	return true


func _report_rendered() -> void:
	print("rendered load: %d frames in %.1f s" % [_frames.size(), _seconds])
	_print_spread("frame", _frames)


func _initialize() -> void:
	var rendered: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "rendered":
			rendered = true
		elif arg.begins_with("ticks="):
			_ticks = arg.trim_prefix("ticks=").to_int()
		elif arg.begins_with("seconds="):
			_seconds = arg.trim_prefix("seconds=").to_float()
	if rendered:
		_start_rendered()
	else:
		_run_headless()


func _run_headless() -> void:
	var first: LoadRun = _simulate(true)
	var second: LoadRun = _simulate(false)
	print("headless load: %d ticks, %d entities at the start, %d catches" % [
		_ticks,
		first.entities,
		first.catches,
	])
	_print_spread("tick", first.ticks)
	for feature_id: int in first.features:
		var per_tick: float = first.features[feature_id] / float(_ticks)
		print("  feature %d: %.1f us per tick" % [feature_id, per_tick])
	var same: bool = first.end_hash == second.end_hash
	print("end state hash %d, %s" % [first.end_hash, "same in both runs" if same else "DIFFERS"])
	quit(0 if same else 1)


## One headless run, timed when `timed`.
func _simulate(timed: bool) -> LoadRun:
	var state: GameState = Instances.create(Instances.LOAD, SEED, PLAYERS)
	var run: LoadRun = LoadRun.new()
	run.entities = state.entities.size()
	for tick: int in _ticks:
		var commands: Array[Command] = _commands(tick)
		var start: int = Time.get_ticks_usec()
		run.mark = start
		Simulation.step(state, commands, run.observe if timed else Callable())
		run.ticks.append(Time.get_ticks_usec() - start)
		run.count_catches(state.events)
	run.end_hash = state.state_hash()
	return run


## Each player walks in a direction of its own, turning every LEG_TICKS ticks.
func _commands(tick: int) -> Array[Command]:
	var leg: int = floori(float(tick) / LEG_TICKS)
	var commands: Array[Command] = []
	commands.assign(range(PLAYERS).map(
		func(slot: int) -> Command: return Command.new((leg + slot * 2) % Hex.DIRECTIONS.size())
	))
	return commands


func _start_rendered() -> void:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	driver.instance = Instances.LOAD
	# Uncapped, so the frame times show the real cost, not the display's refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.add_child(main)
	_started_usec = Time.get_ticks_usec()
	_last_usec = _started_usec


func _print_spread(what: String, samples: Array[int]) -> void:
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return
	var total: int = 0
	for sample: int in sorted:
		total += sample
	print("  %s: mean %.1f us, median %d us, 95th %d us, max %d us" % [
		what,
		float(total) / sorted.size(),
		sorted[floori(sorted.size() * 0.5)],
		sorted[floori(sorted.size() * 0.95)],
		sorted[sorted.size() - 1],
	])


## One headless run's measurements.
class LoadRun:
	extends RefCounted

	## Each tick's duration, in microseconds.
	var ticks: Array[int] = []
	## Each feature's total time over the run, in microseconds, by feature id.
	var features: Dictionary[int, int] = {}
	var entities: int = 0
	var catches: int = 0
	var end_hash: int = 0
	## When the last feature finished, or the tick started.
	var mark: int = 0

	## Called by Simulation.step after each feature: adds the time since the last mark to it.
	func observe(feature: Feature) -> void:
		var now: int = Time.get_ticks_usec()
		features[feature.id()] = features.get(feature.id(), 0) + now - mark
		mark = now

	func count_catches(events: Array[RefCounted]) -> void:
		for event: RefCounted in events:
			if event is WildMonsterCaught:
				catches += 1
