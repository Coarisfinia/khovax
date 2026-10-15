extends RefCounted
## Profile flow (#37): the player's profile across runs. A new profile starts with one slot and
## nothing caught; every gain adds its catches, with ids that are never reused, and its materials,
## and is on disk at once; the profile survives saving and loading; a save it can't trust is
## refused; and a damaged save falls back to the newest intact generation before it (#179).

const SAVE_PATH: String = "user://test_profile.json"


func run(_tree: SceneTree) -> String:
	var profile: Profile = Profile.new()
	if profile.unlocked_slots != 1 or not profile.captured_monsters.is_empty():
		return "a new profile doesn't start with one slot and nothing caught"
	var applied: String = profile.apply(_result(["ember_fox", "moss_toad"], { "crystal": 2 }))
	applied += profile.apply(_result(["ember_fox"], { "crystal": 1, "feather": 3 }))
	if not applied.is_empty():
		return "a valid gain was refused: " + applied
	var ids: Array[int] = []
	for monster: CapturedMonster in profile.captured_monsters:
		ids.append(monster.id)
	var expected: Array[int] = [1, 2, 3]
	var expected_materials: Dictionary[String, int] = { "crystal": 3, "feather": 3 }
	if ids != expected or profile.materials != expected_materials:
		return "two gains gave monsters %s and materials %s" % [ids, profile.materials]
	var result: String = _check_kept_at_once()
	if result.is_empty():
		result = _check_bad_results(profile)
	if result.is_empty():
		result = _check_save(profile)
	if result.is_empty():
		result = _check_refused()
	if result.is_empty():
		result = _check_recovered()
	SaveStore.remove(SAVE_PATH)
	return result


## Saving is debounced (owner, #73): the first catch after a quiet spell is on disk at once, a burst
## right after it is saved together once SAVE_INTERVAL_MSEC has passed, and ending a run flushes
## whatever is pending.
func _check_kept_at_once() -> String:
	var keeper: ProfileKeeper = ProfileKeeper.new(Profile.new(), SAVE_PATH)
	var problem: String = keeper.take(_result(["moss_toad"], {}), 0)
	if not problem.is_empty() or _monsters_on_disk() != 1:
		return "the first catch wasn't on disk right away: " + problem
	for ms: int in range(100, 5000, 100):
		problem += keeper.take(_result(["moss_toad"], {}), ms)
	var interval: int = ProfileKeeper.SAVE_INTERVAL_MSEC
	problem += keeper.save_if_due(interval - 1)
	if not problem.is_empty() or _monsters_on_disk() != 1:
		return "a burst of catches was saved before the interval passed: " + problem
	problem = keeper.save_if_due(interval)
	if not problem.is_empty() or _monsters_on_disk() != 50:
		return "the burst wasn't saved once the interval passed: " + problem
	problem = keeper.take(_result(["moss_toad"], {}), interval + 1) + keeper.finish_run()
	var on_disk: Profile = SaveStore.load_profile(SAVE_PATH)
	SaveStore.remove(SAVE_PATH)
	if (not problem.is_empty()
			or on_disk.runs_finished != 1
			or on_disk.captured_monsters.size() != 51):
		return "finishing the run didn't flush the pending catch: " + problem
	return ""


func _monsters_on_disk() -> int:
	return SaveStore.load_profile(SAVE_PATH).captured_monsters.size()


## A gain the profile couldn't save is refused whole, and the profile stays as it was.
func _check_bad_results(profile: Profile) -> String:
	var before: String = profile.to_text()
	var bad: Array[Gain] = [
		_result(["ember_fox", ""], {}),
		_result([], { "crystal": -1 }),
		_result([], { "": 1 }),
		_result([], { "crystal": Profile.MAX_NUMBER }),
	]
	for result: Gain in bad:
		if profile.apply(result).is_empty():
			return "a bad gain was taken over: %s %s" % [
				result.caught_species,
				result.materials,
			]
	if profile.to_text() != before:
		return "a refused gain still changed the profile"
	return ""


## Saving and loading gives back the same profile, with the next id still unused.
func _check_save(profile: Profile) -> String:
	var problem: String = SaveStore.save_profile(profile, SAVE_PATH)
	if not problem.is_empty():
		return problem
	var loaded: Profile = SaveStore.load_profile(SAVE_PATH)
	SaveStore.remove(SAVE_PATH)
	if not loaded.problem.is_empty() or loaded.to_text() != profile.to_text():
		return "the loaded profile differs from the saved one: " + loaded.problem
	if FileAccess.file_exists(SAVE_PATH + ".tmp"):
		return "saving left its temporary file behind"
	var _caught: String = loaded.apply(_result(["moss_toad"], {}))
	if loaded.captured_monsters.back().id != 4:
		return "a monster caught after loading reused an id"
	if not SaveStore.load_profile(SAVE_PATH).captured_monsters.is_empty():
		return "without a save, the game didn't start a new profile"
	return ""


## A save that isn't one, comes from a newer build, or contradicts itself is refused, not misread.
func _check_refused() -> String:
	var text: String = Profile.new().to_text()
	var cases: Dictionary[String, String] = {
		"not json": "not a profile save",
		text.replace("\"format\": 1", "\"format\": 99"): "save format 99",
		text.replace("\"unlocked_slots\": 1", "\"unlocked_slots\": 7"): "the save's slots",
		text.replace(
			"\"captured_monsters\": []",
			"\"captured_monsters\": [{\"id\": 5}]",
		): "a captured",
		text.replace("\"unlocked_slots\": 1", "\"unlocked_slots\": 1.5"): "the save's slots",
		text.replace("\"next_monster_id\": 1", "\"next_monster_id\": 0"): "the save's slots",
	}
	for case: String in cases:
		var problem: String = Profile.parse(case).problem
		if not problem.begins_with(cases[case]):
			return "expected a refusal starting %s, got: %s" % [cases[case], problem]
	return ""


func _result(species: Array, materials: Dictionary) -> Gain:
	var result: Gain = Gain.new()
	result.caught_species.assign(species)
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
		if loaded.to_text() != older.to_text():
			return "the fallback isn't the save before the damaged one"
	for file: String in [SAVE_PATH, SAVE_PATH + ".1"]:
		_write(file, "{}")
	if SaveStore.load_profile(SAVE_PATH).problem.is_empty():
		return "a save with every generation damaged was read"
	SaveStore.remove(SAVE_PATH)
	_write(SAVE_PATH, newer.to_text())
	if SaveStore.load_profile(SAVE_PATH).to_text() != newer.to_text():
		return "a plain save from before checksums didn't load"
	return ""


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var _stored: bool = file.store_string(text)
	file.close()
