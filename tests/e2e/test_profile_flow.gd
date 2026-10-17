extends RefCounted
## Profile flow (#37): the player's profile across sessions. A new profile starts with one slot and
## nothing dominated; every gain adds its dominations, with ids that are never reused, and its
## materials, and is on disk at once; the profile survives saving and loading; a save it can't trust
## is refused; an older save is migrated, oldest step first, into the current format with no quest
## progress (#184); the first three monsters dominated are carried (#53); and a damaged save falls
## back to the newest intact generation before it (#179).

const SAVE_PATH: String = "user://test_profile.json"


func run(_tree: SceneTree) -> String:
	var profile: Profile = Profile.new()
	if profile.unlocked_slots != 1 or not profile.dominated_monsters.is_empty():
		return "a new profile doesn't start with one slot and nothing dominated"
	var applied: String = profile.apply(_result(["ember_fox", "moss_toad"], { "crystal": 2 }))
	applied += profile.apply(_result(["ember_fox"], { "crystal": 1, "feather": 3 }))
	if not applied.is_empty():
		return "a valid gain was refused: " + applied
	var ids: Array[int] = []
	for monster: DominatedMonster in profile.dominated_monsters:
		ids.append(monster.id)
	var expected: Array[int] = [1, 2, 3]
	var expected_materials: Dictionary[String, int] = { "crystal": 3, "feather": 3 }
	if ids != expected or profile.materials != expected_materials or profile.carried != expected:
		return "two gains gave monsters %s, materials %s and carried %s" % [
			ids,
			profile.materials,
			profile.carried,
		]
	var result: String = _check_kept_at_once()
	if result.is_empty():
		result = _check_bad_results(profile)
	if result.is_empty():
		result = _check_save(profile)
	if result.is_empty():
		result = _check_refused()
	if result.is_empty():
		result = _check_migrated()
	if result.is_empty():
		result = _check_recovered()
	SaveStore.remove(SAVE_PATH)
	return result


## Saving is debounced (owner, #73): the first domination after a quiet spell is on disk at once, a
## burst right after it is saved together once SAVE_INTERVAL_MSEC has passed, and ending the session
## flushes whatever is pending.
func _check_kept_at_once() -> String:
	var keeper: ProfileKeeper = ProfileKeeper.new(Profile.new(), SAVE_PATH)
	var problem: String = keeper.take(_result(["moss_toad"], {}), 0)
	if not problem.is_empty() or _monsters_on_disk() != 1:
		return "the first domination wasn't on disk right away: " + problem
	for ms: int in range(100, 5000, 100):
		problem += keeper.take(_result(["moss_toad"], {}), ms)
	var interval: int = ProfileKeeper.SAVE_INTERVAL_MSEC
	problem += keeper.save_if_due(interval - 1)
	if not problem.is_empty() or _monsters_on_disk() != 1:
		return "a burst of dominations was saved before the interval passed: " + problem
	problem = keeper.save_if_due(interval)
	if not problem.is_empty() or _monsters_on_disk() != 50:
		return "the burst wasn't saved once the interval passed: " + problem
	problem = keeper.take(_result(["moss_toad"], {}), interval + 1) + keeper.end_session()
	var on_disk: Profile = SaveStore.load_profile(SAVE_PATH)
	SaveStore.remove(SAVE_PATH)
	if not problem.is_empty() or on_disk.dominated_monsters.size() != 51:
		return "ending the session didn't flush the pending domination: " + problem
	return ""


func _monsters_on_disk() -> int:
	return SaveStore.load_profile(SAVE_PATH).dominated_monsters.size()


## A gain the profile couldn't save is refused whole, and the profile stays as it was.
func _check_bad_results(profile: Profile) -> String:
	var before: String = ProfileSave.to_text(profile)
	var no_chests: Gain = _result(["moss_toad"], {})
	no_chests.chests_opened = -1
	var bad: Array[Gain] = [
		no_chests,
		_result(["ember_fox", ""], {}),
		_result([], { "crystal": -1 }),
		_result([], { "": 1 }),
		_result([], { "crystal": Profile.MAX_NUMBER }),
	]
	for result: Gain in bad:
		if profile.apply(result).is_empty():
			return "a bad gain was taken over: %s %s" % [
				result.dominated_species,
				result.materials,
			]
	if ProfileSave.to_text(profile) != before:
		return "a refused gain still changed the profile"
	return ""


## Saving and loading gives back the same profile, with the next id still unused.
func _check_save(profile: Profile) -> String:
	var problem: String = SaveStore.save_profile(profile, SAVE_PATH)
	if not problem.is_empty():
		return problem
	var loaded: Profile = SaveStore.load_profile(SAVE_PATH)
	SaveStore.remove(SAVE_PATH)
	if not loaded.problem.is_empty() or ProfileSave.to_text(loaded) != ProfileSave.to_text(profile):
		return "the loaded profile differs from the saved one: " + loaded.problem
	if FileAccess.file_exists(SAVE_PATH + ".tmp"):
		return "saving left its temporary file behind"
	var _dominated: String = loaded.apply(_result(["moss_toad"], {}))
	var three: Array[int] = [1, 2, 3]
	if loaded.dominated_monsters.back().id != 4 or loaded.carried != three:
		return "a monster dominated after loading reused an id or joined the carried three"
	if not SaveStore.load_profile(SAVE_PATH).dominated_monsters.is_empty():
		return "without a save, the game didn't start a new profile"
	return ""


## A save that isn't one, comes from a newer build, or contradicts itself is refused, not misread.
func _check_refused() -> String:
	var text: String = ProfileSave.to_text(Profile.new())
	var format: String = "\"format\": %d" % ProfileSave.FORMAT
	var done: String = "\"quests_done\": []"
	var progress: String = "\"quest_progress\": {}"
	var cases: Dictionary[String, String] = {
		"not json": "not a profile save",
		text.replace(format, "\"format\": 99"): "save format 99",
		text.replace(done, "\"quests_done\": [\"a\", \"a\"]"): "a finished quest",
		text.replace(done, "\"quests_done\": [7]"): "a finished quest",
		text.replace(done, "\"quests_done\": [\"Bad id\"]"): "a finished quest",
		text.replace(progress, "\"quest_progress\": {\"Bad id\": {\"step\": 0, \"count\": 0}}"): (
			"quest Bad id's"
		),
		text.replace(progress, "\"quest_progress\": {\"a\": {\"step\": 0, \"count\": 1e10}}"): (
			"quest a's"
		),
		text.replace(progress, "\"quest_progress\": {\"a\": {\"step\": -1, \"count\": 0}}"): (
			"quest a's"
		),
		text.replace(progress, "\"quest_progress\": {\"a\": {\"step\": 0}}"): "quest a's",
		text.replace(progress, "\"quest_progress\": []"): "the save lacks its quest",
		text.replace("\"unlocked_slots\": 1", "\"unlocked_slots\": 7"): "the save's slots",
		text.replace(
			"\"dominated_monsters\": []",
			"\"dominated_monsters\": [{\"id\": 5}]",
		): "a dominated",
		text.replace("\"unlocked_slots\": 1", "\"unlocked_slots\": 1.5"): "the save's slots",
		text.replace("\"next_monster_id\": 1", "\"next_monster_id\": 0"): "the save's slots",
		text.replace("\"carried\": []", "\"carried\": [5]"): "a carried monster isn't",
		text.replace("\"carried\": []", "\"carried\": {}"): "the save lacks its carried",
	}
	for case: String in cases:
		var problem: String = ProfileSave.parse(case).problem
		if not problem.begins_with(cases[case]):
			return "expected a refusal starting %s, got: %s" % [cases[case], problem]
	return ""


## Older saves load into the current format, migrated oldest step first: format 1 still counted
## finished runs (#197), formats before 3 had no quest progress (#184), which starts empty, and
## formats before 4 carried no monsters (#53): the first three dominated are carried then, and
## formats before 5 named them captured (#317).
func _check_migrated() -> String:
	var text: String = ProfileSave.to_text(Profile.new())
	var current: Dictionary = _as_captured(text)
	var _no_progress: bool = current.erase("quest_progress")
	var _none_done: bool = current.erase("quests_done")
	var _none_carried: bool = current.erase("carried")
	# Format 1 with its run count and without it, and format 2 with a stale run count and without.
	var olds: Array[Dictionary] = [
		{ "format": 1, "runs_finished": 3 },
		{ "format": 1 },
		{ "format": 2, "runs_finished": 3 },
		{ "format": 2 },
		{ "format": 3, "quest_progress": {}, "quests_done": [] },
		{ "format": 4, "quest_progress": {}, "quests_done": [], "carried": [] },
	]
	for old: Dictionary in olds:
		var save: Dictionary = current.duplicate()
		save.merge(old, true)
		var loaded: Profile = ProfileSave.parse(JSON.stringify(save))
		if not loaded.problem.is_empty() or ProfileSave.to_text(loaded) != text:
			return "an older save %s didn't load as the current one: %s" % [old, loaded.problem]
	var problem: String = _check_migrated_quest()
	return problem if not problem.is_empty() else _check_migrated_carried()


## A format 4 save's first quest, open or finished, is the renamed first quest (#317).
func _check_migrated_quest() -> String:
	var save: Dictionary = _as_captured(ProfileSave.to_text(Profile.new()))
	save["format"] = 4
	save["quest_progress"] = { "first_catch": { "step": 0, "count": 1 } }
	var open: Profile = ProfileSave.parse(JSON.stringify(save))
	var progress: QuestProgress = open.quest_progress.get("first_domination")
	if not open.problem.is_empty() or progress == null or progress.count != 1:
		return "a format 4 save's open first quest wasn't renamed: %s" % open.problem
	save["quest_progress"] = {}
	save["quests_done"] = ["first_catch"]
	var done: Profile = ProfileSave.parse(JSON.stringify(save))
	var expected: Array[String] = ["first_domination"]
	if not done.problem.is_empty() or done.quests_done != expected:
		return "a format 4 save's finished first quest wasn't renamed: %s" % done.problem
	return ""


## Current save `text` as data with its monsters under their name before format 5.
func _as_captured(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	data["captured_monsters"] = data["dominated_monsters"]
	var _renamed: bool = data.erase("dominated_monsters")
	return data


## A format 3 save with four monsters carries its first three; a format 4 save carrying one twice,
## or four, is refused.
func _check_migrated_carried() -> String:
	var profile: Profile = Profile.new()
	var four: Array = ["ember_fox", "moss_toad", "ember_fox", "moss_toad"]
	var _dominated: String = profile.apply(_result(four, {}))
	var save: Dictionary = _as_captured(ProfileSave.to_text(profile))
	save["format"] = 4
	for bad: Array in [[1, 1], [1, 2, 3, 4]]:
		var wrong: Dictionary = save.duplicate()
		wrong["carried"] = bad
		var problem: String = ProfileSave.parse(JSON.stringify(wrong)).problem
		if not problem.begins_with("a carried monster"):
			return "a save carrying %s wasn't refused: %s" % [bad, problem]
	var _dropped: bool = save.erase("carried")
	save["format"] = 3
	var loaded: Profile = ProfileSave.parse(JSON.stringify(save))
	var three: Array[int] = [1, 2, 3]
	if not loaded.problem.is_empty() or loaded.carried != three:
		return "a format 3 save didn't carry its first three monsters: %s" % loaded.problem
	return ""


func _result(species: Array, materials: Dictionary) -> Gain:
	var result: Gain = Gain.new()
	result.dominated_species.assign(species)
	result.materials.assign(materials)
	return result


## A damaged newest save, tampered with or cut short, falls back to the newest intact generation
## before it; with every generation damaged the save is refused; and a plain save from before
## checksums still loads.
func _check_recovered() -> String:
	SaveStore.remove(SAVE_PATH)
	var older: Profile = Profile.new()
	var _first: String = older.apply(_result(["moss_toad"], {}))
	var newer: Profile = Profile.new()
	var _second: String = newer.apply(_result(["moss_toad", "ember_fox"], {}))
	var problem: String = SaveStore.save_profile(older, SAVE_PATH)
	problem += SaveStore.save_profile(newer, SAVE_PATH)
	var newest: String = FileAccess.get_file_as_string(SAVE_PATH)
	var damaged_saves: Array[String] = [
		newest.replace("ember_fox", "ember_cat"),
		newest.left(40),
		newest.replace("\"save\": 1", "\"saved\": 1"),
	]
	for damaged: String in damaged_saves:
		_write(SAVE_PATH, damaged)
		var loaded: Profile = SaveStore.load_profile(SAVE_PATH)
		if not problem.is_empty() or loaded.loaded_generation != 1:
			return "a damaged newest save didn't fall back a generation: " + problem
		if ProfileSave.to_text(loaded) != ProfileSave.to_text(older):
			return "the fallback isn't the save before the damaged one"
	for file: String in [SAVE_PATH, SAVE_PATH + ".1"]:
		_write(file, "{}")
	if SaveStore.load_profile(SAVE_PATH).problem.is_empty():
		return "a save with every generation damaged was read"
	SaveStore.remove(SAVE_PATH)
	_write(SAVE_PATH, ProfileSave.to_text(newer))
	if ProfileSave.to_text(SaveStore.load_profile(SAVE_PATH)) != ProfileSave.to_text(newer):
		return "a plain save from before checksums didn't load"
	return ""


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var _stored: bool = file.store_string(text)
	file.close()
