extends Node
## Hands the menu what the slices after its own add to it (#1614), so the menu never names them:
## the player's Might and gear panels in its Character tab, the damage numbers' rows in its Settings
## tab, and the quest list's column, which its open button stands above on a screen held upright
## (#1465). The Quests tab and the codex book are the menu's own children in the main scene instead.
## The two panels are this node's children in the main scene, so the profile's tie
## (ProfilePanelsTie) can name the gear panel there too; this moves them into the tab.

## The menu they're added to.
@export var menu: GameMenu
## The quest list at the top's side.
@export var quest_list: QuestListView
## The player's Might and its parts (#509), and their gear slots (#690).
@export var might: MightPanel
@export var gear: GearPanel

## The damage numbers' choice, which their rows in the Settings tab call: kept here so the rows'
## callables stay bound to it.
var damage_numbers: DamageNumbersChoice


func _ready() -> void:
	# The menu builds its tabs when it's ready, which may be after this.
	if not menu.is_node_ready():
		await menu.ready
	_add_panels(menu.character)
	if menu.graphics != null:
		damage_numbers = DamageNumbersChoice.new(menu.graphics)
		damage_numbers.add_rows(menu.settings)
	if quest_list != null:
		menu.side_column = quest_list.column_in
		var _room: int = menu.side_room.connect(_make_room)


## The player's Might above their standing with each faction, and their gear above their
## materials, sized with the tab's text.
func _add_panels(tab: CharacterTab) -> void:
	remove_child(might)
	tab.add_panel(might, tab.factions)
	remove_child(gear)
	tab.add_panel(gear, tab.materials)
	var _fitted: int = tab.fitted.connect(gear.fit)


## Makes the quest list room below the menu's open button, which reaches `below` pixels down from
## the list's top (0 when it leaves the list's top free), with the list's gap under it.
func _make_room(below: float) -> void:
	quest_list.room_above = below + QuestListView.GAP if below > 0.0 else 0.0
