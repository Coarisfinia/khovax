class_name DialogContent
extends RefCounted
## The dialogs' content data (#618), which the dialogs slice owns (#412): one JSONC file per dialog
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against dialogs.schema.json beside them in CI. Everything else reads the dialogs through this.

const DIR: String = "res://slices/dialogs/data/"

## Every dialog, by id.
var dialogs: Dictionary[String, Dialog] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""


## Every dialog file in `directory`, read and checked.
static func load_dialogs(directory: String = DIR) -> DialogContent:
	var content: DialogContent = DialogContent.new()
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".jsonc"):
			var text: String = FileAccess.get_file_as_string(directory + file_name)
			var dialog: Dialog = Dialog.parse(file_name.get_basename(), text)
			if not dialog.problem.is_empty():
				content.problem = file_name + ": " + dialog.problem
				return content
			content.dialogs[dialog.id] = dialog
	return content
