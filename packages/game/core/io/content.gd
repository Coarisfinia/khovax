# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (reads files and JSON for core/io, #591)
class_name Content
extends RefCounted
## The game's content data (#72): JSONC files, one per entry, each kind in the slice that owns it
## (#412: the slice's own kind directly in slices/<slice>/data/, so no folder repeats the slice's
## name, #442, and any other kind in slices/<slice>/data/<kind>/), checked against its schema there
## in CI and here for what a schema can't check: ids unique and matching their file. Every kind is
## read by its own `<Kind>Content` (#816), which extends this: it reads its kind's files through
## `read`, adds each entry in its own `add`, and holds the entries, so this never names a slice's
## kind (#506); a kind a resource pack holds is read from the files the packs list (`read_files`,
## #1903). The tile blueprints, which the core's TileKinds reads first, live in the core and
## are read by TileContent. Here too: the field helpers they all use.

## What a content file's reader says when object_of finds no JSON object in it.
const NOT_AN_OBJECT: String = "not a JSON object"

## Why the content couldn't be read, or "" when it could.
var problem: String = ""


## Reads every JSONC file in `directory` into this through `add`, in file name order, and stops at
## the first one that can't be: `problem` then names that file and why.
func read(directory: String) -> void:
	var texts: Dictionary[String, String] = texts_in(directory)
	for file_id: String in texts:
		var why: String = add(file_id, texts[file_id])
		if not why.is_empty():
			problem = file_id + ".jsonc: " + why
			return


## Reads every file of `files` (each res:// path by its entry's id, as a resource pack lists them,
## #1888, #1903) into this through `add`, in id order, and stops at the first one that can't be:
## then names that file and why. A file that can't be read is refused like any broken one.
func read_files(files: Dictionary[String, String]) -> void:
	var ids: Array[String] = []
	ids.assign(files.keys())
	ids.sort()
	for file_id: String in ids:
		var why: String = add(file_id, text_in(files[file_id]))
		if not why.is_empty():
			problem = files[file_id] + ": " + why
			return


## Reads one file's text, named `file_id`, and adds its entry; returns why it can't, or "". Each
## `<Kind>Content` gives its own.
func add(file_id: String, _text: String) -> String:
	push_error("%s's content kind doesn't read its files" % file_id)
	return "its kind can't be read"


## The text of every JSONC file in `directory`, by its file name without the extension, in file
## name order (#713): every content reader reads through this, so all of them read their files,
## and name the first bad one, in the same order on every machine.
static func texts_in(directory: String) -> Dictionary[String, String]:
	var texts: Dictionary[String, String] = {}
	for file_name: String in file_names_in(directory):
		if file_name.ends_with(".jsonc"):
			texts[file_name.get_basename()] = text_in(directory + file_name)
	return texts


## The names of the files in `directory`, in file name order, so every machine lists them alike.
static func file_names_in(directory: String) -> Array[String]:
	var file_names: Array[String] = []
	file_names.assign(DirAccess.get_files_at(directory))
	file_names.sort()
	return file_names


## The text of the file at `path`, or "" when it can't be read.
static func text_in(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The JSON object a content file's JSONC `text` holds, or null when it holds anything else: every
## content file's reader starts here, and says NOT_AN_OBJECT for null.
static func object_of(text: String) -> Variant:
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		return null
	return json.data


## The value in the JSON `text` (no comments, unlike content files), or null when it isn't JSON.
static func json_of(text: String) -> Variant:
	# A JSON object reports a parse error through its result instead of logging it.
	var json: JSON = JSON.new()
	return json.data if json.parse(text) == OK else null


## Why `id` can't be the id of the entry in the file named `file_id`, or "": every content
## file's id is its file's name, and an id as Ids says.
static func id_problem(id: String, file_id: String) -> String:
	if id != file_id or not is_id(id):
		return "its id must match the file name and be lowercase words with underscores"
	return ""


## Whether `text` is an id, as Ids says.
static func is_id(text: String) -> bool:
	return Ids.is_id(text)


## A content file's codex entry (#959) from its `codex` object `raw`: its entry and its gloss, or
## an empty list unless both have more than spaces.
static func codex_of(raw: Variant) -> Array[String]:
	var codex: Dictionary = raw if raw is Dictionary else {}
	var parts: Array[String] = [text_of(codex.get("entry")), text_of(codex.get("gloss"))]
	for part: String in parts:
		if part.strip_edges().is_empty():
			return []
	return parts


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
