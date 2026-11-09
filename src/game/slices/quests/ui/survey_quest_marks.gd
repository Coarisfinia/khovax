class_name SurveyQuestMarks
extends SurveyQuests
## What this machine's player's quests show on a SurveyView (#300, #1278, #1298), handed to it by
## game/ (#1666), since the quests' slice comes after the Survey's: the tile each open quest points
## at (QuestTargets.of), following the quest a tap or a click on its grey arrow picks, the grey
## arrows' color, as their markers in the world, and the layers above the Survey, the followed
## quest's (SurveyFocusedQuest) under the card of the grey arrow the pointer rests on
## (SurveyQuestHover).

## This machine's player's quests.
var keeper: QuestKeeper


func _init(quest_keeper: QuestKeeper) -> void:
	keeper = quest_keeper


## Hands `survey` the quests `quest_keeper` keeps and their layers, once, after its own layers are
## made.
static func hand_to(survey: SurveyView, quest_keeper: QuestKeeper) -> void:
	survey.quests = SurveyQuestMarks.new(quest_keeper)
	var focused: SurveyFocusedQuest = SurveyFocusedQuest.new()
	focused.name = SurveyFocusedQuest.NAME
	focused.keeper = quest_keeper
	survey.add_child(focused)
	var hover: SurveyQuestHover = SurveyQuestHover.new()
	hover.name = SurveyQuestHover.NAME
	hover.keeper = quest_keeper
	survey.add_child(hover)


## None while the player's quests can't be read.
func targets(state: GameState, slot: int, here: String) -> Dictionary[String, Vector2i]:
	if keeper.quests() == null:
		return {}
	return QuestTargets.of(state, keeper.quests(), slot, here)


func follow(id: String) -> void:
	keeper.follow(id)


func arrow_color() -> Color:
	return QuestMarkerView.OTHER_COLOR
