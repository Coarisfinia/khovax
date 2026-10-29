class_name SurveyQuests
extends RefCounted
## What a SurveyView marks of this machine's player's quests (#300, #1298): here none, as a Survey
## has until game/ hands it theirs. The quests' slice comes after the Survey's, so theirs extends
## this one (SurveyQuestMarks, #1666) and the Survey never names it.


## The tile each open quest of the player in `slot` points at in `state`, in the instance `here`,
## by a key naming the quest (its id, or its id and a choice's index after a slash).
func targets(_state: GameState, _slot: int, _here: String) -> Dictionary[String, Vector2i]:
	return {}


## Makes this machine's player follow the open quest `id`, as a tap or a click on its grey arrow
## asks (SurveyQuestPicker).
func follow(_id: String) -> void:
	return


## The color of the grey arrows the Survey draws, the quests not followed.
func arrow_color() -> Color:
	return Color.GRAY
