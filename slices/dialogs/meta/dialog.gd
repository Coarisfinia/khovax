class_name Dialog
extends RefCounted
## A dialog (#618), read from content data (the dialogs slice's data/, #72, #412): who speaks it,
## and the lines they say, read in the file's order. A line can offer the player answers, each of
## which ends the dialog or leads to the line it names. Only people speak: monsters never talk
## (the owner's worldbuilding rules).

## Its schema, which says the fields a dialog file, its lines and their answers may have
## (SchemaFields, #825).
const SCHEMA: String = "res://slices/dialogs/data/dialogs.schema.json"
## How many people with locking dialogs one instance's region places before the content check warns
## (#891): locking dialogs are for rare story beats.
const MOST_LOCKING_PER_REGION: int = 1

var id: String = ""
## The player-facing name of who says the lines.
var speaker: String = ""
## Whether the dialog holds its player until they finish it (#891): rare story beats only.
var lock: bool = false
## The lines, in the order they're read where no answer leads elsewhere.
var lines: Array[DialogLine] = []
## Why the dialog couldn't be read, or "" when it could.
var problem: String = ""


## A dialog read from a dialog file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> Dialog:
	var dialog: Dialog = Dialog.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		dialog.problem = "not a JSON object"
		return dialog
	var data: Dictionary = json.data
	dialog.id = Content.text_of(data.get("id"))
	dialog.speaker = Content.text_of(data.get("speaker"))
	dialog.problem = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if dialog.problem.is_empty() and not data.get("lock") is bool:
		dialog.problem = "it must state lock, true or false"
	dialog.lock = data.get("lock") is bool and data.get("lock")
	if dialog.problem.is_empty():
		dialog.problem = dialog._check(file_id, data.get("lines"))
	return dialog


## The index of the line with the id `line_id`, or -1 when none has it.
func line_index(line_id: String) -> int:
	for index: int in lines.size():
		if not line_id.is_empty() and lines[index].id == line_id:
			return index
	return -1


## The answer with the id `answer_id`, on whichever line offers it, or null when none has it.
func answer_of(answer_id: String) -> DialogAnswer:
	for line: DialogLine in lines:
		for answer: DialogAnswer in line.answers:
			if answer.id == answer_id:
				return answer
	return null


## The index of the line that follows the one at `index` once the player picks the answer with the
## id `answer_id` there ("" on a line without answers), or -1 when the dialog ends there or the line
## offers no such answer (on a line without answers, any but "").
func after(index: int, answer_id: String = "") -> int:
	var line: DialogLine = lines[index]
	if line.answers.is_empty():
		return index + 1 if index + 1 < lines.size() and answer_id.is_empty() else -1
	for answer: DialogAnswer in line.answers:
		if answer.id == answer_id:
			return line_index(answer.next)
	return -1


## Why the read fields are wrong, or "", and the lines read from `raw_lines` when they aren't.
func _check(file_id: String, raw_lines: Variant) -> String:
	if id != file_id or not Content.is_id(id):
		return "its id must match the file name and be lowercase words with underscores"
	if speaker.strip_edges().is_empty():
		return "it needs a speaker"
	var entries: Array = raw_lines if raw_lines is Array else []
	if entries.is_empty():
		return "it needs a list of one or more lines"
	for entry: Variant in entries:
		var line: DialogLine = DialogLine.read(entry)
		if not line.problem.is_empty():
			return "line %d: %s" % [lines.size(), line.problem]
		lines.append(line)
	var problem: String = _check_links()
	return problem if not problem.is_empty() else _check_held_end()


## Why the lines don't hold together, or "": no two lines share an id, no two answers share one,
## and every answer that leads on leads to a line.
func _check_links() -> String:
	var answer_ids: Dictionary[String, bool] = {}
	for index: int in lines.size():
		var line: DialogLine = lines[index]
		if not line.id.is_empty() and line_index(line.id) != index:
			return "line %d: another line already has the id %s" % [index, line.id]
		for answer: DialogAnswer in line.answers:
			if answer_ids.has(answer.id):
				return "line %d: another answer already has the id %s" % [index, answer.id]
			answer_ids[answer.id] = true
			if not answer.next.is_empty() and line_index(answer.next) < 0:
				return "line %d: answer %s leads to %s, which no line is" % [
					index, answer.id, answer.next,
				]
	return ""


## Why a line the dialog holds its player on (it locks, or a committing answer leads there, #912)
## ends it without an answer, or "": reading on past a last line closes the card but never reaches
## the simulation, so the dialog would hold its player forever (#1014). Once held, it holds on.
func _check_held_end() -> String:
	var waiting: Array[int] = []
	if lock:
		waiting.append(0)
	for line: DialogLine in lines:
		for answer: DialogAnswer in line.answers:
			if answer.commits and not answer.next.is_empty():
				waiting.append(line_index(answer.next))
	var seen: Dictionary[int, bool] = {}
	while not waiting.is_empty():
		var index: int = waiting.pop_back()
		if seen.has(index):
			continue
		seen[index] = true
		if lines[index].answers.is_empty() and index + 1 == lines.size():
			return "line %d: it holds its player, so it must end on an answer" % index
		if lines[index].answers.is_empty():
			waiting.append(index + 1)
		for answer: DialogAnswer in lines[index].answers:
			if not answer.next.is_empty():
				waiting.append(line_index(answer.next))
	return ""
