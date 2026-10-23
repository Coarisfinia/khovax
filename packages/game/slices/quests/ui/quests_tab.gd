class_name QuestsTab
extends ScrollContainer
## The menu's Quests tab (#388): the same open quests as the list at the side of the screen (#340,
## QuestTracker.open_steps), each with its name and path mark (#471) and its steps on the player's
## way, worded as the list words them (QuestListView.step_line): the steps done, the one it's on
## with its count, and the ones still to come up to its next choice (#573). Each step says which it
## is in words, never by color alone (#68). Under each quest's name, a pill names the instance its
## current step counts in, as the list shows it (QuestPill, #794). It only reads the quests, keeps
## up with them while
## shown, and scrolls when the screen is too short for every quest. Its layout lives in its scene,
## quests_tab.tscn (#437): this script keeps only what it does.

## The gap between rows, as the scene sets it.
const GAP: float = 8.0
## How far a quest's steps sit in from its name, in gaps.
const STEP_INDENT: float = 3.0
const DONE_STEP: String = "Done: "
const CURRENT_STEP: String = "Now: "
const LATER_STEP: String = "Later: "
const NONE_TEXT: String = "No open quests"
## A quest pill: the instance a step counts in.
const PILL: PackedScene = preload("res://slices/quests/ui/quest_pill.tscn")

## Whose quests are shown: this machine's player's.
var keeper: QuestKeeper
## The running session, which says the instance this machine's player is in, for the pills.
var driver: Session
## What the tab shows for each open quest, by quest id: its steps' lines, one per line. Kept here
## so tests can read it.
var shown: Dictionary[String, String] = {}
## Each open quest's pill, by quest id, while the tab shows it. Kept so tests can read them.
var pills: Dictionary[String, QuestPill] = {}
## The instance this machine's player was in when the rows were built.
var _here: String = ""

@onready var _rows: VBoxContainer = $Middle/Rows


func _ready() -> void:
	_show({}, {}, "")


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## Shows the open quests as they are now; builds the rows anew only when that changed.
func refresh() -> void:
	var lines: Dictionary[String, String] = {}
	var names: Dictionary[String, String] = {}
	var quests: QuestTracker = keeper.quests() if keeper != null else null
	if quests != null:
		for id: String in quests.open_steps():
			names[id] = quests.book[id].shown_name()
			lines[id] = "\n".join(quest_lines(quests, id))
	var here: String = driver.local_instance_name() if driver != null else ""
	if lines != shown or here != _here:
		_show(names, lines, here)


## Makes the rows `width` pixels wide.
func fit(width: float) -> void:
	_rows.custom_minimum_size.x = width


## The steps of the open quest `id` of `quests` on the player's way, worded: the ones done, in the
## order done, the one it's on with its count, and the ones sure to come later, up to its next
## choice (#573), whose way on isn't known yet.
static func quest_lines(quests: QuestTracker, id: String) -> Array[String]:
	var progress: QuestProgress = quests.progress_of(id)
	var quest: QuestDefinition = quests.book[id]
	var lines: Array[String] = _done_lines(quest, progress)
	var current: QuestStep = quest.step_at(progress.step)
	if current != null:
		lines.append(CURRENT_STEP + QuestListView.step_line(current, progress.count))
	for index: int in quest.steps_after(progress.step):
		lines.append(LATER_STEP + QuestListView.step_line(quest.steps[index], 0))
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
			lines.append(DONE_STEP + QuestListView.step_line(shown_step, shown_step.count))
	return lines


## Builds the rows: each quest's name from `names` and its `lines` below it, by quest id, the pill
## between them filled when it names `here`, the instance this machine's player is in.
func _show(
	names: Dictionary[String, String],
	lines: Dictionary[String, String],
	here: String,
) -> void:
	shown = lines
	_here = here
	pills.clear()
	for row: Node in _rows.get_children():
		row.queue_free()
	if names.is_empty():
		_rows.add_child(GameMenu.label(NONE_TEXT))
	var quests: QuestTracker = keeper.quests() if keeper != null else null
	for id: String in names:
		_add_quest(names[id], lines[id])
		var step: QuestStep = quests.book[id].step_at(quests.progress_of(id).step)
		var where: String = step.counts_in() if step != null else ""
		pills[id] = PILL.instantiate() as QuestPill
		_rows.add_child(pills[id])
		_rows.move_child(pills[id], -2)
		pills[id].fit(get_theme_default_font_size())
		pills[id].show_instance(where, where == here)


## Adds a quest's rows: its name `quest_name`, and its steps' `lines` set in below it.
func _add_quest(quest_name: String, lines: String) -> void:
	_rows.add_child(GameMenu.label(quest_name))
	var steps: MarginContainer = MarginContainer.new()
	steps.add_theme_constant_override("margin_left", roundi(GAP * STEP_INDENT))
	var column: VBoxContainer = VBoxContainer.new()
	for line: String in lines.split("\n", false):
		column.add_child(GameMenu.label(line))
	steps.add_child(column)
	_rows.add_child(steps)
