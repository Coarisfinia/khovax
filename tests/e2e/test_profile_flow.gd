extends RefCounted
## Profile flow (#37): the player's profile across runs. A new profile starts with one slot and
## nothing caught; a finished run's result adds its catches, with ids that are never reused, and its
## materials; the profile survives saving and loading; and a save it can't trust is refused.

const SAVE_PATH: String = "user://test_profile.json"


func run(_tree: SceneTree) -> String:
	var profile: Profile = Profile.new()
	if profile.unlocked_slots != 1 or not profile.captured_monsters.is_empty():
		return "a new profile doesn't start with one slot and nothing caught"
	var applied: String = profile.apply(_result(["ember_fox", "moss_toad"], { "crystal": 2 }))
	applied += profile.apply(_result(["ember_fox"], { "crystal": 1, "feather": 3 }))
	if not applied.is_empty():
		return "a valid run result was refused: " + applied
	var ids: Array[int] = []
	for monster: CapturedMonster in profile.captured_monsters:
		ids.append(monster.id)
	var expected: Array[int] = [1, 2, 3]
	var expected_materials: Dictionary[String, int] = { "crystal": 3, "feather": 3 }
	if ids != expected or profile.materials != expected_materials:
		return "two runs gave monsters %s and materials %s" % [ids, profile.materials]
	if profile.runs_finished != 2:
		return "the profile counted %d finished runs, not 2" % profile.runs_finished
	var result: String = _check_bad_results(profile)
	if result.is_empty():
		result = _check_save(profile)
	if result.is_empty():
		result = _check_refused()
	return result


## A run result the profile couldn't save is refused whole, and the profile stays as it was.
func _check_bad_results(profile: Profile) -> String:
	var before: String = profile.to_text()
	var bad: Array[RunResult] = [
		_result(["ember_fox", ""], {}),
		_result([], { "crystal": -1 }),
		_result([], { "": 1 }),
		_result([], { "crystal": Profile.MAX_NUMBER }),
	]
	for result: RunResult in bad:
		if profile.apply(result).is_empty():
			return "a bad run result was taken over: %s %s" % [
				result.caught_species,
				result.materials,
			]
	if profile.to_text() != before:
		return "a refused run result still changed the profile"
	return ""


## Saving and loading gives back the same profile, with the next id still unused.
func _check_save(profile: Profile) -> String:
	var problem: String = SaveStore.save_profile(profile, SAVE_PATH)
	if not problem.is_empty():
		return problem
	var loaded: Profile = SaveStore.load_profile(SAVE_PATH)
	var _removed: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
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


func _result(species: Array, materials: Dictionary) -> RunResult:
	var result: RunResult = RunResult.new()
	result.caught_species.assign(species)
	result.materials.assign(materials)
	return result
