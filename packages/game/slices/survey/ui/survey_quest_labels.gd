class_name SurveyQuestLabels
extends Control
## The labels on the Survey's quest markers (#1278), over the SurveyView it's a child of: above each
## open quest's arrow (SurveyView.quest_targets) a small card names the quest, with the pill under
## its name naming the instance its step counts in, as the quest list shows it (QuestMarkerLabel,
## QuestPill, #794): filled while this machine's player is there, outlined with an arrow while
## elsewhere, and none while the step counts anywhere. A step with choices labels each choice's
## arrow with that choice's instance. Labels keep inside the Survey, and one that would cover
## another, or a player's circle (#1289), moves up above it, in the quests' order; one that still
## can't fit is left out. A Survey too small for them, like one in a corner, which the quest list
## sits beside anyway, shows its arrows bare, and an arrow off the Survey has no label. It only
## reads what the Survey worked out and this machine's player's quests, after the Survey each frame.

## A quest marker's label: the quest's name and its pill.
const LABEL: PackedScene = preload("res://slices/quests/ui/quest_marker_label.tscn")
## The Survey's shorter side, in pixels, below which it shows no labels.
const MIN_SIDE: float = 400.0
## The labels' font size, as a share of the Survey's shorter side, within the sizes below.
const FONT_SHARE: float = 0.03
const MIN_FONT: int = 14
const MAX_FONT: int = 20
## The room between labels, in pixels.
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
		if minf(survey.size.x, survey.size.y) >= MIN_SIDE:
			targets = _on_view(survey)
	for key: String in labels.keys():
		if not targets.has(key):
			labels[key].queue_free()
			var _dropped: bool = labels.erase(key)
	if not targets.is_empty():
		_show(survey, targets)


## The arrows `survey` shows whose tips are on it, by key.
static func _on_view(survey: SurveyView) -> Dictionary[String, Vector2i]:
	var shown: Dictionary[String, Vector2i] = {}
	var view: Rect2 = Rect2(Vector2.ZERO, survey.size)
	for key: String in survey.quest_targets:
		if view.has_point(survey.to_view(survey.quest_targets[key])):
			shown[key] = survey.quest_targets[key]
	return shown


## Shows a label over each arrow of `targets`, the arrows `survey` shows, by key.
func _show(survey: SurveyView, targets: Dictionary[String, Vector2i]) -> void:
	var quests: QuestTracker = survey.quest_keeper.quests()
	var steps: Dictionary[String, QuestStep] = quests.open_steps()
	var font: int = clampi(
		roundi(minf(survey.size.x, survey.size.y) * FONT_SHARE),
		MIN_FONT,
		MAX_FONT,
	)
	# The players' circles go first, so labels keep clear of them as they do of each other.
	var placed: Array[Rect2] = survey.circle_boxes()
	for key: String in targets:
		var step: QuestStep = _step_of(steps, key)
		if step == null:
			continue
		var label: QuestMarkerLabel = _label(key)
		var shown_name: String = quests.book[key.get_slice("/", 0)].shown_name()
		var where: String = step.counts_in()
		label.show_quest(shown_name, where, where == survey.driver.local_instance_name())
		label.fit(font)
		label.reset_size()
		label.position = _spot(label.size, survey.arrow_top(targets[key]), survey.size, placed)
		label.visible = _fits(label.get_rect(), survey.size, placed)
		if label.visible:
			placed.append(label.get_rect())


## Where a label `box` big goes, its top left corner: its bottom's middle on `top`, the top of its
## arrow, moved inside a Survey `area` big, and up above each of the labels and circles already
## `placed` it would cover, as long as it stays inside.
static func _spot(box: Vector2, top: Vector2, area: Vector2, placed: Array[Rect2]) -> Vector2:
	var corner: Vector2 = (top - Vector2(box.x / 2.0, box.y)).clamp(Vector2.ZERO, area - box)
	var moved: bool = true
	while moved:
		moved = false
		for other: Rect2 in placed:
			if other.intersects(Rect2(corner, box)) and other.position.y - GAP - box.y >= 0.0:
				corner.y = other.position.y - GAP - box.y
				moved = true
	return corner


## Whether `box` lies inside a Survey `area` big, clear of the labels and circles already `placed`:
## a label that can't, as one too wide or crowded against the top edge, isn't shown.
static func _fits(box: Rect2, area: Vector2, placed: Array[Rect2]) -> bool:
	if not Rect2(Vector2.ZERO, area).encloses(box):
		return false
	for other: Rect2 in placed:
		if other.intersects(box):
			return false
	return true


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
