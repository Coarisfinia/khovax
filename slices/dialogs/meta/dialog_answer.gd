class_name DialogAnswer
extends RefCounted
## One answer a dialog's line offers the player (#618): what the player says, and the line it leads
## to. Choosing one is to raise an event naming the dialog's id and the answer's id, which quests
## count and branch on (#573, #624), so an answer's id is never reused or changed once shipped.

## An answer's fields, as the dialogs' schema (slices/dialogs/data/dialogs.schema.json) allows them.
const FIELDS: Array[String] = ["id", "text", "next"]

## Unique within its dialog.
var id: String = ""
## What the player says.
var text: String = ""
## The id of the line it leads to, or "" when the dialog ends with it.
var next: String = ""
## Why the answer couldn't be read, or "" when it could.
var problem: String = ""


## An answer read from a dialog file's `raw` entry; its `problem` says what's wrong.
static func read(raw: Variant) -> DialogAnswer:
	var answer: DialogAnswer = DialogAnswer.new()
	if not raw is Dictionary:
		answer.problem = "an answer must be an object"
		return answer
	var data: Dictionary = raw
	answer.id = Content.text_of(data.get("id"))
	answer.text = Content.text_of(data.get("text"))
	answer.next = Content.text_of(data.get("next"))
	answer.problem = Content.unknown_field(data, FIELDS)
	if not answer.problem.is_empty():
		return answer
	if not Content.is_id(answer.id):
		answer.problem = "an answer needs an id of lowercase words with underscores"
	elif answer.text.strip_edges().is_empty():
		answer.problem = "answer %s needs a text" % answer.id
	elif data.has("next") and not Content.is_id(answer.next):
		answer.problem = "answer %s must lead to a line's id" % answer.id
	return answer
