class_name QuestSave
extends RefCounted
## The player's quests' part of the profile's save (#37, #855): their progress (`quest_progress`),
## the ones finished (`quests_done`), the side quests started, in the order started
## (`quests_started`), and the one the player picked to follow (`quest_focus`, #1298), kept in the
## profile's file by QuestKeeper, its companion.
## Integers and ids only, every value checked as it's read, and brought up to date from older
## formats one step at a time, at the profile's format changes (ProfileSave.CHANGES).

## The profile's format changes that changed the quests' keys, each named for its step.
const QUESTS: String = "184-quests"
const DOMINATED: String = "317-dominated-monsters"
const STEPS_DONE: String = "573-quest-steps-done"
const SPECIES_IDS: String = "763-species-ids"
const INSTANCE_IDS: String = "975-instance-ids"
## The one that brought the quest the player follows and the order side quests started in (#1298).
const FOCUS: String = "1298-quest-focus"
## The first quest's id before format 5, and since (#317).
const OLD_FIRST_QUEST: String = "first_catch"
const NEW_FIRST_QUEST: String = "first_domination"
## The quest ids before format 14 that named a species by its old id, each to its id since (#763).
const OLD_QUESTS: Dictionary[String, String] = { "three_moss_toads": "three_ombulumo" }
## The quest ids before format 16 that named an instance by its old id, each to its id since (#975).
const OLD_INSTANCE_QUESTS: Dictionary[String, String] = {
	"glade_fork": "lumwen_hoal_fork",
	"guild_charts_the_forest": "guild_charts_morwe_wudhen",
	"guild_holds_the_outpost": "guild_holds_edhra_tewk",
}


## The quests of `tracker` as save data, by key.
static func beside(tracker: QuestTracker) -> Dictionary:
	var progress: Dictionary = {}
	var ids: Array[String] = []
	ids.assign(tracker.progress.keys())
	ids.sort()
	for id: String in ids:
		var at: QuestProgress = tracker.progress[id]
		progress[id] = { "step": at.step, "count": at.count, "done": at.done }
	return {
		"quest_progress": progress,
		"quests_done": tracker.finished,
		"quests_started": tracker.started,
		"quest_focus": tracker.focus,
	}


## Brings the quests in the save `data`, written with the profile's format changes `changes`, up to
## the current format: a step for each change it lacks, oldest first.
static func migrate(data: Dictionary, changes: Array[String]) -> void:
	# Quests (#184) start with no progress.
	if not changes.has(QUESTS):
		data["quest_progress"] = {}
		data["quests_done"] = []
	# Monsters are dominated, not captured (#317), and so is the first quest.
	if not changes.has(DOMINATED):
		_rename_quest(data, OLD_FIRST_QUEST, NEW_FIRST_QUEST)
	if not changes.has(STEPS_DONE):
		_keep_done(data)
	# A species' id is its name (#763), and so are the quest ids that named one.
	if not changes.has(SPECIES_IDS):
		for old_id: String in OLD_QUESTS:
			_rename_quest(data, old_id, OLD_QUESTS[old_id])
	# The instances have Land-speech ids (#975), and so do the quest ids that named one.
	if not changes.has(INSTANCE_IDS):
		for old_id: String in OLD_INSTANCE_QUESTS:
			_rename_quest(data, old_id, OLD_INSTANCE_QUESTS[old_id])
	# The player follows the newest quest (#1298), and the order side quests started in wasn't
	# kept, so the ones started count as started in id order.
	if not changes.has(FOCUS):
		var progress: Variant = data.get("quest_progress")
		var by_id: Dictionary = progress if progress is Dictionary else {}
		var ids: Array = by_id.keys()
		ids.sort()
		data["quests_started"] = ids
		data["quest_focus"] = ""


## Format 8 to 9: a quest's progress keeps the steps done (#573). Quests had no choices before, so
## every step before the one it's on was done, in order: at most QuestProgress.MAX_DONE of them,
## the latest.
static func _keep_done(data: Dictionary) -> void:
	var progress: Variant = data.get("quest_progress")
	var by_id: Dictionary = progress if progress is Dictionary else {}
	for id: Variant in by_id:
		if by_id[id] is Dictionary:
			var entry: Dictionary = by_id[id]
			var at: int = _int(entry.get("step"))
			entry["done"] = range(maxi(0, at - QuestProgress.MAX_DONE), maxi(0, at))


## Renames the quest `old_id` to `new_id` in the save `data`'s progress and finished quests.
static func _rename_quest(data: Dictionary, old_id: String, new_id: String) -> void:
	var progress: Variant = data.get("quest_progress")
	var by_id: Dictionary = progress if progress is Dictionary else {}
	if by_id.has(old_id):
		by_id[new_id] = by_id[old_id]
		var _moved: bool = by_id.erase(old_id)
	var done: Variant = data.get("quests_done")
	if done is Array:
		var done_list: Array = done
		var at: int = done_list.find(old_id)
		if at >= 0:
			done_list[at] = new_id


## Reads the current-format save `data`'s quests into `tracker`, which has none yet; returns why it
## can't, or "".
static func read(tracker: QuestTracker, data: Dictionary) -> String:
	var started: Variant = data.get("quest_progress")
	var done: Variant = data.get("quests_done")
	if not started is Dictionary or not done is Array:
		return "the save lacks its quest progress"
	var done_list: Array = done
	for id: Variant in done_list:
		var text: String = Content.text_of(id)
		if not Content.is_id(text) or tracker.finished.has(text):
			return "a finished quest in the save has no valid id or is there twice"
		tracker.finished.append(text)
	var by_id: Dictionary = started
	for id: Variant in by_id:
		var progress: QuestProgress = _quest_progress(by_id[id])
		if progress == null or not Content.is_id(str(id)) or tracker.finished.has(str(id)):
			return "quest %s's progress in the save is malformed or it's finished" % id
		tracker.progress[str(id)] = progress
	return _read_focus(tracker, data)


## Reads the side quests started and the quest followed (#1298) from the save `data` into
## `tracker`, whose progress is read; returns why it can't, or "". A quest started is one with
## progress, there once, and the quest followed is an id or "".
static func _read_focus(tracker: QuestTracker, data: Dictionary) -> String:
	var order: Variant = data.get("quests_started")
	var focus: Variant = data.get("quest_focus")
	if not order is Array or not focus is String:
		return "the save lacks the quests started or the one followed"
	var order_list: Array = order
	for id: Variant in order_list:
		var text: String = Content.text_of(id)
		if not tracker.progress.has(text) or tracker.started.has(text):
			return "a quest started in the save has no progress or is there twice"
		tracker.started.append(text)
	var focus_text: String = Content.text_of(focus)
	if not focus_text.is_empty() and not Content.is_id(focus_text):
		return "the quest followed in the save has no valid id"
	tracker.focus = focus_text
	return ""


## A quest's progress from save data, or null when it's malformed: a step and a count, each a
## whole number from 0 to Profile.MAX_NUMBER, and the steps done (#573), at most
## QuestProgress.MAX_DONE of them, each such a number too.
static func _quest_progress(entry: Variant) -> QuestProgress:
	if not entry is Dictionary:
		return null
	var data: Dictionary = entry
	var progress: QuestProgress = QuestProgress.new(_int(data.get("step")), _int(data.get("count")))
	var done: Variant = data.get("done")
	if progress.step < 0 or progress.count < 0 or data.size() != 3 or not done is Array:
		return null
	var done_list: Array = done
	if done_list.size() > QuestProgress.MAX_DONE:
		return null
	for index: Variant in done_list:
		if _int(index) < 0:
			return null
		progress.done.append(_int(index))
	return progress


## A whole JSON number from 0 to Profile.MAX_NUMBER as an integer; -1 for anything else, so a
## fraction or an out-of-range number is refused instead of rounded.
static func _int(value: Variant) -> int:
	return JsonNumbers.whole(value, 0, Profile.MAX_NUMBER, -1)
