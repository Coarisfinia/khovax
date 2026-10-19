class_name Dialog
extends RefCounted
## A dialog (#618), read from content data (the dialogs slice's data/, #72, #412): who speaks it,
## and the lines they say, read in the file's order. A line can offer the player answers, each of
## which ends the dialog or leads to the line it names. Only people speak: monsters never talk
## (the owner's worldbuilding rules).

## A dialog file's fields, as its schema (slices/dialogs/data/dialogs.schema.json) allows them.
const FIELDS: Array[String] = ["id", "speaker", "lines"]

var id: String = ""
## The player-facing name of who says the lines.
var speaker: String = ""
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
	dialog.problem = Content.unknown_field(data, FIELDS)
	if dialog.problem.is_empty():
		dialog.problem = dialog._check(file_id, data.get("lines"))
	return dialog


## The index of the line with the id `line_id`, or -1 when none has it.
func line_index(line_id: String) -> int:
	for index: int in lines.size():
		if not line_id.is_empty() and lines[index].id == line_id:
			return index
	return -1


## The index of the line that follows the one at `index` once the player picks the answer with the
## id `answer_id` there ("" on a line without answers), or -1 when the dialog ends there or the line
## offers no such answer.
func after(index: int, answer_id: String = "") -> int:
	var line: DialogLine = lines[index]
	if line.answers.is_empty():
		return index + 1 if index + 1 < lines.size() else -1
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
	return _check_links()


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
