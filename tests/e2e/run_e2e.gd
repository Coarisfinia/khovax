## Headless e2e runner. Runs every tests/e2e/test_*.gd and exits non-zero on failure.
## Usage: godot --headless --path . -s res://tests/e2e/run_e2e.gd
## Each test script extends RefCounted and defines `func run(tree: SceneTree) -> String`,
## returning "" on success or a failure message. `run` may await.
## Any error logged while a test runs (script errors, push_error, engine errors) fails it too:
## a function that hits a script error returns its type's default, which for String is "".
extends SceneTree

const TEST_DIR := "res://tests/e2e"
## A test running longer than this is named and fails the whole run, instead of the CI timeout
## killing Godot without saying which test hung.
const TEST_TIMEOUT_SECONDS := 60.0


class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1


var _errors := ErrorCounter.new()
var _current: String = ""


func _initialize() -> void:
	OS.add_logger(_errors)
	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	files.sort()
	var count: int = 0
	var failed: int = 0
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		count += 1
		var message: String = await _run_test(file)
		if message.is_empty():
			print("PASS  ", file)
		else:
			failed += 1
			printerr("FAIL  ", file, ": ", message)
	if count == 0:
		printerr("no tests found in ", TEST_DIR)
	print("%d passed, %d failed" % [count - failed, failed])
	quit(1 if failed > 0 or count == 0 else 0)


func _run_test(file: String) -> String:
	var script: GDScript = load(TEST_DIR.path_join(file))
	if script == null or not script.can_instantiate():
		return "script failed to load"
	if script.get_instance_base_type() != &"RefCounted":
		return "test scripts must extend RefCounted"
	var test: RefCounted = script.new()
	if not test.has_method("run"):
		return "no run(tree: SceneTree) -> String method"

	_current = file
	var watchdog := create_timer(TEST_TIMEOUT_SECONDS)
	watchdog.timeout.connect(_on_timeout.bind(file))
	var errors_before: int = _errors.count
	var message: String = await test.run(self)
	_current = ""

	# Whatever a test left in the tree (e.g. after an error before its own cleanup) must not reach the next one.
	for child: Node in root.get_children():
		child.queue_free()
	await process_frame

	var new_errors: int = _errors.count - errors_before
	if message.is_empty() and new_errors > 0:
		return "%d error(s) logged during the test" % new_errors
	return message


func _on_timeout(file: String) -> void:
	if _current == file:
		printerr("FAIL  ", file, ": still running after %d s" % int(TEST_TIMEOUT_SECONDS))
		quit(1)
