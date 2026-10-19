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
## Why the data couldn't be read, or "" when it could.
var problem: String = ""


## Every dialog file in `directory`, read and checked.
static func load_dialogs(directory: String = DIR) -> DialogContent:
	var content: DialogContent = DialogContent.new()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var dialog: Dialog = Dialog.parse(file_name.get_basename(), text)
			if dialog.problem.is_empty():
				dialog.problem = content._code_answers(dialog)
			if not dialog.problem.is_empty():
				content.problem = file_name + ": " + dialog.problem
				return content
			content.dialogs[dialog.id] = dialog
	return content


## Files `dialog`'s answers by their codes; why one can't be, or "": a command couldn't tell it from
## no answer, or from another dialog's answer with the same code.
func _code_answers(dialog: Dialog) -> String:
	for line: DialogLine in dialog.lines:
		for answer: DialogAnswer in line.answers:
			var by: int = DialogFeature.code(dialog.id, answer.id)
			if by == Command.NO_ANSWER or answers.has(by):
				return "answer %s's code is taken: give it another id" % answer.id
			answers[by] = PackedStringArray([dialog.id, answer.id])
	return ""
