class_name QuestsTab
extends ScrollContainer
## The menu's Quests tab (#388): the same open quests as the list at the side of the screen (#340,
## QuestTracker.open_steps), each with its name and path mark (#471) and its steps on the player's
## way, worded as the list words them (QuestListView.step_line): the steps done, the one it's on
## with its count, and the ones still to come up to its next choice (#573). Each step says which it
## is in words, never by color alone (#68). Under each quest's name, a pill names the instance its
## current step counts in, as the list shows it (QuestPill, #794). Beside it, a button follows the
## quest (#1298), by touch, mouse or controller; the followed quest's says so with a star, not by
## color alone (#68), and takes no press. It only reads the quests but for that pick, keeps
## up with them while
## shown, and scrolls when the screen is too short for every quest. Its layout lives in its scene,
## quests_tab.tscn (#437): this script keeps only what it does.
## The people and places its steps and its pills name are links to their codex pages (NameLinks,
## #1446): a mouse click, a long press on touch, or a controller focusing the text and stepping
## through its names selects one, raising `name_selected`.
## A name shown here isn't met (CodexKeeper): the player meets it where they come across it, in the
## dialog that gave the quest or by entering the place (#1209), so a new player's book stays empty.

## A name in a step or a pill was selected (NameLinks): the kind of its tag and its id.
signal name_selected(kind: String, id: String)

## The gap between rows, as the scene sets it.
const GAP: float = 8.0
## How far a quest's steps sit in from its name, in gaps.
const STEP_INDENT: float = 3.0
const DONE_STEP: String = "Done: "
const CURRENT_STEP: String = "Now: "
const LATER_STEP: String = "Later: "
const NONE_TEXT: String = "No open quests"
const FOLLOW_TEXT: String = "Follow"
const FOLLOWED_TEXT: String = "★ Following"
## A quest pill: the instance a step counts in.
const PILL: PackedScene = preload("res://slices/quests/ui/quest_pill.tscn")

## Whose quests are shown: this machine's player's.
@export var keeper: QuestKeeper
## The running session, which says the instance this machine's player is in, for the pills.
@export var driver: Session

## What the tab shows for each open quest, by quest id: its steps' lines, one per line. Kept here
## so tests can read it. As the player reads them; `_tagged` keeps them with their text tags.
var shown: Dictionary[String, String] = {}
## Each open quest's pill, by quest id, while the tab shows it. Kept so tests can read them.
var pills: Dictionary[String, QuestPill] = {}
## Each open quest's button following it, by quest id, while the tab shows it. Kept so tests can
## press them.
var follow_buttons: Dictionary[String, Button] = {}
## Each open quest's steps' lines with their text tags (#733), by quest id, when the rows were
## built.
var _tagged: Dictionary[String, String] = {}
## The quest followed when the rows were built.
var _followed: String = ""
## The instance this machine's player was in when the rows were built.
var _here: String = ""
## The instance each open quest's current step counts in, by quest id, when the rows were built.
var _wheres: Dictionary[String, String] = {}

@onready var _rows: VBoxContainer = $Middle/Rows


func _ready() -> void:
	_show({}, {}, {}, "", "")


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## The menu's title for this tab (#1677): a literal tr(), so the translation template has it; the
## node keeps its English name, which the tests find it by.
func tab_title() -> String:
	return tr("Quests")


## Shows the open quests as they are now; builds the rows anew only when that changed.
func refresh() -> void:
	var lines: Dictionary[String, String] = {}
	var names: Dictionary[String, String] = {}
	var wheres: Dictionary[String, String] = {}
	var quests: QuestTracker = keeper.quests() if keeper != null else null
	if quests != null:
		for id: String in quests.open_steps():
			names[id] = quests.book[id].shown_name()
			lines[id] = "\n".join(quest_lines(quests, id, true))
			var step: QuestStep = quests.book[id].step_at(quests.progress_of(id).step)
			wheres[id] = step.counts_in() if step != null else ""
	var here: String = driver.local_instance_name() if driver != null else ""
	var followed: String = quests.focused() if quests != null else ""
	if lines != _tagged or wheres != _wheres or here != _here or followed != _followed:
		_show(names, lines, wheres, here, followed)


## Follows the quest `id` (#1298).
func _follow(id: String) -> void:
	if keeper != null:
		keeper.follow(id)


## Makes the rows `width` pixels wide.
func fit(width: float) -> void:
	_rows.custom_minimum_size.x = width


## The steps of the open quest `id` of `quests` on the player's way, worded: the ones done, in the
## order done, the one it's on with its count, and the ones sure to come later, up to its next
## choice (#573), whose way on isn't known yet. As the player reads them, or with their text tags
## (#733) when `tagged`.
static func quest_lines(quests: QuestTracker, id: String, tagged: bool = false) -> Array[String]:
	var progress: QuestProgress = quests.progress_of(id)
	var quest: QuestDefinition = quests.book[id]
	var lines: Array[String] = _done_lines(quest, progress)
	var current: QuestStep = quest.step_at(progress.step)
	if current != null:
		lines.append(CURRENT_STEP + QuestListView.step_tagged(current, progress.count))
	for index: int in quest.steps_after(progress.step):
		lines.append(LATER_STEP + QuestListView.step_tagged(quest.steps[index], 0))
	if not tagged:
		for at: int in lines.size():
			lines[at] = TextTags.shown(lines[at])
	return lines


## The steps of `quest` that `progress` has done, worded in the order done: a step with choices as
## the choice taken, the one leading to the step after it on the way.
static func _done_lines(quest: QuestDefinition, progress: QuestProgress) -> Array[String]:
	var way: Array[int] = progress.done.duplicate()
	way.append(progress.step)
	var lines: Array[String] = []
	for at: int in progress.done.size():
		var step: QuestStep = quest.step_at(way[at])
		if step != null:
			var taken: QuestStep = quest.choice_to(way[at], way[at + 1])
			var shown_step: QuestStep = taken if taken != null else step
			lines.append(DONE_STEP + QuestListView.step_tagged(shown_step, shown_step.count))
	return lines


## Builds the rows: each quest's name from `names` and its `lines` (with text tags) below it, by
## quest id, the pill naming its instance from `wheres` between them, filled when that's `here`, the
## instance this machine's player is in, and the button following it beside its name, saying so for
## `followed`.
func _show(
	names: Dictionary[String, String],
	lines: Dictionary[String, String],
	wheres: Dictionary[String, String],
	here: String,
	followed: String,
) -> void:
	_tagged = lines
	shown = {}
	for id: String in lines:
		shown[id] = TextTags.shown(lines[id])
	_wheres = wheres
	_here = here
	_followed = followed
	pills.clear()
	follow_buttons.clear()
	for row: Node in _rows.get_children():
		row.queue_free()
	if names.is_empty():
		_rows.add_child(MenuWidgets.label(NONE_TEXT))
	for id: String in names:
		pills[id] = _add_quest(names[id], lines[id], id, id == followed)
		pills[id].show_instance(wheres[id], wheres[id] == here)


## Adds the rows of quest `id`: its name `quest_name` beside the button following it, which says
## so when it's `followed`, its pill, and its steps' `lines` set in below it; returns the pill.
func _add_quest(quest_name: String, lines: String, id: String, followed: bool) -> QuestPill:
	var heading: HBoxContainer = HBoxContainer.new()
	var title: Label = MenuWidgets.label(quest_name)
	# Fills the row, its button at the end: trimmed to nothing otherwise.
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var follow: Button = MenuWidgets.button(
		FOLLOWED_TEXT if followed else FOLLOW_TEXT,
		_follow.bind(id),
	)
	follow.disabled = followed
	heading.add_child(follow)
	follow_buttons[id] = follow
	_rows.add_child(heading)
	var pill: QuestPill = PILL.instantiate() as QuestPill
	_forward(pill)
	_rows.add_child(pill)
	pill.fit(get_theme_default_font_size())
	pill.links_on(true)
	var steps: MarginContainer = MarginContainer.new()
	steps.add_theme_constant_override("margin_left", roundi(GAP * STEP_INDENT))
	var column: VBoxContainer = VBoxContainer.new()
	for line: String in lines.split("\n", false):
		column.add_child(_step_links(line))
	steps.add_child(column)
	_rows.add_child(steps)
	return pill


## The text of a step's `line`, a text with text tags, its names links raised as the tab's own.
func _step_links(line: String) -> NameLinks:
	var step: NameLinks = NameLinks.new()
	_forward(step)
	step.show_tagged(line)
	return step


## Raises the names `links` (a NameLinks or a QuestPill) selects as the tab's own.
func _forward(links: Control) -> void:
	var _selected: int = links.connect(&"name_selected", name_selected.emit)
