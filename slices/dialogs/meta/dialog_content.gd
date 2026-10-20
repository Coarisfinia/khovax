class_name DialogContent
extends RefCounted
## The dialogs' content data (#618), which the dialogs slice owns (#412): one JSONC file per dialog
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against dialogs.schema.json beside them in CI. Everything else reads the dialogs through this.

const DIR: String = "res://slices/dialogs/data/"

## Every dialog, by id.
var dialogs: Dictionary[String, Dialog] = {}
## Every answer of every dialog, by the code a command gives it by (DialogFeature.code, #635): its
## dialog's id and its own.
var answers: Dictionary[int, PackedStringArray] = {}
## The index of the line each answer leads to, by its code, or DialogFeature.NO_LINE when it ends
## its dialog (#898).
var leads: Dictionary[int, int] = {}
## How many lines each dialog has, by its id.
var line_counts: Dictionary[String, int] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""


## Every dialog file in `directory`, read and checked.
static func load_dialogs(directory: String = DIR) -> DialogContent:
	var content: DialogContent = DialogContent.new()
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		var dialog: Dialog = Dialog.parse(file_id, texts[file_id])
		if dialog.problem.is_empty():
			dialog.problem = content._code_answers(dialog)
		if not dialog.problem.is_empty():
			content.problem = file_id + ".jsonc: " + dialog.problem
			return content
		content.dialogs[dialog.id] = dialog
		content.line_counts[dialog.id] = dialog.lines.size()
	return content


## Files `dialog`'s answers by their codes; why one can't be, or "": a command couldn't tell it from
## no answer, or from another dialog's answer with the same code.
func _code_answers(dialog: Dialog) -> String:
	for line: DialogLine in dialog.lines:
		for answer: DialogAnswer in line.answers:
			var by: int = DialogFeature.code(dialog.id, answer.id)
			if not CommandCodes.file(answers, by, PackedStringArray([dialog.id, answer.id])):
				return "answer %s's code is taken: give it another id" % answer.id
			leads[by] = dialog.line_index(answer.next)
	return ""
