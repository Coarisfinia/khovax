class_name Dialog
extends RefCounted
## A dialog (#618), read from content data (the dialogs slice's data/, #72, #412): who speaks it,
## a person named by their id (#1005), and the lines they say, read in the file's order. A line can
## offer the player answers, each of which ends the dialog or leads to the line it names. Only
## people speak: monsters never talk (the owner's worldbuilding rules).

## Its schema, which says the fields a dialog file, its lines and their answers may have
## (SchemaFields, #825).
const SCHEMA: String = "res://slices/dialogs/data/dialogs.schema.json"
## How many people with locking dialogs one instance's region places before the content check warns
## (#891): locking dialogs are for rare story beats.
const MOST_LOCKING_PER_REGION: int = 1

var id: String = ""
## The id of the person who says the lines (#1005; PeopleContent holds their name).
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
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		dialog.problem = Content.NOT_AN_OBJECT
		return dialog
	var data: Dictionary = parsed
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
	var wrong_id: String = Content.id_problem(id, file_id)
	if not wrong_id.is_empty():
		return wrong_id
	if not Content.is_id(speaker):
		return "it needs a speaker, a person's id"
	var entries: Array = raw_lines if raw_lines is Array else []
	if entries.is_empty():
		return "it needs a list of one or more lines"
	for entry: Variant in entries:
		var line: DialogLine = DialogLine.read(entry)
		if not line.problem.is_empty():
			return "line %d: %s" % [lines.size(), line.problem]
		lines.append(line)
	var link_problem: String = _check_links()
	if link_problem.is_empty():
		link_problem = _check_reached()
	return link_problem if not link_problem.is_empty() else _check_held_end()


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


## Why a line can't be reached from line 0, by reading on or by an answer, or "": such a line is
## dead content (#1029).
func _check_reached() -> String:
	var reached: Dictionary[int, bool] = _reached_from([0])
	for index: int in lines.size():
		if not reached.has(index):
			return "line %d: nothing leads to it from line 0" % index
	return ""


## Why a line the dialog holds its player on (it locks, or a committing answer leads there, #912)
## ends it without an answer, or "": reading on past a last line closes the card but never reaches
## the simulation, so the dialog would hold its player forever (#1014). Once held, it holds on.
func _check_held_end() -> String:
	var held: Array[int] = []
	if lock:
		held.append(0)
	for line: DialogLine in lines:
		for answer: DialogAnswer in line.answers:
			if answer.commits and not answer.next.is_empty():
				held.append(line_index(answer.next))
	for index: int in _reached_from(held):
		if lines[index].answers.is_empty() and index + 1 == lines.size():
			return "line %d: it holds its player, so it must end on an answer" % index
	return ""


## Every line reached from the lines at `starts`, them included: by reading on past a line without
## answers, or by an answer that leads on.
func _reached_from(starts: Array[int]) -> Dictionary[int, bool]:
	var waiting: Array[int] = []
	waiting.append_array(starts)
	var reached: Dictionary[int, bool] = {}
	while not waiting.is_empty():
		var index: int = waiting.pop_back()
		if reached.has(index):
			continue
		reached[index] = true
		if lines[index].answers.is_empty() and index + 1 < lines.size():
			waiting.append(index + 1)
		for answer: DialogAnswer in lines[index].answers:
			if not answer.next.is_empty():
				waiting.append(line_index(answer.next))
	return reached
