# gdstyle:ignore-file=quality/no-debug-print
# The runner's report on stdout is what it is for, not leftover debug printing.
extends SceneTree
## Headless e2e runner. Runs every tests/e2e/test_*.gd and exits non-zero on failure.
## Usage: godot --headless --path . -s res://tests/e2e/run_e2e.gd -- --seed=0
## Locally, add `--user-dir=<branch>` (#786): worktrees share one `user://` folder otherwise, and
## parallel runs overwrite each other's files. CI runs without it, each job on its own machine.
## The seed is required (#237): every flow boots the main scene on that world, and the flows'
## expectations are written for the seed CI passes.
## Each test script extends RefCounted and defines `func run(tree: SceneTree) -> String`,
## returning "" on success or a failure message. `run` may await.
## Any error logged while a test runs (script errors, push_error, engine errors) fails it too:
## a function that hits a script error returns its type's default, which for String is "".

const TEST_DIR: String = "res://tests/e2e"
## A test running longer than this is named and fails the whole suite, instead of the CI timeout
## killing Godot without saying which test hung.
const TEST_TIMEOUT_SECONDS: float = 60.0

var _errors: ErrorCounter = ErrorCounter.new()
var _current: String = ""


func _initialize() -> void:
	OS.add_logger(_errors)
	# The flows never resume or overwrite a world on this device's disk; the resume flow points its
	# keeper at a test file of its own.
	WorldKeeper.default_path = ""
	# Every flow boots the main scene on the same world (#213), from the seed it's given; the boot
	# flow checks the rolling and puts the seed back.
	var options: LaunchOptions = LaunchOptions.parse(OS.get_cmdline_user_args())
	if not options.problem.is_empty() or options.seed_value == GameDriver.ROLLED_SEED:
		printerr("the runner needs a seed, e.g. -- --seed=0. ", options.problem)
		quit(1)
		return
	var not_applied: String = options.apply()
	if not not_applied.is_empty():
		printerr("the launch options couldn't be applied: ", not_applied)
		quit(1)
		return
	# The flows boot the playground, which only the tests play (#712), unless they're given another.
	if GameDriver.start_instance.is_empty():
		GameDriver.start_instance = InstanceBlueprints.BASIC
	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	files.sort()
	var tests: Array[String] = []
	for file: String in files:
		if file.begins_with("test_") and file.ends_with(".gd"):
			tests.append(file)
	if tests.is_empty():
		printerr("no tests found in ", TEST_DIR)
		quit(1)
		return
	var failed: int = await _run_from(tests, 0)
	print("%d passed, %d failed" % [tests.size() - failed, failed])
	quit(1 if failed > 0 else 0)


## Runs the tests from `index` on, one after another, and returns how many failed.
func _run_from(tests: Array[String], index: int) -> int:
	if index >= tests.size():
		return 0
	var file: String = tests[index]
	var message: String = await _run_test(file)
	if message.is_empty():
		print("PASS  ", file)
	else:
		printerr("FAIL  ", file, ": ", message)
	var failed_here: int = 0 if message.is_empty() else 1
	var failed_after: int = await _run_from(tests, index + 1)
	return failed_here + failed_after


func _run_test(file: String) -> String:
	var script: GDScript = load(TEST_DIR.path_join(file)) as GDScript
	if script == null or not script.can_instantiate():
		return "script failed to load"
	if script.get_instance_base_type() != &"RefCounted":
		return "test scripts must extend RefCounted"
	var test: RefCounted = script.new()
	if not test.has_method("run"):
		return "no run(tree: SceneTree) -> String method"

	_current = file
	var watchdog: SceneTreeTimer = create_timer(TEST_TIMEOUT_SECONDS)
	var connected: int = watchdog.timeout.connect(_on_timeout.bind(file))
	if connected != OK:
		return "could not start the watchdog"
	var errors_before: int = _errors.count
	var run: Callable = Callable(test, "run")
	var message: String = await run.call(self)
	_current = ""

	# Whatever a test left in the tree (e.g. after an error before its own cleanup) must not
	# reach the next one.
	for child: Node in root.get_children():
		child.queue_free()
	await process_frame

	var new_errors: int = _errors.count - errors_before
	var missing: Array[String] = _errors.expected.duplicate()
	_errors.expected.clear()
	if message.is_empty() and new_errors > 0:
		message = "%d error(s) logged during the test" % new_errors
	elif message.is_empty() and not missing.is_empty():
		message = "expected warnings never came: %s" % [missing]
	return message


## Lets the running flow expect a warning containing `fragment` (ErrorCounter.expect): it then
## doesn't fail the flow, and the flow fails if it never comes. Flows call it through their tree.
func expect_warning(fragment: String) -> void:
	_errors.expect(fragment)


func _on_timeout(file: String) -> void:
	if _current == file:
		printerr("FAIL  ", file, ": still running after %d s" % int(TEST_TIMEOUT_SECONDS))
		quit(1)
