class_name QuestsTab
extends ScrollContainer
## The menu's Quests tab (#388): the same open quests as the list at the side of the screen (#340,
## Profile.open_steps), each with its name and every one of its steps, worded as the list words
## them (QuestListView.step_line): the steps done, the one it's on with its count, and the ones
## still to come. Each step says which it is in words, never by color alone (#68). It only reads
## the profile, keeps up with it while shown, and scrolls when the screen is too short for every
## quest. Its layout lives in its scene, quests_tab.tscn (#437): this script keeps only what it
## does.

## The gap between rows, as the scene sets it.
const GAP: float = 8.0
## How far a quest's steps sit in from its name, in gaps.
const STEP_INDENT: float = 3.0
const DONE_STEP: String = "Done: "
const CURRENT_STEP: String = "Now: "
const LATER_STEP: String = "Later: "
const NONE_TEXT: String = "No open quests"

## Whose quests are shown: this machine's player's profile.
var holder: ProfileHolder
## What the tab shows for each open quest, by quest id: its steps' lines, one per line. Kept here
## so tests can read it.
var shown: Dictionary[String, String] = {}

@onready var _rows: VBoxContainer = $Middle/Rows


func _ready() -> void:
	_show({}, {})


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## Shows the open quests as they are now; builds the rows anew only when that changed.
func refresh() -> void:
	var lines: Dictionary[String, String] = {}
	var names: Dictionary[String, String] = {}
	if holder != null and holder.keeper != null:
		var profile: Profile = holder.keeper.profile
		for id: String in profile.open_steps():
			names[id] = profile.quest_book[id].name
			lines[id] = "\n".join(quest_lines(profile, id))
	if lines != shown:
		_show(names, lines)


## Makes the rows `width` pixels wide.
func fit(width: float) -> void:
	_rows.custom_minimum_size.x = width


## Each step of `profile`'s open quest `id`, worded: done, the one it's on with its count, or
## later.
static func quest_lines(profile: Profile, id: String) -> Array[String]:
	var progress: QuestProgress = profile.quest_progress.get(id, QuestProgress.new())
	var steps: Array[QuestStep] = profile.quest_book[id].steps
	var lines: Array[String] = []
	for index: int in steps.size():
		var step: QuestStep = steps[index]
		var prefix: String = LATER_STEP
		var count: int = 0
		if index < progress.step:
			prefix = DONE_STEP
			count = step.count
		elif index == progress.step:
			prefix = CURRENT_STEP
			count = progress.count
		lines.append(prefix + QuestListView.step_line(step, count))
	return lines


## Builds the rows: each quest's name from `names` and its `lines` below it, by quest id.
func _show(names: Dictionary[String, String], lines: Dictionary[String, String]) -> void:
	shown = lines
	for row: Node in _rows.get_children():
		row.queue_free()
	if names.is_empty():
		_rows.add_child(GameMenu.label(NONE_TEXT))
	for id: String in names:
		_add_quest(names[id], lines[id])


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
