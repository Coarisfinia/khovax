## Headless e2e runner. Runs every tests/e2e/test_*.gd and exits non-zero on failure.
## Usage: godot --headless --path . -s res://tests/e2e/run_e2e.gd
## Each test script extends RefCounted and defines `func run(tree: SceneTree) -> String`,
## returning "" on success or a failure message. `run` may await.
extends SceneTree

const TEST_DIR := "res://tests/e2e"


func _initialize() -> void:
	var failed: int = 0
	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	files.sort()
	var count: int = 0
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		count += 1
		var script: GDScript = load(TEST_DIR.path_join(file))
		if script == null or not script.can_instantiate():
			failed += 1
			printerr("FAIL  ", file, ": script failed to load")
			continue
		var test: Object = script.new()
		var message: String = await test.run(self)
		if message.is_empty():
			print("PASS  ", file)
		else:
			failed += 1
			printerr("FAIL  ", file, ": ", message)
	print("%d passed, %d failed" % [count - failed, failed])
	quit(1 if failed > 0 or count == 0 else 0)
