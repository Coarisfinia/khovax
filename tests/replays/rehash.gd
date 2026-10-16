# gdstyle:ignore-file=quality/no-debug-print
# The tool reports to whoever runs it on stdout and stderr; that is what it is for.
extends SceneTree
## Rehashes every golden replay under the current rules, after a rules change made on purpose
## (bump Simulation.RULES_VERSION in the same change, and say in the pull request why the game
## plays out differently): godot --headless --path . -s res://tests/replays/rehash.gd
## A golden replay can also start as a file with only its start and commands: this adds the
## checkpoints.

const FOLDER: String = "res://tests/replays/"


func _init() -> void:
	var failed: int = 0
	for file_name: String in DirAccess.get_files_at(FOLDER):
		if file_name.ends_with(".replay") and not _rehash(FOLDER + file_name):
			failed += 1
	quit(1 if failed > 0 else 0)


func _rehash(path: String) -> bool:
	var replay: Replay = ReplayFile.parse(FileAccess.get_file_as_string(path))
	var problem: String = replay.rehash()
	if not problem.is_empty():
		printerr("%s: %s" % [path, problem])
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null or not file.store_string(ReplayFile.to_text(replay) + "\n"):
		printerr("%s: couldn't write it" % path)
		return false
	print("rehashed ", path)
	return true
