class_name QuestNamesTie
extends Node
## Ties the names in the menu's Quests tab to the codex (#1446): selecting a person or a place in a
## quest's steps or its pill opens its page (CodexPage) over the menu, and each one shown is met
## (CodexKeeper). The quests' slice comes before the codex, and the menu builds the tab itself, so
## this connects them instead of the scene.

## The menu whose Quests tab names them.
@export var menu: GameMenu
## The page a selected name opens.
@export var page: CodexPage
## Where the names met are kept.
@export var keeper: CodexKeeper


func _ready() -> void:
	# The menu builds its tabs when it's ready, which may be after this.
	if not menu.is_node_ready():
		await menu.ready
	var _selected: int = menu.quests_tab().name_selected.connect(page.open)
	var _shown: int = menu.quests_tab().name_shown.connect(keeper.meet)
