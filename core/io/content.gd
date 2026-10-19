# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (reads content files, #591)
class_name Content
extends RefCounted
## The game's content data (#72): JSONC files, one per entry, each kind in the slice that owns it
## (#412: the slice's own kind directly in slices/<slice>/data/, so no folder repeats the slice's
## name, #442, and any other kind in slices/<slice>/data/<kind>/), checked against its schema there
## in CI and here for what a schema can't check: ids unique and matching their file. The slices
## read their kinds through their own accessors into their own data (SpeciesContent into
## SpeciesData, and so on, #506), so this never names them; the tile blueprints (#116), which the
## core's TileKinds reads first, live in the core and are read here, from core/data/tiles/ (#506).
## Here too: the field helpers they all use.

const TILES_DIR: String = "res://core/data/tiles/"

## Every tile blueprint, by id.
var tiles: Dictionary[String, TileBlueprint] = {}
## Why the content couldn't be read, or "" when it could.
var problem: String = ""


## Every tile blueprint file in `directory`, read and checked.
static func load_tiles(directory: String = TILES_DIR) -> Content:
	var content: Content = Content.new()
	var numbers: Dictionary[int, bool] = {}
	var texts: Dictionary[String, String] = texts_in(directory)
	for file_id: String in texts:
		var tile: TileBlueprint = TileBlueprint.parse(file_id, texts[file_id])
		if tile.problem.is_empty() and numbers.has(tile.number):
			tile.problem = "its number %d is another tile blueprint's" % tile.number
		if not tile.problem.is_empty():
			content.problem = file_id + ".jsonc: " + tile.problem
			return content
		content.tiles[tile.id] = tile
		numbers[tile.number] = true
	return content


## The text of every JSONC file in `directory`, by its file name without the extension, in file
## name order (#713): every content reader reads through this, so all of them read their files,
## and name the first bad one, in the same order on every machine.
static func texts_in(directory: String) -> Dictionary[String, String]:
	var file_names: Array[String] = []
	file_names.assign(DirAccess.get_files_at(directory))
	file_names.sort()
	var texts: Dictionary[String, String] = {}
	for file_name: String in file_names:
		if file_name.ends_with(".jsonc"):
			texts[file_name.get_basename()] = FileAccess.get_file_as_string(directory + file_name)
	return texts


## Whether `text` is an id: a lowercase letter, then lowercase letters, digits and underscores.
static func is_id(text: String) -> bool:
	var pattern: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return pattern.search(text) != null


## A whole JSON number from 1 to Fixed.MAX_AMOUNT, or 0 for anything else.
static func amount(value: Variant) -> int:
	return JsonNumbers.whole(value, 1, Fixed.MAX_AMOUNT, 0)


## Why `data` has a field outside `allowed`, or "".
static func unknown_field(data: Dictionary, allowed: Array[String]) -> String:
	for key: Variant in data:
		if not allowed.has(str(key)):
			return "field %s isn't allowed here" % key
	return ""


## `value` if it's a string, or "" for anything else, so that e.g. `true` never reads as an id.
static func text_of(value: Variant) -> String:
	var text: String = value if value is String else ""
	return text
