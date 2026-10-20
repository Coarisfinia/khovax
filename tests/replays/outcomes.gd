# gdstyle:ignore-file=quality/no-debug-print
# The tool reports to whoever runs it on stdout and stderr; that is what it is for.
extends SceneTree
## The outcome report (#876, step 2): how this build plays the reference replays and the APK's e2e
## flow, written as JSON for CI to compare with the parent commit's build:
## godot --headless --path . -s res://tests/replays/outcomes.gd -- out=<absolute path>
## [--user-dir=<name>]
## Each replay in tests/replays/ is played twice under this build's rules, ignoring its committed
## checkpoints, and the two plays must match: the report holds its state hash at every checkpoint
## tick and its final hash. The APK flow (tests/e2e/test_apk_flow.gd) runs as in the headless e2e
## tests, and the report holds the game's final state hash.
## Exits non-zero and writes no report when a play differs, a replay or the flow fails, or any
## error is logged (a script that doesn't compile logs one), so a broken build never reports
## success.

const REPLAYS: String = "res://tests/replays/"
const APK_FLOW: String = "res://tests/e2e/test_apk_flow.gd"
const OUT: String = "out="

var _errors: ErrorCounter = ErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(_errors)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = ""
	for arg: String in args:
		if arg.begins_with(OUT):
			out = arg.trim_prefix(OUT)
	var options: LaunchOptions = LaunchOptions.parse(args)
	var problem: String = options.problem
	# Godot runs in the project's folder, so a relative path wouldn't land where its caller is.
	if problem.is_empty() and not out.begins_with("/"):
		problem = "the tool needs an absolute output path, e.g. -- out=/tmp/outcomes.json"
	if problem.is_empty():
		problem = options.apply()
	if not problem.is_empty():
		printerr(problem)
		quit(1)
		return
	# As in the headless e2e run (tests/e2e/run_e2e.gd with --seed=0): the flow never resumes or
	# overwrites a saved world, and the main scene boots the same world.
	WorldKeeper.default_path = ""
	GameDriver.fixed_seed = 0
	GameDriver.start_instance = InstanceBlueprints.BASIC
	# The main scene needs a running tree (see run_e2e.gd).
	await process_frame
	var ok: bool = await _report(out)
	quit(0 if ok else 1)


## Writes the report to `out` and returns true when everything played, twice the same, without
## errors; otherwise writes nothing, so no half report is ever compared.
func _report(out: String) -> bool:
	# A report left from an earlier run must not pass for this one's.
	var _removed: Error = DirAccess.remove_absolute(out)
	var ok: bool = true
	var replays: Dictionary = {}
	for file_name: String in DirAccess.get_files_at(REPLAYS):
		if file_name.ends_with(".replay"):
			var outcome: Dictionary = _play_twice(REPLAYS + file_name)
			ok = ok and not outcome.is_empty()
			replays[file_name] = outcome
	var flow: RefCounted = (load(APK_FLOW) as GDScript).new()
	var result: String = await Callable(flow, "run").call(self)
	if not result.is_empty():
		printerr("%s: %s" % [APK_FLOW, result])
		ok = false
	var report: Dictionary = {
		"replays": replays,
		"apk_flow": { "final": str(flow.get("final_hash")) },
	}
	if _errors.count > 0:
		printerr("%d error(s) logged" % _errors.count)
		ok = false
	if not ok:
		return false
	var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	if file == null or not file.store_string(JSON.stringify(report, "\t") + "\n"):
		printerr("%s: couldn't write it" % out)
		return false
	print("wrote ", out)
	return ok


## Plays the replay at `path` twice and returns its checkpoints and final hash, or an empty
## dictionary when it can't be played or the two plays differ.
func _play_twice(path: String) -> Dictionary:
	var plays: Array[Dictionary] = []
	for _play: int in 2:
		var replay: Replay = ReplayFile.parse(FileAccess.get_file_as_string(path))
		# Records fresh checkpoints under this build's rules, without the committed ones.
		var problem: String = replay.rehash()
		if not problem.is_empty():
			printerr("%s: %s" % [path, problem])
			return {}
		var checkpoints: Dictionary = {}
		var ticks: Array[int] = []
		ticks.assign(replay.checkpoints.keys())
		ticks.sort()
		for tick: int in ticks:
			checkpoints[str(tick)] = str(replay.checkpoints[tick])
		plays.append({ "checkpoints": checkpoints, "final": str(replay.played.state_hash()) })
	if plays[0] != plays[1]:
		printerr("%s: two plays of it differ, the game isn't deterministic" % path)
		return {}
	return plays[0]
