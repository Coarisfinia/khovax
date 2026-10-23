class_name SurveyQuestLabels
extends Control
## The labels on the Survey's quest markers (#1278), over the SurveyView it's a child of: above each
## open quest's arrow (SurveyView.quest_targets) a small card names the quest, with the pill under
## its name naming the instance its step counts in, as the quest list shows it (QuestMarkerLabel,
## QuestPill, #794): filled while this machine's player is there, outlined with an arrow while
## elsewhere, and none while the step counts anywhere. A step with choices labels each choice's
## arrow with that choice's instance. Labels over one tile stack upwards in the quests' order. It
## only reads what the Survey worked out and this machine's player's quests, after the Survey each
## frame.

## A quest marker's label: the quest's name and its pill.
const LABEL: PackedScene = preload("res://slices/quests/ui/quest_marker_label.tscn")
## The labels' font size, as a share of the Survey's shorter side, within the sizes below: small in
## a corner, never past what reads well over the whole screen.
const FONT_SHARE: float = 0.04
const MIN_FONT: int = 12
const MAX_FONT: int = 20
## The room between labels stacked over one tile, in pixels.
const GAP: float = 2.0

## Each label shown, by the key its arrow has in SurveyView.quest_targets. Kept so tests can read
## them.
var labels: Dictionary[String, QuestMarkerLabel] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	# After the Survey, its parent, which processes first.
	if is_visible_in_tree():
		show_state()


## Labels the arrows the Survey shows, each over its arrow. Called every frame while it shows;
## tests call it directly, after the Survey's own.
func show_state() -> void:
	var survey: SurveyView = get_parent() as SurveyView
	var targets: Dictionary[String, Vector2i] = {}
	if survey != null and survey.quest_keeper != null and survey.quest_keeper.quests() != null:
		targets = survey.quest_targets
	for key: String in labels.keys():
		if not targets.has(key):
			labels[key].queue_free()
			var _dropped: bool = labels.erase(key)
	if not targets.is_empty():
		_show(survey, targets)


## Shows a label over each arrow of `targets`, the arrows `survey` shows, by key.
func _show(survey: SurveyView, targets: Dictionary[String, Vector2i]) -> void:
	var quests: QuestTracker = survey.quest_keeper.quests()
	var steps: Dictionary[String, QuestStep] = quests.open_steps()
	var font: int = clampi(
		roundi(minf(survey.size.x, survey.size.y) * FONT_SHARE),
		MIN_FONT,
		MAX_FONT,
	)
	var stacked: Dictionary[Vector2i, float] = {}
	for key: String in targets:
		var step: QuestStep = _step_of(steps, key)
		if step == null:
			continue
		var label: QuestMarkerLabel = _label(key)
		var shown_name: String = quests.book[key.get_slice("/", 0)].shown_name()
		var where: String = step.counts_in()
		label.show_quest(shown_name, where, where == survey.driver.local_instance_name())
		label.fit(font)
		_place(label, survey.arrow_top(targets[key]), targets[key], stacked)


## Puts `label` with its bottom's middle on `top`, the top of its arrow on `tile`, or over the
## labels already `stacked` there, by how high they stack on each tile; counts it in.
static func _place(
	label: QuestMarkerLabel,
	top: Vector2,
	tile: Vector2i,
	stacked: Dictionary[Vector2i, float],
) -> void:
	label.reset_size()
	var bottom: Vector2 = top - Vector2(0.0, stacked.get(tile, 0.0))
	label.position = bottom - Vector2(label.size.x / 2.0, label.size.y)
	stacked[tile] = stacked.get(tile, 0.0) + label.size.y + GAP


## The step the arrow `key` points for, of the open `steps`: the quest's current step, or the
## choice its key names after a slash (QuestTargets.of); null when its quest isn't open.
static func _step_of(steps: Dictionary[String, QuestStep], key: String) -> QuestStep:
	var id: String = key.get_slice("/", 0)
	if not steps.has(id):
		return null
	if key.get_slice_count("/") < 2:
		return steps[id]
	return steps[id].triggers()[key.get_slice("/", 1).to_int()]


## The label of the arrow `key`, made the first time it's asked for.
func _label(key: String) -> QuestMarkerLabel:
	if not labels.has(key):
		var label: QuestMarkerLabel = LABEL.instantiate() as QuestMarkerLabel
		add_child(label)
		labels[key] = label
	return labels[key]
