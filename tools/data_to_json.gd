# gdstyle:ignore-file=quality/no-debug-print
# The tool reports to whoever runs it (CI) on stderr; that is what it is for.
extends SceneTree
## Writes every content data file (data/<kind>/*.jsonc, and slices/<slice>/data/<kind>/*.jsonc for
## a kind a slice owns, #412) as plain JSON into build/data-json/<kind>/,
## with the comments stripped by the game's own stripper (Jsonc), so CI can check each one against
## its schema: godot --headless --path . -s res://tools/data_to_json.gd

const TARGET: String = "res://build/data-json/"
const SLICES: String = "res://slices/"


func _init() -> void:
	var failed: int = _convert_all("res://data/", false)
	for slice: String in DirAccess.get_directories_at(SLICES):
		if DirAccess.dir_exists_absolute(SLICES + slice + "/data"):
			failed += _convert_all(SLICES + slice + "/data/", true)
	quit(1 if failed > 0 else 0)


## Converts every kind's folder in `source`. Content lives exactly one folder deep
## (<source><kind>/<id>.jsonc), as CI checks it; anything elsewhere would go unchecked, so it fails
## instead, except the schemas: data/schemas/, or, in a slice's data/ (`beside`), the
## <kind>.schema.json beside its kind.
func _convert_all(source: String, beside: bool) -> int:
	var failed: int = 0
	for file_name: String in DirAccess.get_files_at(source):
		if not (beside and file_name.ends_with(".schema.json")):
			printerr("%s%s isn't content: put it in a <kind>/ folder" % [source, file_name])
			failed += 1
	for folder: String in DirAccess.get_directories_at(source):
		if folder != "schemas":
			failed += _convert(source, folder)
	return failed


## Converts one folder's files; returns how many couldn't be written or aren't JSONC (a stray file
## would go unchecked).
func _convert(source: String, folder: String) -> int:
	var target: String = TARGET + folder + "/"
	var _made: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
	var failed: int = DirAccess.get_directories_at(source + folder).size()
	if failed > 0:
		printerr("%s%s/ has subfolders, which content can't have" % [source, folder])
	for file_name: String in DirAccess.get_files_at(source + folder):
		if not file_name.ends_with(".jsonc"):
			printerr("%s%s/%s isn't a .jsonc file" % [source, folder, file_name])
			failed += 1
		else:
			var path: String = source + folder + "/" + file_name
			var text: String = Jsonc.strip(FileAccess.get_file_as_string(path))
			var file: FileAccess = FileAccess.open(
				target + file_name.get_basename() + ".json",
				FileAccess.WRITE,
			)
			if file == null or not file.store_string(text):
				failed += 1
	return failed
