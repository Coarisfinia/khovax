class_name QuestSave
extends RefCounted
## The player's quests' part of the profile's save (#37, #855): their progress (`quest_progress`)
## and the ones finished (`quests_done`), kept in the profile's file by QuestKeeper, its companion.
## Integers and ids only, every value checked as it's read, and brought up to date from older
## formats one step at a time, at the profile's save format (ProfileSave.FORMAT).

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
	return { "quest_progress": progress, "quests_done": tracker.finished }


## Brings the quests in the save `data`, in save format `format`, up to the current one, oldest
## step first.
static func migrate(data: Dictionary, format: int) -> void:
	# Format 2 to 3: quests (#184) start with no progress.
	if format < 3:
		data["quest_progress"] = {}
		data["quests_done"] = []
	# Format 4 to 5: monsters are dominated, not captured (#317), and so is the first quest.
	if format < 5:
		_rename_quest(data, OLD_FIRST_QUEST, NEW_FIRST_QUEST)
	if format < 9:
		_keep_done(data)
	# Format 13 to 14: a species' id is its name (#763), and so are the quest ids that named one.
	if format < 14:
		for old_id: String in OLD_QUESTS:
			_rename_quest(data, old_id, OLD_QUESTS[old_id])
	# Format 15 to 16: the instances have Land-speech ids (#975), and so do the quest ids that named
	# one.
	if format < 16:
		for old_id: String in OLD_INSTANCE_QUESTS:
			_rename_quest(data, old_id, OLD_INSTANCE_QUESTS[old_id])


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
