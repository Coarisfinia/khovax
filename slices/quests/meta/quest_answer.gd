class_name QuestAnswer
extends RefCounted
## The answer an `answered` quest step or choice asks for (#636): a dialog's id and one of its
## answers' ids, as the dialogs' files name them, and how the player reads them.

## The dialog's id, or "" on a step that asks for no answer.
var dialog: String = ""
## The answer's id within that dialog.
var id: String = ""
## Who speaks the dialog and what the answer says, as the player reads them, or "" (QuestContent
## fills them in from the dialogs).
var speaker: String = ""
var text: String = ""


## The answer as one fact, as Gain.answers_chosen holds it (QuestStep.answer_key).
func key() -> String:
	return QuestStep.answer_key(dialog, id)
