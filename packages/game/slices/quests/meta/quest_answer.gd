class_name QuestAnswer
extends RefCounted
## The answer an `answered` quest step or choice asks for (#636): a dialog's id and one of its
## answers' ids, as the dialogs' files name them, and how the player reads them.

## The dialog's id, or "" on a step that asks for no answer.
var dialog: String = ""
## The answer's id within that dialog.
var id: String = ""
## The id of the person who speaks the dialog (#1005) and what the answer says, or "" (QuestContent
## fills them in from the dialogs).
var speaker: String = ""
var text: String = ""


## The answer as one fact, as an answered QuestFact names it (QuestStep.answer_key).
func key() -> String:
	return QuestStep.answer_key(dialog, id)
