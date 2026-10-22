# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (reads content files, #591)
class_name Content
extends RefCounted
## The game's content data (#72): JSONC files, one per entry, each kind in the slice that owns it
## (#412: the slice's own kind directly in slices/<slice>/data/, so no folder repeats the slice's
## name, #442, and any other kind in slices/<slice>/data/<kind>/), checked against its schema there
## in CI and here for what a schema can't check: ids unique and matching their file. Every kind is
## read by its own `<Kind>Content` (#816), which extends this: it reads its kind's files through
## `read`, adds each entry in its own `add`, and holds the entries, so this never names a slice's
## kind (#506). The tile blueprints, which the core's TileKinds reads first, live in the core and
## are read by TileContent. Here too: the field helpers they all use.

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


## Reads one file's text, named `file_id`, and adds its entry; returns why it can't, or "". Each
## `<Kind>Content` gives its own.
func add(file_id: String, _text: String) -> String:
	push_error("%s's content kind doesn't read its files" % file_id)
	return "its kind can't be read"


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


## Whether `text` is an id, as Ids says.
static func is_id(text: String) -> bool:
	return Ids.is_id(text)


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
