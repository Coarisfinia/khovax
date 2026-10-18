extends RefCounted
## Profile flow (#37): the player's profile across sessions. A new profile starts with one slot and
## nothing dominated; every gain adds its dominations, with ids that are never reused, and its
## materials, and is on disk at once; the profile survives saving and loading; a save it can't trust
## is refused; an older save is migrated, oldest step first, into the current format with no quest
## progress (#184); the first three monsters dominated are carried (#53); the standing with each
## faction stays on its scale and is saved (#483); and a damaged save falls back to the newest
## intact generation before it (#179).

const SAVE_PATH: String = "user://test_profile.json"
## The keys a newer save format added (#184, #53, #391, #399, #483), which older saves lack.
const ADDED_KEYS: Array[String] = [
	"quest_progress",
	"quests_done",
	"carried",
	"personal_color",
	"character_name",
	"standings",
]


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
	var color: String = "\"personal_color\": -1"
	var nameless: String = "\"character_name\": \"\""
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
		text.replace(color, "\"personal_color\": -2"): "the save's personal color",
		text.replace(color, "\"personal_color\": 16777216"): "the save's personal color",
		text.replace(color, "\"personal_color\": 1.5"): "the save's personal color",
		text.replace(color, "\"personal_color\": \"red\""): "the save's personal color",
		text.replace(nameless, "\"character_name\": \"   \""): "the save's character name",
		text.replace(nameless, "\"character_name\": 123"): "the save's character name",
		text.replace(nameless, "\"character_name\": \"%s\"" % "x".repeat(Profile.NAME_LIMIT + 1)): (
			"the save's character name"
		),
	}
	var problem: String = _unrefused(cases)
	return problem if not problem.is_empty() else _check_named()


## Why one of the saves in `cases` wasn't refused with the reason it maps to, or "".
func _unrefused(cases: Dictionary[String, String]) -> String:
	for case: String in cases:
		var problem: String = ProfileSave.parse(case).problem
		if not problem.begins_with(cases[case]):
			return "expected a refusal starting %s, got: %s" % [cases[case], problem]
	return ""


## Might (#508): the carried monsters' part sums each one's HP, twice its strength and its speed,
## times its level; a monster that isn't carried, or of a species the data lacks, adds nothing.
func _check_might() -> String:
	var species: Dictionary[String, Species] = SpeciesContent.load_species().species
	var profile: Profile = Profile.new()
	var gain: Gain = Gain.new()
	gain.dominated_species.assign(["moss_toad", "storm_finch", "moss_toad", "storm_finch"])
	var _taken: String = profile.apply(gain)
	var toad: Species = species["moss_toad"]
	var finch: Species = species["storm_finch"]
	var each_toad: int = toad.hp + Might.STRENGTH_WEIGHT * toad.strength + toad.speed
	var each_finch: int = finch.hp + Might.STRENGTH_WEIGHT * finch.strength + finch.speed
	# The first three are carried: two toads and a finch; the second finch rests.
	if Might.of(profile, species) != 2 * each_toad + each_finch:
		return "Might isn't the carried monsters' stats: %d" % Might.of(profile, species)
	profile.dominated_monsters[0].level = 3
	if Might.of(profile, species) != 4 * each_toad + each_finch:
		return "a carried monster's level doesn't multiply its part of Might"
	profile.dominated_monsters[0].species = "nobody_knows"
	if Might.of(profile, species) != each_toad + each_finch:
		return "a monster of an unknown species adds to Might"
	return ""


## Naming the character (#399): a name with its spaces at either end dropped is kept and saved; an
## empty one or one too long is refused with a reason in words, leaving the name as it was.
func _check_named() -> String:
	var keeper: ProfileKeeper = ProfileKeeper.new(Profile.new(), SAVE_PATH)
	var kept: String = keeper.choose_name("  Ash  ", 0)
	var _flushed: String = keeper.flush()
	var saved: Profile = SaveStore.load_profile(SAVE_PATH)
	if not kept.is_empty() or saved.character_name != "Ash":
		return "the name Ash wasn't kept and saved: %s, %s" % [kept, saved.character_name]
	var empty: String = keeper.choose_name("   ", 0)
	var long: String = keeper.choose_name("x".repeat(Profile.NAME_LIMIT + 1), 0)
	if empty.is_empty() or long.is_empty() or keeper.profile.character_name != "Ash":
		return "an empty or too long name wasn't refused, or changed the name"
	var problem: String = _check_might()
	return problem if not problem.is_empty() else _check_standings()


## Standing with a faction (#483): neutral until something moves it, held between the lowest and
## the highest standing however far it's pushed, neutral again on coming back to 0, and kept
## through saving and loading; a faction without a valid id is refused and changes nothing.
func _check_standings() -> String:
	var profile: Profile = Profile.new()
	var standings: Standings = profile.standings
	var guild: String = "cartographers_guild"
	if standings.of(guild) != 0:
		return "a new profile isn't neutral with a faction"
	var changed: String = standings.change(guild, 3) + standings.change(guild, 4)
	changed += standings.change("rivals", -2) + standings.change("rivals", -(1 << 62))
	if not changed.is_empty() or standings.of(guild) != Standings.HIGHEST:
		return "pushing a standing past the top didn't stay at the top: %s" % changed
	if standings.of("rivals") != Standings.LOWEST:
		return "pushing a standing past the bottom didn't stay at the bottom"
	changed = standings.change("rivals", -Standings.LOWEST)
	if not changed.is_empty() or standings.by_faction.has("rivals"):
		return "a standing back at 0 isn't neutral again"
	changed = standings.change("rivals", -1)
	if not changed.is_empty() or standings.change("Bad id", 1).is_empty():
		return "a faction without a valid id was taken, or a valid one refused: %s" % changed
	if standings.by_faction.has("Bad id"):
		return "a faction without a valid id still got a standing"
	var loaded: Profile = ProfileSave.parse(ProfileSave.to_text(profile))
	var expected: Dictionary[String, int] = { "rivals": -1, guild: Standings.HIGHEST }
	if not loaded.problem.is_empty() or loaded.standings.by_faction != expected:
		return "the standings didn't survive saving: %s %s" % [
			loaded.problem,
			loaded.standings.by_faction,
		]
	return _check_standings_refused()


## A save with standings that aren't a dictionary, a faction without a valid id, or a standing that
## isn't a whole number off neutral on the scale is refused.
func _check_standings_refused() -> String:
	var text: String = ProfileSave.to_text(Profile.new())
	var neutral: String = "\"standings\": {}"
	var faction_a: String = "the standing with faction a"
	var cases: Dictionary[String, String] = {
		text.replace(neutral, "\"standings\": []"): "the save lacks its standings",
		text.replace(neutral, "\"standings\": {\"Bad id\": 1}"): "the standing with faction Bad",
		text.replace(neutral, "\"standings\": {\"a\": 0}"): faction_a,
		text.replace(neutral, "\"standings\": {\"a\": 6}"): faction_a,
		text.replace(neutral, "\"standings\": {\"a\": -6}"): faction_a,
		text.replace(neutral, "\"standings\": {\"a\": 1.5}"): faction_a,
		text.replace(neutral, "\"standings\": {\"a\": \"1\"}"): faction_a,
	}
	return _unrefused(cases)


## Older saves load into the current format, migrated oldest step first: format 1 still counted
## finished runs (#197), formats before 3 had no quest progress (#184), which starts empty, and
## formats before 4 carried no monsters (#53): the first three dominated are carried then, and
## formats before 5 named them captured (#317); formats before 6 had no personal color (#391), which
## starts on Auto; formats before 7 had no character name (#399), which starts empty; and formats
## before 8 had no standings with factions (#483), which start neutral.
func _check_migrated() -> String:
	var text: String = ProfileSave.to_text(Profile.new())
	var current: Dictionary = _as_captured(text)
	# What older formats lacked.
	for key: String in ADDED_KEYS:
		var _dropped: bool = current.erase(key)
	# Format 1 with its run count and without it, and format 2 with a stale run count and without.
	var olds: Array[Dictionary] = [
		{ "format": 1, "runs_finished": 3 },
		{ "format": 1 },
		{ "format": 2, "runs_finished": 3 },
		{ "format": 2 },
		{ "format": 3, "quest_progress": {}, "quests_done": [] },
		{ "format": 4, "quest_progress": {}, "quests_done": [], "carried": [] },
		{
			"format": 5,
			"quest_progress": {},
			"quests_done": [],
			"carried": [],
			"dominated_monsters": [],
		},
		{
			"format": 6,
			"quest_progress": {},
			"quests_done": [],
			"carried": [],
			"dominated_monsters": [],
			"personal_color": Profile.AUTO_COLOR,
		},
		{
			"format": 7,
			"quest_progress": {},
			"quests_done": [],
			"carried": [],
			"dominated_monsters": [],
			"personal_color": Profile.AUTO_COLOR,
			"character_name": "",
		},
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
