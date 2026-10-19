class_name DialogLine
extends RefCounted
## One line a dialog's speaker says (#618), and the answers it offers the player, if any.

## A line's fields, as the dialogs' schema (slices/dialogs/data/dialogs.schema.json) allows them.
const FIELDS: Array[String] = ["id", "text", "answers"]

## Its id within the dialog, which answers name to lead to it, or "" where none does.
var id: String = ""
## What the speaker says.
var text: String = ""
## The answers the player chooses from; without any, the dialog reads on to the next line.
var answers: Array[DialogAnswer] = []
## Why the line couldn't be read, or "" when it could.
var problem: String = ""


## A line read from a dialog file's `raw` entry; its `problem` says what's wrong.
static func read(raw: Variant) -> DialogLine:
	var line: DialogLine = DialogLine.new()
	if not raw is Dictionary:
		line.problem = "a line must be an object"
		return line
	var data: Dictionary = raw
	line.id = Content.text_of(data.get("id"))
	line.text = Content.text_of(data.get("text"))
	line.problem = Content.unknown_field(data, FIELDS)
	if line.problem.is_empty() and data.has("id") and not Content.is_id(line.id):
		line.problem = "a line's id must be lowercase words with underscores"
	if line.problem.is_empty() and line.text.strip_edges().is_empty():
		line.problem = "a line needs a text"
	if line.problem.is_empty() and data.has("answers"):
		line.problem = line._read_answers(data.get("answers"))
	return line


## Why `raw` isn't a list of one or more answers, or "", and the answers read into `answers`.
func _read_answers(raw: Variant) -> String:
	var entries: Array = raw if raw is Array else []
	if entries.is_empty():
		return "a line's answers must be a list of one or more"
	for entry: Variant in entries:
		var answer: DialogAnswer = DialogAnswer.read(entry)
		if not answer.problem.is_empty():
			return answer.problem
		answers.append(answer)
	return ""
