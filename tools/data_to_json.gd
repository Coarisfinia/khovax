# gdstyle:ignore-file=quality/no-debug-print
# The tool reports to whoever runs it (CI) on stderr; that is what it is for.
extends SceneTree
## Writes every content data file (the core's, core/data/<kind>/*.jsonc, #506; in a slice's data/,
## #412, the slice's own kind's files directly, named for the slice so no folder repeats it, #442,
## and any other kind it owns in <kind>/) as plain JSON into build/data-json/<kind>/,
## with the comments stripped by the game's own stripper (Jsonc), so CI can check each one against
## its schema: godot --headless --path . -s res://tools/data_to_json.gd

const TARGET: String = "res://build/data-json/"
const SLICES: String = "res://slices/"


func _init() -> void:
	var failed: int = _convert_all("res://core/data/", "")
	for slice: String in DirAccess.get_directories_at(SLICES):
		if DirAccess.dir_exists_absolute(SLICES + slice + "/data"):
			failed += _convert_all(SLICES + slice + "/data/", slice)
	quit(1 if failed > 0 else 0)


## Converts every kind's folder in `source`. Content lives one folder deep
## (<source><kind>/<id>.jsonc), as CI checks it, except in a slice's data/ (`slice` names it), where
## the slice's own kind's files sit directly, beside the schemas; anything elsewhere would go
## unchecked, so it fails instead, except core/data/schemas/.
func _convert_all(source: String, slice: String) -> int:
	var failed: int = 0
	for file_name: String in DirAccess.get_files_at(source):
		var beside: bool = file_name.ends_with(".schema.json") or file_name.ends_with(".jsonc")
		if slice.is_empty() or not beside:
			printerr("%s%s isn't content: put it in a <kind>/ folder" % [source, file_name])
			failed += 1
	if not slice.is_empty():
		failed += _convert_files(source, slice)
	for folder: String in DirAccess.get_directories_at(source):
		if folder != "schemas":
			failed += _convert(source, folder)
	return failed


## Converts one folder's files; returns how many couldn't be written or aren't JSONC (a stray file
## would go unchecked).
func _convert(source: String, folder: String) -> int:
	var failed: int = DirAccess.get_directories_at(source + folder).size()
	if failed > 0:
		printerr("%s%s/ has subfolders, which content can't have" % [source, folder])
	for file_name: String in DirAccess.get_files_at(source + folder):
		if not file_name.ends_with(".jsonc"):
			printerr("%s%s/%s isn't a .jsonc file" % [source, folder, file_name])
			failed += 1
	return failed + _convert_files(source + folder + "/", folder)


## Writes the .jsonc files directly in `directory` into the build folder of `kind`, made only when
## there are some (CI wants a schema for every kind's folder); returns how many couldn't be written.
func _convert_files(directory: String, kind: String) -> int:
	var target: String = TARGET + kind + "/"
	var failed: int = 0
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var _made: Error = DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(target),
			)
			var text: String = Jsonc.strip(FileAccess.get_file_as_string(directory + file_name))
			var file: FileAccess = FileAccess.open(
				target + file_name.get_basename() + ".json",
				FileAccess.WRITE,
			)
			if file == null or not file.store_string(text):
				failed += 1
	return failed
