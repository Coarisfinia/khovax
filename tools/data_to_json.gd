extends SceneTree
## Writes every content data file (data/**/*.jsonc) as plain JSON into build/data-json/, with the
## comments stripped by the game's own stripper (Jsonc), so CI can check each one against its
## schema: godot --headless --path . -s res://tools/data_to_json.gd

const SOURCE: String = "res://data/"
const TARGET: String = "res://build/data-json/"


func _init() -> void:
	var failed: int = 0
	for folder: String in DirAccess.get_directories_at(SOURCE):
		if folder != "schemas":
			failed += _convert(folder)
	quit(1 if failed > 0 else 0)


## Converts one folder's files; returns how many couldn't be written.
func _convert(folder: String) -> int:
	var target: String = TARGET + folder + "/"
	var _made: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
	var failed: int = 0
	for file_name: String in DirAccess.get_files_at(SOURCE + folder):
		if file_name.ends_with(".jsonc"):
			var source: String = SOURCE + folder + "/" + file_name
			var text: String = Jsonc.strip(FileAccess.get_file_as_string(source))
			var file: FileAccess = FileAccess.open(
				target + file_name.get_basename() + ".json",
				FileAccess.WRITE,
			)
			if file == null or not file.store_string(text):
				failed += 1
	return failed
