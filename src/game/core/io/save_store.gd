# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (files and JSON)
class_name SaveStore
extends RefCounted
## How saves are kept on this device (#37, #179), so a crash, a full disk or a damaged file never
## costs more than the newest save. Every save file is an envelope around its text, `{"save": 1,
## "checksum": <SHA-256 of the text>, "text": ...}`, so a damaged one is detected instead of
## half-read. Each save keeps GENERATIONS - 1 older ones next to it (`<path>.1`, `<path>.2`), and
## loading takes the newest whose checksum holds. A new save is written whole to a temporary file
## before the generations move up. On the web, whoever saves syncs it into the browser's storage
## (#590), so the core names no platform.

## How many saves are kept: the newest and the ones before it.
const GENERATIONS: int = 3
## The envelope's own format.
const ENVELOPE: int = 1


## The newest generation of the save at `path` whose checksum holds. A plain file from before
## envelopes (#179) is read as it is, so older saves keep working.
static func read_save(path: String) -> SaveRead:
	var read: SaveRead = SaveRead.new()
	for generation: int in GENERATIONS:
		var file: String = _generation_path(path, generation)
		if not FileAccess.file_exists(file):
			continue
		var text: String = _opened(FileAccess.get_file_as_string(file))
		if not text.is_empty():
			read.text = text
			read.generation = generation
			return read
	read.problem = "no generation of %s is intact" % path
	return read


## Saves `text` at `path` in its envelope, keeping the older generations; returns why it couldn't,
## or "". The new file is written whole first, and only then do the generations move up, so a
## crash mid-write leaves every earlier generation in place.
static func write_save(path: String, text: String) -> String:
	var envelope: Dictionary = {
		"save": ENVELOPE,
		"checksum": text.sha256_text(),
		"text": text,
	}
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null or not file.store_string(json_text(envelope, "\t") + "\n"):
		return "couldn't write %s" % temporary
	file.close()
	var folder: DirAccess = DirAccess.open(path.get_base_dir())
	if folder == null:
		return "couldn't open the folder of %s" % path
	# Godot's rename replaces an existing target on every platform, Windows included.
	for generation: int in range(GENERATIONS - 1, 0, -1):
		var older: String = _generation_path(path, generation - 1)
		if FileAccess.file_exists(older):
			var newer: String = _generation_path(path, generation)
			if folder.rename(older.get_file(), newer.get_file()) != OK:
				return "couldn't keep %s as an older generation" % older
	if folder.rename(temporary.get_file(), path.get_file()) != OK:
		return "couldn't put the new save in place at %s" % path
	return ""


## `value` as JSON text, indented by `indent` ("" for one line): every save's text is written
## through this.
static func json_text(value: Variant, indent: String = "") -> String:
	return JSON.stringify(value, indent)


## Whether any generation of the save at `path` exists. Not only the newest: a crash between
## moving it up and putting the new one in place leaves only older ones, which must never be taken
## for no save and overwritten by a new profile.
static func exists(path: String) -> bool:
	for generation: int in GENERATIONS:
		if FileAccess.file_exists(_generation_path(path, generation)):
			return true
	return false


## Deletes the save at `path` with every generation and its temporary file. Only the tests delete
## saves, so nothing syncs a deletion into the browser's storage.
static func remove(path: String) -> void:
	var files: Array[String] = [path + ".tmp"]
	for generation: int in GENERATIONS:
		files.append(_generation_path(path, generation))
	var folder: DirAccess = DirAccess.open(path.get_base_dir())
	if folder == null:
		return
	for file: String in files:
		if FileAccess.file_exists(file):
			var _gone: Error = folder.remove(file.get_file())


## The text inside an envelope, or "" when it isn't one that holds. A plain save from before
## envelopes (none of the envelope's fields) is its own text; anything else shaped like an envelope
## must be a whole one, or it's damaged and an older generation is tried.
static func _opened(content: String) -> String:
	# A JSON object, not JSON.parse_string: a damaged save is expected here, not an error to log.
	var json: JSON = JSON.new()
	if json.parse(content) != OK or not json.data is Dictionary:
		return ""
	var envelope: Dictionary = json.data
	var fields: Array[String] = ["save", "checksum", "text"]
	if fields.all(func(field: String) -> bool: return not envelope.has(field)):
		return content
	if JsonNumbers.whole(envelope.get("save"), ENVELOPE, ENVELOPE, -1) != ENVELOPE:
		return ""
	var text: Variant = envelope.get("text")
	var checksum: Variant = envelope.get("checksum")
	if not text is String or not checksum is String:
		return ""
	var opened: String = text
	return opened if opened.sha256_text() == checksum else ""


## Where generation `generation` of the save at `path` lies: 0 is the newest.
static func _generation_path(path: String, generation: int) -> String:
	return path if generation == 0 else "%s.%d" % [path, generation]
