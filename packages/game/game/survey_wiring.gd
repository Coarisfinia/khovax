extends Node
## Hands each Survey, the one on the screen and the menu's Survey tab's, this machine's player's
## quests (SurveyQuestMarks, #1666): the quests' slice comes after the Survey's, so the Survey never
## names it.

## The Survey on the screen.
@export var survey: SurveyView
## The menu, whose Survey tab has a Survey of its own.
@export var menu: GameMenu
## This machine's player's quests.
@export var quest_keeper: QuestKeeper


func _ready() -> void:
	# The menu builds its tabs when it's ready, which may be after this.
	if not menu.is_node_ready():
		await menu.ready
	SurveyQuestMarks.hand_to(survey, quest_keeper)
	SurveyQuestMarks.hand_to(menu.survey_tab.view, quest_keeper)
