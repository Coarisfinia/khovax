extends RefCounted
## Profile flow (#37): the player's profile across sessions. A new profile starts with one slot and
## nothing dominated; every gain adds its dominations, keyed on their short ids (#754), and its
## materials, and is on disk at once; the profile survives saving and loading; a save it can't trust
## is refused; an older save is migrated, oldest step first, into the current format with no quest
## progress (#184), and an open quest's earlier steps done (#573); the first three monsters
## dominated are carried (#53); the standing with each faction stays on its scale and is saved
## (#483); gear goes into a slot only while the player owns it, and is saved (#690); the leaning
## toward the story's paths counts the path-marked choices and is saved (#658); every dominated
## monster keeps its short id (#700) and grows in levels from the dominations it's carried through
## (#1251), each letting it take a node of its development web (#1417); the outbox's requests to the
## world are saved until the world
## acknowledges them (#771); and a damaged save falls back to the newest intact generation
## before it (#179).

const SAVE_PATH: String = "user://test_profile.json"
## The keys a newer save format added (#184, #53, #391, #399, #483, #658, #771, #1298, #1333), which
## older saves lack.
const ADDED_KEYS: Array[String] = [
	"quest_progress",
	"quests_done",
	"quests_started",
	"quest_focus",
	"carried",
	"personal_color",
	"character_name",
	"standings",
	"standings_half_lost",
	"postgame",
	"gear",
	"equipped",
	"path_leaning",
	"outbox",
]
## A save's quest progress for quest a with the steps done (#573) left open.
const PROGRESS_DONE: String = (
	"\"quest_progress\": {\"a\": {\"step\": 0, \"count\": 0, \"done\": %s}}"
)

## The quests the last `_parse` read, as the game's QuestKeeper keeps them beside the profile
## (#855).
var _parsed_quests: QuestTracker = null


func run(_tree: SceneTree) -> String:
	var profile: Profile = Profile.new()
	if profile.unlocked_slots != 1 or not profile.dominated_monsters.is_empty():
		return "a new profile doesn't start with one slot and nothing dominated"
	var applied: String = profile.apply(_result(["ember_fox", "ombulumo"], { "crystal": 2 }))
	applied += profile.apply(_result(["ember_fox"], { "crystal": 1, "feather": 3 }))
	if not applied.is_empty():
		return "a valid gain was refused: " + applied
	var ids: Array[String] = []
	for monster: DominatedMonster in profile.dominated_monsters:
		ids.append(monster.short_id)
	var expected: Array[String] = [ShortId.stand_in(1), ShortId.stand_in(2), ShortId.stand_in(3)]
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
## burst right after it is saved together once SAVE_INTERVAL_MSEC has passed, and the game going to
## the background flushes whatever is pending, through the holder's notification as the game does.
func _check_kept_at_once() -> String:
	var keeper: ProfileKeeper = ProfileKeeper.new(Profile.new(), SAVE_PATH)
	var problem: String = keeper.take(_result(["ombulumo"], {}), 0)
	if not problem.is_empty() or _monsters_on_disk() != 1:
		return "the first domination wasn't on disk right away: " + problem
	for ms: int in range(100, 5000, 100):
		problem += keeper.take(_result(["ombulumo"], {}), ms)
	var interval: int = ProfileKeeper.SAVE_INTERVAL_MSEC
	problem += keeper.save_if_due(interval - 1)
	if not problem.is_empty() or _monsters_on_disk() != 1:
		return "a burst of dominations was saved before the interval passed: " + problem
	problem = keeper.save_if_due(interval)
	if not problem.is_empty() or _monsters_on_disk() != 50:
		return "the burst wasn't saved once the interval passed: " + problem
	problem = keeper.take(_result(["ombulumo"], {}), interval + 1)
	var holder: ProfileHolder = ProfileHolder.new()
	holder.keeper = keeper
	holder.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	holder.free()
	var on_disk: Profile = ProfileStore.load_from(SAVE_PATH)
	SaveStore.remove(SAVE_PATH)
	if not problem.is_empty() or on_disk.dominated_monsters.size() != 51:
		return "going to the background didn't flush the pending domination: " + problem
	return ""


func _monsters_on_disk() -> int:
	return ProfileStore.load_from(SAVE_PATH).dominated_monsters.size()


## A gain the profile couldn't save is refused whole, and the profile stays as it was.
func _check_bad_results(profile: Profile) -> String:
	var before: String = _text(profile)
	var bad_id: Gain = _result(["ombulumo"], {})
	bad_id.dominated_short_ids.assign(["l1o0ij-"])
	var bad: Array[Gain] = [
		bad_id,
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
	if _text(profile) != before:
		return "a refused gain still changed the profile"
	return ""


## Saving and loading gives back the same profile, and a monster dominated after it gets a short id
## no other has; then the short ids (#700).
func _check_save(profile: Profile) -> String:
	var problem: String = ProfileStore.save(profile, SAVE_PATH)
	if not problem.is_empty():
		return problem
	var loaded: Profile = ProfileStore.load_from(SAVE_PATH)
	SaveStore.remove(SAVE_PATH)
	if not loaded.problem.is_empty() or _text(loaded) != _text(profile):
		return "the loaded profile differs from the saved one: " + loaded.problem
	if FileAccess.file_exists(SAVE_PATH + ".tmp"):
		return "saving left its temporary file behind"
	var _dominated: String = loaded.apply(_result(["ombulumo"], {}))
	var three: Array[String] = profile.carried.duplicate()
	if loaded.dominated_monsters.back().short_id != ShortId.stand_in(4) or loaded.carried != three:
		return "a monster dominated after loading reused a short id or joined the carried three"
	if not ProfileStore.load_from(SAVE_PATH).dominated_monsters.is_empty():
		return "without a save, the game didn't start a new profile"
	return _check_short_ids()


## A dominated monster keeps the short id it had in the wild (#700) through saving and loading, and
## one dominated without one gets the stand-in for its place. A save from before short ids (format
## 11)
## gives each the stand-in for its id, and a save with a short id that isn't one is refused.
func _check_short_ids() -> String:
	var profile: Profile = Profile.new()
	var gain: Gain = _result(["ombulumo", "ombulumo"], {})
	gain.dominated_short_ids.assign(["abc2345"])
	var _taken: String = profile.apply(gain)
	var loaded: Profile = _parse(_text(profile))
	var kept: Array[String] = []
	for monster: DominatedMonster in loaded.dominated_monsters:
		kept.append(monster.short_id)
	var expected: Array[String] = ["abc2345", ShortId.stand_in(2)]
	if not loaded.problem.is_empty() or kept != expected:
		return "the dominated monsters' short ids weren't kept: %s %s" % [kept, loaded.problem]
	return _check_short_ids_read(profile)


## `profile`'s save from before short ids (format 11) gives each monster the stand-in for its id,
## and one with a short id that isn't one is refused.
func _check_short_ids_read(profile: Profile) -> String:
	var data: Dictionary = _numbered(profile, 11)
	var monsters: Array = data["dominated_monsters"]
	for entry: Dictionary in monsters:
		var _dropped: bool = entry.erase("short_id")
	var migrated: Profile = _parse(JSON.stringify(data))
	if migrated.problem != "" or migrated.dominated_monsters[0].short_id != ShortId.stand_in(1):
		return "a format 11 save's monsters didn't get stand-in short ids: " + migrated.problem
	var bad: String = _text(profile).replace("abc2345", "abl2345")
	if not _parse(bad).problem.begins_with("a dominated monster"):
		return "a save with a short id that isn't one wasn't refused"
	return _check_short_id_keys()


## The profile keys its monsters on their short ids (#754): a gain bringing one it already holds, or
## the same one twice, gets a fresh stand-in, and a save holding one twice is refused. A save from
## before (format 19) numbered them and named the carried ones by their numbers, which load as
## their short ids, in the player's order; a carried number no monster has, or a number held twice
## or from the next one up, is refused.
func _check_short_id_keys() -> String:
	var profile: Profile = Profile.new()
	var gain: Gain = _result(["ombulumo", "tikazzir", "ombulumo", "tikazzir"], {})
	gain.dominated_short_ids.assign(["abc2345", "abc2345", "xyz6789"])
	var _taken: String = profile.apply(gain)
	var kept: Array[String] = []
	for monster: DominatedMonster in profile.dominated_monsters:
		kept.append(monster.short_id)
	var expected: Array[String] = ["abc2345", ShortId.stand_in(2), "xyz6789", ShortId.stand_in(4)]
	if kept != expected:
		return "a gain's short id already held didn't get a fresh stand-in: %s" % [kept]
	var _moved: String = profile.move_monster("xyz6789", 0)
	var migrated: Profile = _parse(JSON.stringify(_numbered(profile, 19)))
	if not migrated.problem.is_empty() or _text(migrated) != _text(profile):
		return "a format 19 save didn't load keyed on its short ids: " + migrated.problem
	return _check_short_id_keys_refused(profile)


## `profile`'s save holding a short id twice, or from format 19 with a carried number no monster
## has or a number held twice or from the next one up, is refused (#754).
func _check_short_id_keys_refused(profile: Profile) -> String:
	var stray: Dictionary = _numbered(profile, 19)
	stray["carried"] = [1, 9]
	var twice: String = _text(profile).replace(ShortId.stand_in(2), "abc2345")
	var renumbered: Dictionary = _numbered(profile, 19)
	renumbered["dominated_monsters"][1]["id"] = 1
	var beyond: Dictionary = _numbered(profile, 19)
	beyond["next_monster_id"] = 4
	var problem: String = _unrefused({
		JSON.stringify(stray): "a carried monster isn't",
		JSON.stringify(renumbered): "a dominated monster",
		JSON.stringify(beyond): "a dominated monster",
		twice: "a dominated monster",
	})
	return problem if not problem.is_empty() else _check_old_species_ids()


## A save from before a species' id was its name (format 13, #763) names its monsters and quests by
## the old ids, which load renamed: a quest under way, and a finished one.
func _check_old_species_ids() -> String:
	var profile: Profile = Profile.new()
	var _taken: String = profile.apply(_result(["ombulumo", "tikazzir"], {}))
	var quests: QuestTracker = QuestTracker.new()
	quests.progress["three_ombulumo"] = QuestProgress.new(0, 1)
	var migrated: Profile = _parse(_format_13(profile, quests))
	var species: Array[String] = []
	for monster: DominatedMonster in migrated.dominated_monsters:
		species.append(monster.species)
	var expected: Array[String] = ["ombulumo", "tikazzir"]
	if (not migrated.problem.is_empty()
			or species != expected
			or not _parsed_quests.progress.has("three_ombulumo")):
		return "a format 13 save's old species ids weren't renamed: %s %s" % [
			species,
			migrated.problem,
		]
	quests.progress.clear()
	quests.finished.append("three_ombulumo")
	var finished: Profile = _parse(_format_13(profile, quests))
	if not finished.problem.is_empty() or _parsed_quests.finished != ["three_ombulumo"]:
		return "a format 13 save's finished quest wasn't renamed: " + finished.problem
	return _check_old_faction_ids()


## A save from before a faction's id was its name (format 14, #976) names the faction by its old
## id, in its standings and in a territory hand-over still in its outbox, which load renamed.
func _check_old_faction_ids() -> String:
	var old_id: String = "cartographers_guild"
	var new_id: String = "amvrel_velmarai"
	var profile: Profile = Profile.new()
	var _raised: String = profile.standings.change(new_id, 2)
	# The forest's hand-over by its id then: format 16 recodes it to its Land-speech id (#975).
	var new_code: int = Territory.code(FlowSteps.FOREST, new_id)
	var then_code: int = Territory.code("forest", new_id)
	var _posted: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, then_code)
	var text: String = _in_format(_text(profile), 14)
	text = text.replace(
		new_id,
		old_id,
	).replace(str(then_code), str(Territory.code("forest", old_id)))
	var migrated: Profile = _parse(text)
	var expected: Dictionary[String, int] = { new_id: 2 }
	if (not migrated.problem.is_empty()
			or migrated.standings.by_faction != expected
			or migrated.outbox.entries.size() != 1
			or migrated.outbox.entries[0].data != new_code):
		return "a format 14 save's old faction id wasn't renamed: %s %s" % [
			migrated.standings.by_faction,
			migrated.problem,
		]
	return _check_old_instance_ids()


## A save from before the instances' Land-speech ids (format 15, #975) names its quests and the
## territory it hands over in its outbox by the old ids, which load renamed.
func _check_old_instance_ids() -> String:
	var profile: Profile = Profile.new()
	var faction: String = "amvrel_velmarai"
	var _posted: OutboxEntry = profile.outbox.post(
		OutboxEntry.TERRITORY,
		Territory.code(FlowSteps.FOREST, faction),
	)
	var quests: QuestTracker = QuestTracker.new()
	quests.progress["guild_charts_morwe_wudhen"] = QuestProgress.new(1, 0)
	quests.finished.append("lumwen_hoal_fork")
	var text: String = _in_format(_text(profile, quests), 15)
	text = text.replace("guild_charts_morwe_wudhen", "guild_charts_the_forest")
	text = text.replace("lumwen_hoal_fork", "glade_fork")
	text = text.replace(
		str(Territory.code(FlowSteps.FOREST, faction)),
		str(Territory.code("forest", faction)),
	)
	var migrated: Profile = _parse(text)
	var entries: Array[OutboxEntry] = migrated.outbox.entries
	var handed: int = entries[0].data if not entries.is_empty() else 0
	if (not migrated.problem.is_empty()
			or handed != Territory.code(FlowSteps.FOREST, faction)
			or not _parsed_quests.progress.has("guild_charts_morwe_wudhen")
			or _parsed_quests.finished != ["lumwen_hoal_fork"]):
		return "a format 15 save's old instance ids weren't renamed: " + migrated.problem
	return ""


## The save `text` in the numbered format `format`, from before format changes had names (#801).
static func _in_format(text: String, format: int) -> String:
	var data: Dictionary = JsonNumbers.wholes(JSON.parse_string(text))
	var _unnamed: bool = data.erase(FormatChanges.KEY)
	data["format"] = format
	return JSON.stringify(data)


## `profile`'s save with `quests` as format 13 wrote it, with the species and quest ids from before
## #763.
func _format_13(profile: Profile, quests: QuestTracker) -> String:
	var text: String = JSON.stringify(_numbered(profile, 13, quests))
	text = text.replace("three_ombulumo", "three_moss_toads")
	return text.replace("ombulumo", "moss_toad").replace("tikazzir", "storm_finch")


## A save that isn't one, comes from a newer build, or contradicts itself is refused, not misread.
func _check_refused() -> String:
	var text: String = _text(Profile.new())
	var done: String = "\"quests_done\": []"
	var progress: String = "\"quest_progress\": {}"
	var color: String = "\"personal_color\": -1"
	var nameless: String = "\"character_name\": \"\""
	var cases: Dictionary[String, String] = {

		"not json": "not a profile save",
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
		text.replace("\"quests_started\": []", "\"quests_started\": [\"a\"]"): "a quest started",
		text.replace("\"quest_focus\": \"\"", "\"quest_focus\": 7"): "the save lacks the quests",
		text.replace("\"quest_focus\": \"\"", "\"quest_focus\": \"Bad id\""): "the quest followed",
		text.replace("\"unlocked_slots\": 1", "\"unlocked_slots\": 7"): "the save's slots",
		text.replace(
			"\"dominated_monsters\": []",
			"\"dominated_monsters\": [{\"species\": \"ombulumo\"}]",
		): "a dominated",
		text.replace("\"unlocked_slots\": 1", "\"unlocked_slots\": 1.5"): "the save's slots",
		text.replace("\"carried\": []", "\"carried\": [5]"): "a carried monster isn't",
		text.replace("\"carried\": []", "\"carried\": [\"abc2345\"]"): "a carried monster isn't",
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
	return problem if not problem.is_empty() else _check_format_refused()


## A save in a format this build can't read is refused (#801): with a newer build's format change,
## with one listed twice, or numbered past the last numbered format.
func _check_format_refused() -> String:
	var text: String = _text(Profile.new())
	var changes: String = "\"%s\": [" % FormatChanges.KEY
	var first: String = ProfileSave.NUMBERED[0]
	var problem: String = _unrefused({
		text.replace(changes, changes + "\"9999-newer\", "): "save format: format change 9999",
		text.replace(changes, changes + "\"%s\", " % first): "save format: format change " + first,
		_in_format(text, ProfileSave.NUMBERED.size() + 2): "save format: format isn't",
	})
	return problem if not problem.is_empty() else _check_named()


## Why one of the saves in `cases` wasn't refused with the reason it maps to, or "".
func _unrefused(cases: Dictionary[String, String]) -> String:
	for case: String in cases:
		var problem: String = _parse(case).problem
		if not problem.begins_with(cases[case]):
			return "expected a refusal starting %s, got: %s" % [cases[case], problem]
	return ""


## Might (#508): the carried monsters' part sums each one's HP, twice its strength and its speed,
## times its level; a monster that isn't carried, or of a species the data lacks, adds nothing.
func _check_might() -> String:
	var species: Dictionary[String, Species] = SpeciesContent.load_species().species
	var profile: Profile = Profile.new()
	var gain: Gain = Gain.new()
	gain.dominated_species.assign(["ombulumo", "tikazzir", "ombulumo", "tikazzir"])
	var _taken: String = profile.apply(gain)
	var toad: Species = species["ombulumo"]
	var finch: Species = species["tikazzir"]
	var each_toad: int = toad.hp + Might.STRENGTH_WEIGHT * toad.strength + toad.speed
	var each_finch: int = finch.hp + Might.STRENGTH_WEIGHT * finch.strength + finch.speed
	# The first three are carried: two toads and a finch; the second finch rests. The first toad
	# was carried through three dominations, a level's worth (#1251).
	if Might.of(profile, species) != 3 * each_toad + each_finch:
		return "Might isn't the carried monsters' stats: %d" % Might.of(profile, species)
	profile.dominated_monsters[0].level = 3
	if Might.of(profile, species) != 4 * each_toad + each_finch:
		return "a carried monster's level doesn't multiply its part of Might"
	profile.dominated_monsters[0].species = "nobody_knows"
	if Might.of(profile, species) != each_toad + each_finch:
		return "a monster of an unknown species adds to Might"
	return ""


## Levels (#1251): each domination earns every monster carried then a point of progress, the
## dominated one none from its own; a level takes PROGRESS_PER_LEVEL times the level, and what is
## left over counts toward the next.
func _check_levels() -> String:
	var profile: Profile = Profile.new()
	var _first: String = profile.apply(_result(["ombulumo"], {}))
	var first: DominatedMonster = profile.dominated_monsters[0]
	if first.level != 1 or first.progress != 0:
		return "a monster earned progress from its own domination"
	var needed: int = DominatedMonster.progress_needed(1) + DominatedMonster.progress_needed(2)
	for _domination: int in needed + 1:
		var _taken: String = profile.apply(_result(["tikazzir"], {}))
	var levels: Array[int] = []
	for monster: DominatedMonster in profile.dominated_monsters.slice(0, 4):
		levels.append_array([monster.level, monster.progress])
	# The first earned 10, the second 9 and the third 8; the fourth rests.
	var expected: Array[int] = [3, 1, 3, 0, 2, 5, 1, 0]
	if levels != expected:
		return "levels and progress didn't follow the dominations carried through: %s" % [levels]
	var problem: String = _check_defeats(profile)
	return problem if not problem.is_empty() else _check_levels_saved(profile)


## Defeats (#1256): each wild monster the player's companion fells with its special earns every
## monster they carry PROGRESS_PER_DEFEAT, like a domination; a felling by another player's
## companion, or a strike that doesn't fell, is no defeat of theirs; a gain with a negative count is
## refused.
func _check_defeats(profile: Profile) -> String:
	var mine: SpecialStruck = SpecialStruck.new(1, 2, 7, true)
	mine.slot = 0
	var theirs: SpecialStruck = SpecialStruck.new(1, 2, 7, true)
	theirs.slot = 1
	var standing: SpecialStruck = SpecialStruck.new(1, 2, 7, false)
	standing.slot = 0
	var counted: Array[int] = [
		ProfileTie.defeats_in(mine, 0),
		ProfileTie.defeats_in(theirs, 0),
		ProfileTie.defeats_in(standing, 0),
	]
	if counted != ([1, 0, 0] as Array[int]):
		return "defeats were counted as %s, not only the player's own felling" % [counted]
	var gain: Gain = Gain.new()
	gain.defeats = 2
	# The third carried monster was at level 2 with 5 of 6: two defeats of a point each take it to
	# level 3 with 1.
	var third: DominatedMonster = profile.dominated_monsters[2]
	if not profile.apply(gain).is_empty() or third.level != 3 or third.progress != 1:
		return "two defeats gave the third monster level %d with %d" % [third.level, third.progress]
	gain.defeats = -1
	if profile.apply(gain).is_empty():
		return "a gain with a negative count of defeats was taken over"
	return ""


## `profile`'s levels and progress (#1251) are kept through saving and loading; a format 18 save
## starts every monster at none; and a save with progress its level can't hold is refused.
func _check_levels_saved(profile: Profile) -> String:
	var loaded: Profile = _parse(_text(profile))
	if not loaded.problem.is_empty() or _text(loaded) != _text(profile):
		return "levels and progress weren't kept through saving: " + loaded.problem
	var old: Dictionary = _numbered(profile, 18)
	for entry: Dictionary in old["dominated_monsters"]:
		var _dropped: bool = entry.erase("progress")
	var migrated: Profile = _parse(JSON.stringify(old))
	if not migrated.problem.is_empty() or migrated.dominated_monsters[0].progress != 0:
		return "a format 18 save's monsters didn't start without progress: " + migrated.problem
	var text: String = _text(Profile.new()).replace(
		"\"dominated_monsters\": []",
		"\"dominated_monsters\": [%s]",
	)
	var monster: String = "{\"species\": \"ombulumo\", \"short_id\": \"%s\", " % (
		ShortId.stand_in(1)
	)
	var held: Profile = _parse(text % (monster + "\"level\": 1, \"progress\": 2, \"taken\": []}"))
	if not held.problem.is_empty() or held.dominated_monsters[0].progress != 2:
		return "a save with progress its level holds was refused: " + held.problem
	return _unrefused({
		text % (monster + "\"level\": 1, \"progress\": 3}"): "a dominated",
		text % (monster + "\"level\": 2, \"progress\": -1}"): "a dominated",
	})


## Development (#1417): each level a dominated monster gained lets it take one node of its
## species' web, any one revealed (DevelopmentWeb.open_nodes) and not taken yet, never one still in
## fog, and the nodes it took are saved.
func _check_development() -> String:
	var profile: Profile = Profile.new()
	var _dominated: String = profile.apply(_result(["ombulumo"], {}))
	var monster: DominatedMonster = profile.dominated_monsters[0]
	var short_id: String = monster.short_id
	var refused: Array[String] = [profile.take_node(short_id, "sturdy_1")]
	monster.level = 3
	refused.append(profile.take_node(short_id, "sturdy_3"))
	refused.append(profile.take_node("zzzzzzz", "sturdy_1"))
	var took: String = profile.take_node(short_id, "sturdy_1")
	refused.append(profile.take_node(short_id, "sturdy_1"))
	took += profile.take_node(short_id, "sturdy_2")
	refused.append(profile.take_node(short_id, "heavy_1"))
	if not took.is_empty() or refused.has("") or monster.taken != ["sturdy_1", "sturdy_2"]:
		return "taking nodes gave %s, %s and refused %s" % [monster.taken, took, refused]
	var problem: String = _check_development_carried(_parse(_text(profile)))
	return problem if not problem.is_empty() else _check_development_saved(profile)


## The stat nodes `profile`'s first monster took (#1358), Ombulumo's sturdy_1 and sturdy_2 (+5% and
## +6% HP), ride to the world with its party: the run of carry requests says its leaning, summed
## from its web, and a monster without a web leans nowhere. An older save's carry requests, from
## before runs held leanings, are dropped; a leaning's code reads back every stat in its place, and
## a code with bits past them is none.
func _check_development_carried(profile: Profile) -> String:
	if not _leaning_codes_read_back():
		return "a leaning's code didn't read back as itself, or one too wide was read"
	var keeper: ProfileKeeper = ProfileKeeper.new(profile, SAVE_PATH)
	var problem: String = keeper.catch_up_party({}, 0, DevelopmentContent.cached().webs)
	var entries: Array[OutboxEntry] = profile.outbox.entries
	if not problem.is_empty() or entries.size() != CarryRequest.VALUES_PER_MONSTER:
		return "the monster's party wasn't sent as one monster's run: " + problem
	var value: int = CarryRequest.value_of(entries[2].data)
	var leaning: CompanionLeaning = CompanionLeaning.of_code(value)
	if leaning == null or not leaning.same_as(CompanionLeaning.of(110, 0, 0)):
		return "the run's leaning wasn't +11%% HP: %d" % value
	var old: Dictionary = JSON.parse_string(_text(profile))
	var changes: Array = old[FormatChanges.KEY]
	changes.erase("1358-carry-leanings")
	var migrated: Profile = _parse(JSON.stringify(old))
	if not migrated.problem.is_empty() or not migrated.outbox.entries.is_empty():
		return "an older save's carry requests weren't dropped: " + migrated.problem
	entries.clear()
	problem = keeper.catch_up_party({}, 0, {})
	value = CarryRequest.value_of(entries[2].data) if entries.size() > 2 else -1
	var none: CompanionLeaning = CompanionLeaning.of_code(value)
	if not problem.is_empty() or none == null or not none.is_none():
		return "a monster without its web leaned in its run: " + problem
	return ""


## `profile`'s first monster's nodes taken (#1417) are kept through saving and loading, start at
## none in a save from before them, and a save with more than its levels allow, one twice, or one
## that isn't an id, is refused.
func _check_development_saved(profile: Profile) -> String:
	var monster: DominatedMonster = profile.dominated_monsters[0]
	var loaded: Profile = _parse(_text(profile))
	if not loaded.problem.is_empty() or loaded.dominated_monsters[0].taken != monster.taken:
		return "the nodes taken weren't kept through saving: " + loaded.problem
	var old: Dictionary = JSON.parse_string(_text(profile))
	var changes: Array = old[FormatChanges.KEY]
	changes.erase("1417-development-taken")
	var entry: Dictionary = old["dominated_monsters"][0]
	var _dropped: bool = entry.erase("taken")
	var migrated: Profile = _parse(JSON.stringify(old))
	if not migrated.problem.is_empty() or not migrated.dominated_monsters[0].taken.is_empty():
		return "an older save's monster didn't start with no nodes taken: " + migrated.problem
	var text: String = _text(profile)
	var problem: String = _check_development_lost(_parse(text.replace("sturdy_2", "sturdy_99")))
	if not problem.is_empty():
		return problem
	return _unrefused({
		text.replace("\"level\": 3", "\"level\": 2"): "a dominated",
		text.replace("\"sturdy_2\"", "\"sturdy_1\""): "a dominated",
		text.replace("\"sturdy_2\"", "\"Bad id\""): "a dominated",
		text.replace("\"taken\": [", "\"taken\": 1, \"was\": ["): "a dominated",
	})


## A node a later web dropped (#1435), like `loaded`'s first monster's second, is loaded but gives
## its pick back as the keeper takes the webs over, and the next save holds it no longer; a web
## that isn't there drops nothing.
func _check_development_lost(loaded: Profile) -> String:
	var monster: DominatedMonster = loaded.dominated_monsters[0]
	var keeper: ProfileKeeper = ProfileKeeper.new(loaded, SAVE_PATH)
	keeper.drop_lost_nodes({})
	if not loaded.problem.is_empty() or monster.taken != ["sturdy_1", "sturdy_99"]:
		return "a node dropped from its web wasn't loaded, or went without its web: %s %s" % [
			loaded.problem,
			monster.taken,
		]
	keeper.drop_lost_nodes(DevelopmentContent.cached().webs)
	var problem: String = keeper.flush()
	var saved: Profile = ProfileStore.load_from(SAVE_PATH)
	if not problem.is_empty() or saved.dominated_monsters[0].taken != ["sturdy_1"]:
		return "a node dropped from its web kept its pick: %s %s" % [
			problem,
			saved.dominated_monsters[0].taken,
		]
	return "" if monster.picks_left() == 1 else "the dropped node's pick wasn't given back"


## Whether a leaning's code reads back every stat in its place, and a code with bits past them
## reads as none (#1358).
func _leaning_codes_read_back() -> bool:
	var least: int = CompanionLeaning.LEAST
	var wide: CompanionLeaning = CompanionLeaning.of(least, 7, CompanionLeaning.MOST)
	var read: CompanionLeaning = CompanionLeaning.of_code(wide.code())
	return read != null and read.same_as(wide) and CompanionLeaning.of_code(1 << 40) == null


## Naming the character (#399): a name with its spaces at either end dropped is kept and saved; an
## empty one or one too long is refused with a reason in words, leaving the name as it was.
func _check_named() -> String:
	var keeper: ProfileKeeper = ProfileKeeper.new(Profile.new(), SAVE_PATH)
	var kept: String = keeper.choose_name("  Ash  ", 0)
	var _flushed: String = keeper.flush()
	var saved: Profile = ProfileStore.load_from(SAVE_PATH)
	if not kept.is_empty() or saved.character_name != "Ash":
		return "the name Ash wasn't kept and saved: %s, %s" % [kept, saved.character_name]
	var empty: String = keeper.choose_name("   ", 0)
	var long: String = keeper.choose_name("x".repeat(Profile.NAME_LIMIT + 1), 0)
	if empty.is_empty() or long.is_empty() or keeper.profile.character_name != "Ash":
		return "an empty or too long name wasn't refused, or changed the name"
	var problem: String = _check_might()
	if problem.is_empty():
		problem = _check_levels()
	if problem.is_empty():
		problem = _check_development()
	return problem if not problem.is_empty() else _check_standings()


## Standing with a faction (#483): neutral until something moves it, held between the lowest and
## the highest standing however far it's pushed, neutral again on coming back to 0, and kept
## through saving and loading; a faction without a valid id is refused and changes nothing.
func _check_standings() -> String:
	var profile: Profile = Profile.new()
	var standings: Standings = profile.standings
	var guild: String = "amvrel_velmarai"
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
	var loaded: Profile = _parse(_text(profile))
	var expected: Dictionary[String, int] = { "rivals": -1, guild: Standings.HIGHEST }
	if not loaded.problem.is_empty() or loaded.standings.by_faction != expected:
		return "the standings didn't survive saving: %s %s" % [
			loaded.problem,
			loaded.standings.by_faction,
		]
	return _check_alignment()


## Alignment (#1310): gaining rank with a faction loses half that gain with each of its enemies, a
## half left over carried until a second makes a whole rank, kept through saving and loading;
## losing rank, or a gain past the top, costs its enemies nothing.
func _check_alignment() -> String:
	var profile: Profile = Profile.new()
	var standings: Standings = profile.standings
	var harmony: Faction = Faction.new()
	harmony.id = "harmony"
	harmony.enemies.assign(["supremacy"])
	standings.align(harmony, 1, false)
	var half: Array[String] = ["supremacy"]
	if standings.of("supremacy") != 0 or standings.half_lost != half:
		return "a gain of one didn't lose half a rank with the enemy: %s" % [standings.half_lost]
	standings.align(harmony, 1, false)
	if standings.of("supremacy") != -1 or not standings.half_lost.is_empty():
		return "two halves didn't make a whole rank lost with the enemy"
	standings.align(harmony, 3, false)
	if standings.of("supremacy") != -2 or standings.half_lost != half:
		return "a gain of three didn't lose one and a half ranks with the enemy"
	standings.align(harmony, -2, false)
	standings.align(harmony, 4, false)
	if standings.of(harmony.id) != Standings.HIGHEST or standings.of("supremacy") != -3:
		return "only the rank gained up to the top should cost the enemy: %s" % [
			standings.by_faction,
		]
	var loaded: Profile = _parse(_text(profile))
	if not loaded.problem.is_empty() or loaded.standings.half_lost != half:
		return "the half rank lost didn't survive saving: %s" % loaded.problem
	return _check_allied()


## A faction allied until the postgame (#1324) can be lowered below neutral before the player joins
## it, and once they have, never below its first rank, however far a change pushes it, until the
## player is in the postgame (#1333).
func _check_allied() -> String:
	var standings: Standings = Standings.new()
	var guild: Faction = Faction.new()
	guild.id = "guild"
	guild.allied_until_postgame = true
	standings.align(guild, -1, false)
	if standings.of(guild.id) != -1:
		return "a faction allied until the postgame, not joined, wasn't lowered"
	standings.align(guild, 4, false)
	standings.align(guild, -(1 << 62), false)
	if standings.of(guild.id) != 1:
		return "a joined faction allied until the postgame dropped below its first rank"
	standings.align(guild, -3, true)
	if standings.of(guild.id) != -2:
		return "in the postgame, a joined faction allied until it still held its first rank"
	return _check_postgame()


## Finishing the quest that ends the main story puts the player in the postgame (#1333), after its
## own standing moved, and the mark survives saving; finishing another quest doesn't set it. A save
## whose mark isn't true or false is refused.
func _check_postgame() -> String:
	var profile: Profile = Profile.new()
	var quest: QuestDefinition = QuestDefinition.new()
	QuestRewards.give(quest, profile)
	if profile.postgame:
		return "a quest that doesn't end the main story put the player in the postgame"
	quest.ends_story = true
	QuestRewards.give(quest, profile)
	var loaded: Profile = _parse(_text(profile))
	if not profile.postgame or not loaded.problem.is_empty() or not loaded.postgame:
		return "finishing the story's end didn't put the player in the postgame for good: " + (
			loaded.problem
		)
	var text: String = _text(Profile.new())
	var mark: String = "\"postgame\": false"
	var refused: String = "the save's postgame mark"
	var cases: Dictionary[String, String] = {
		text.replace(mark, "\"postgame\": 1"): refused,
		text.replace(mark, "\"postgame\": \"true\""): refused,
		text.replace(mark + ",", ""): refused,
	}
	var problem: String = _unrefused(cases)
	return problem if not problem.is_empty() else _check_starting_standing()


## A faction's starting standing (#1378): a new profile stands one rank below neutral with the Odun
## Kragothai, saving nothing for it; raised to neutral, the 0 is saved and loaded back; back at its
## start, nothing is saved again. A save holding a faction's start is refused.
func _check_starting_standing() -> String:
	var profile: Profile = Profile.new()
	var standings: Standings = profile.standings
	var odun: String = "odun_kragothai"
	if standings.of(odun) != -1 or standings.of("sorn_lumawenai") != -1 or standings.of("a") != 0:
		return "a new profile doesn't start one rank below neutral with Supremacy and Harmony"
	if not standings.by_faction.is_empty() or not standings.change(odun, 1).is_empty():
		return "a starting standing was kept as a change, or raising it was refused"
	var loaded: Profile = _parse(_text(profile))
	var raised: Dictionary[String, int] = { odun: 0 }
	if not loaded.problem.is_empty() or loaded.standings.by_faction != raised:
		return "a standing raised to neutral from its start didn't survive saving: %s %s" % [
			loaded.problem,
			loaded.standings.by_faction,
		]
	var _lowered: String = loaded.standings.change(odun, -1)
	if not loaded.standings.by_faction.is_empty() or loaded.standings.of(odun) != -1:
		return "a standing back at its start was still kept"
	var at_start: String = _text(Profile.new()).replace(
		"\"standings\": {}",
		"\"standings\": {\"%s\": -1}" % odun,
	)
	if not _parse(at_start).problem.begins_with("the standing with faction " + odun):
		return "a save holding a faction's starting standing wasn't refused"
	# A format 22 save could hold it; it loads at the start, as nothing kept.
	var old: Profile = _parse(_in_format(at_start, 22))
	if not old.problem.is_empty() or not old.standings.by_faction.is_empty():
		return "a format 22 save at a faction's starting standing didn't load: " + old.problem
	return _check_standings_refused()


## A save with standings that aren't a dictionary, a faction without a valid id, or a standing that
## isn't a whole number off neutral on the scale is refused.
func _check_standings_refused() -> String:
	var text: String = _text(Profile.new())
	var neutral: String = "\"standings\": {}"
	var faction_a: String = "the standing with faction a"
	var half_lost: String = "\"standings_half_lost\": []"
	var halves: String = "the save's half ranks lost"
	var cases: Dictionary[String, String] = {
		text.replace(neutral, "\"standings\": []"): "the save lacks its standings",
		text.replace(neutral, "\"standings\": {\"Bad id\": 1}"): "the standing with faction Bad",
		text.replace(neutral, "\"standings\": {\"a\": 0}"): faction_a,
		text.replace(neutral, "\"standings\": {\"a\": 6}"): faction_a,
		text.replace(neutral, "\"standings\": {\"a\": -6}"): faction_a,
		text.replace(neutral, "\"standings\": {\"a\": 1.5}"): faction_a,
		text.replace(neutral, "\"standings\": {\"a\": \"1\"}"): faction_a,
		text.replace(half_lost, "\"standings_half_lost\": {}"): halves,
		text.replace(half_lost, "\"standings_half_lost\": [\"Bad id\"]"): halves,
		text.replace(half_lost, "\"standings_half_lost\": [\"a\", \"a\"]"): halves,
	}
	var problem: String = _unrefused(cases)
	if problem.is_empty():
		problem = _check_gear()
	return problem if not problem.is_empty() else _check_leaning()


## Gear (#690): a slot takes only gear the player owns, one piece per slot, so a piece owned once
## can't be in two; emptied, it's free again. The gear and the slots survive saving, and a save with
## gear that isn't counted right, or in a slot that isn't one or that the player doesn't own, is
## refused.
func _check_gear() -> String:
	var profile: Profile = Profile.new()
	var gear: GearSlots = profile.gear
	gear.owned.assign({ "charm": 1 })
	var refused: String = gear.equip("ward", "spikes") + gear.equip("hat", "charm")
	var taken: String = gear.equip("ward", "charm")
	refused += gear.equip("trap", "charm")
	taken += gear.equip("ward", "") + gear.equip("trap", "charm")
	var expected: Dictionary[String, String] = { "trap": "charm" }
	if not taken.is_empty() or refused.is_empty() or gear.equipped != expected:
		return "gear went into the wrong slots: %s, %s" % [taken, gear.equipped]
	var loaded: Profile = _parse(_text(profile))
	if not loaded.problem.is_empty() or _text(loaded) != _text(profile):
		return "the gear didn't survive saving: " + loaded.problem
	var text: String = _text(Profile.new())
	var none: String = "\"gear\": {}"
	var empty: String = "\"equipped\": {}"
	var cases: Dictionary[String, String] = {
		text.replace(none, "\"gear\": []"): "the save lacks its gear",
		text.replace(none, "\"gear\": {\"a\": -1}"): "gear a has an invalid count",
		text.replace(none, "\"gear\": {\"a\": 0.5}"): "gear a has an invalid count",
		text.replace(empty, "\"equipped\": {\"ward\": \"a\"}"): "the gear in slot ward",
		text.replace(empty, "\"equipped\": {\"ward\": 7}"): "the gear in slot ward",
	}
	return _unrefused(cases)


## The leaning toward the story's paths (#658): even, toward neither, on a new profile; each
## path-marked choice leans one toward its path, toward both for a mark of both and toward neither
## for none; the path with more is the one leaned toward; it's kept through saving and loading, and
## a save whose leaning isn't a whole count for each path is refused.
func _check_leaning() -> String:
	var profile: Profile = Profile.new()
	if profile.leaning.toward() != PathMark.NONE:
		return "a new profile leans toward a path"
	for mark: String in [PathMark.BOTH, PathMark.HARMONY, PathMark.NONE, PathMark.HARMONY]:
		profile.leaning.lean(mark)
	if profile.leaning.harmony != 3 or profile.leaning.supremacy != 1:
		return "the choices leaned %d, %d" % [profile.leaning.harmony, profile.leaning.supremacy]
	var loaded: Profile = _parse(_text(profile))
	if not loaded.problem.is_empty() or loaded.leaning.toward() != PathMark.HARMONY:
		return "the leaning toward harmony didn't survive saving: " + loaded.problem
	var text: String = _text(Profile.new())
	var even: String = "\"supremacy\": 0"
	var invalid: String = "the save's path leaning"
	var cases: Dictionary[String, String] = {
		text.replace(even, "\"supremacy\": -1"): invalid,
		text.replace(even, "\"supremacy\": 0.5"): invalid,
		text.replace(even, "\"supremacy\": \"1\""): invalid,
		text.replace(even, "\"supremacy\": 0, \"strength\": 1"): invalid,
		text.replace(even, "\"supreme\": 0"): invalid,
	}
	var problem: String = _unrefused(cases)
	return problem if not problem.is_empty() else _check_outbox()


## The outbox (#771) keeps its requests, in the order posted, through saving and loading, each
## under a short id no other has (#791); a request the world acknowledged is dropped. A save whose
## outbox has a request twice, one whose id isn't a short id, of a kind there isn't or with no data,
## or that isn't a list, is refused.
func _check_outbox() -> String:
	var profile: Profile = Profile.new()
	var first: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, 41)
	var _second: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, 42)
	var dropped: bool = profile.outbox.drop(first.id) and not profile.outbox.drop(first.id)
	var _third: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, 43)
	var loaded: Profile = _parse(_text(profile))
	var kept: Array[int] = []
	var ids: Array[String] = []
	for entry: OutboxEntry in loaded.outbox.entries:
		kept.append(entry.data)
		ids.append(entry.id)
	var unique: bool = ids.size() == 2 and ids[0] != ids[1]
	var expected: Array[int] = [42, 43]
	if not dropped or not loaded.problem.is_empty() or kept != expected or not unique:
		return "the outbox didn't keep its requests: %s %s %s" % [kept, ids, loaded.problem]
	for id: String in ids:
		if not ShortId.is_valid(id) or ShortId.of_code(ShortId.code(id)) != id:
			return "the outbox's id %s isn't a short id a command can carry" % id
	return _check_outbox_refused(_text(profile), loaded.outbox.entries[0].to_data())


## A save `text` whose outbox has `request` twice, has it with an id that isn't a short id, of a
## kind there isn't or without its data, or whose outbox isn't a list, is refused.
func _check_outbox_refused(text: String, request: Dictionary) -> String:
	var cases: Dictionary[String, String] = {}
	for outbox: Variant in [
		[request, request],
		[request.merged({ "id": "abl2345" }, true)],
		[request.merged({ "id": 7 }, true)],
		[request.merged({ "kind": 9 }, true)],
		[{ "id": request["id"], "kind": OutboxEntry.TERRITORY }],
		{ "entries": [request] },
	]:
		var data: Dictionary = JSON.parse_string(text)
		data["outbox"] = outbox
		cases[JSON.stringify(data)] = "the save's outbox"
	return _unrefused(cases)


## Older saves load into the current format, migrated oldest step first: format 1 still counted
## finished runs (#197), formats before 3 had no quest progress (#184), which starts empty, and
## formats before 4 carried no monsters (#53): the first three dominated are carried then, and
## formats before 5 named them captured (#317); formats before 6 had no personal color (#391), which
## starts on Auto; formats before 7 had no character name (#399), which starts empty; formats
## before 8 had no standings with factions (#483), which start neutral; formats before 10 had no
## gear (#690): none is owned, and every gear slot starts empty; formats before 11 had no leaning
## toward the paths (#658), which starts even; formats before 13 had no outbox (#771), which
## starts empty; and formats before 24 had no postgame mark (#1333): no player is in it.
func _check_migrated() -> String:
	var text: String = _text(Profile.new())
	var current: Dictionary = _as_captured(text)
	# What older formats lacked.
	for key: String in ADDED_KEYS:
		var _dropped: bool = current.erase(key)
	for old: Dictionary in _old_saves():
		var save: Dictionary = current.duplicate()
		save.merge(old, true)
		var loaded: Profile = _parse(JSON.stringify(save))
		if not loaded.problem.is_empty() or _text(loaded) != text:
			return "an older save %s didn't load as the current one: %s" % [old, loaded.problem]
	var last: Profile = _parse(_in_format(text, ProfileSave.NUMBERED.size() + 1))
	if not last.problem.is_empty() or _text(last) != text:
		return "a save in the last numbered format didn't load as the current one: " + last.problem
	var problem: String = _check_change_names()
	if problem.is_empty():
		problem = _check_migrated_quest()
	return problem if not problem.is_empty() else _check_migrated_carried()


## Every format change the profile's migrations ask for by name (#801), its own and its
## companions', is a file in its folder, so a misspelt one can't migrate every save.
static func _check_change_names() -> String:
	var known: Array[String] = FormatChanges.names_in(ProfileSave.CHANGES)
	var asked: Array = ProfileSave.NUMBERED + [
		QuestSave.QUESTS,
		QuestSave.DOMINATED,
		QuestSave.STEPS_DONE,
		QuestSave.SPECIES_IDS,
		QuestSave.INSTANCE_IDS,
		QuestSave.FOCUS,
		BestiarySave.SINCE,
		CodexKeeper.SINCE,
		MoveHintKeeper.SINCE,
	]
	for change: Variant in asked:
		if not known.has(change):
			return "the profile's format change %s has no file" % [change]
	return ""


## What a save in each older format holds that the current one doesn't, or holds otherwise.
func _old_saves() -> Array[Dictionary]:
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
		{
			"format": 9,
			"quest_progress": {},
			"quests_done": [],
			"carried": [],
			"dominated_monsters": [],
			"personal_color": Profile.AUTO_COLOR,
			"character_name": "",
			"standings": {},
		},
	]
	# Format 10 is format 9's with the gear (#690).
	var ten: Dictionary = olds[-1].duplicate()
	ten.merge({ "format": 10, "gear": {}, "equipped": {} }, true)
	olds.append(ten)
	return olds


## A format 4 save's first quest, open or finished, is the renamed first quest (#317).
func _check_migrated_quest() -> String:
	var save: Dictionary = _as_captured(_text(Profile.new()))
	save["format"] = 4
	save["quest_progress"] = { "first_catch": { "step": 0, "count": 1 } }
	var open: Profile = _parse(JSON.stringify(save))
	var progress: QuestProgress = _parsed_quests.progress.get("first_domination")
	if not open.problem.is_empty() or progress == null or progress.count != 1:
		return "a format 4 save's open first quest wasn't renamed: %s" % open.problem
	save["quest_progress"] = {}
	save["quests_done"] = ["first_catch"]
	var done: Profile = _parse(JSON.stringify(save))
	var expected: Array[String] = ["first_domination"]
	if not done.problem.is_empty() or _parsed_quests.finished != expected:
		return "a format 4 save's finished first quest wasn't renamed: %s" % done.problem
	return _check_migrated_done()


## A format 8 save's quest progress, from before quests had choices (#573), has every step before
## the one it's on done, in order, and keeps them through saving. A current save's progress without
## its steps done, or with steps done that aren't a list of whole numbers from 0, is refused.
func _check_migrated_done() -> String:
	var text: String = _text(Profile.new())
	var progress: String = "\"quest_progress\": {}"
	var cases: Dictionary[String, String] = {
		text.replace(progress, PROGRESS_DONE.replace(", \"done\": %s", "")): "quest a's",
		text.replace(progress, PROGRESS_DONE % "7"): "quest a's",
		text.replace(progress, PROGRESS_DONE % "[-1]"): "quest a's",
		text.replace(progress, PROGRESS_DONE % "[0.5]"): "quest a's",
	}
	var refused: String = _unrefused(cases)
	if not refused.is_empty():
		return refused
	var data: Dictionary = JSON.parse_string(_in_format(_text(Profile.new()), 8))
	data["quest_progress"] = {
		"toads": { "step": 2, "count": 1 },
		"fresh": { "step": 0, "count": 0 },
	}
	var loaded: Profile = _parse(JSON.stringify(data))
	var loaded_quests: QuestTracker = _parsed_quests
	var two: Array[int] = [0, 1]
	var again: Profile = _parse(_text(loaded, loaded_quests))
	if (not loaded.problem.is_empty() or not again.problem.is_empty()
			or loaded_quests.progress["toads"].done != two
			or not loaded_quests.progress["fresh"].done.is_empty()
			or _parsed_quests.progress["toads"].done != two):
		return "a format 8 save's quest progress didn't get its steps done: %s" % loaded.problem
	return ""


## Current save `text` as data with its monsters under their name before format 5.
func _as_captured(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	data["captured_monsters"] = data["dominated_monsters"]
	var _renamed: bool = data.erase("dominated_monsters")
	var _unnamed: bool = data.erase(FormatChanges.KEY)
	return data


## A format 3 save with four monsters carries its first three; a format 4 save carrying one twice,
## or four, is refused.
func _check_migrated_carried() -> String:
	var profile: Profile = Profile.new()
	var four: Array = ["ember_fox", "ombulumo", "ember_fox", "ombulumo"]
	var _dominated: String = profile.apply(_result(four, {}))
	var save: Dictionary = _as_captured(JSON.stringify(_numbered(profile, 4)))
	for bad: Array in [[1, 1], [1, 2, 3, 4]]:
		var wrong: Dictionary = save.duplicate()
		wrong["carried"] = bad
		var problem: String = _parse(JSON.stringify(wrong)).problem
		if not problem.begins_with("a carried monster"):
			return "a save carrying %s wasn't refused: %s" % [bad, problem]
	var _dropped: bool = save.erase("carried")
	save["format"] = 3
	var loaded: Profile = _parse(JSON.stringify(save))
	var three: Array[String] = [ShortId.stand_in(1), ShortId.stand_in(2), ShortId.stand_in(3)]
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
	var _first: String = older.apply(_result(["ombulumo"], {}))
	var newer: Profile = Profile.new()
	var _second: String = newer.apply(_result(["ombulumo", "ember_fox"], {}))
	var problem: String = ProfileStore.save(older, SAVE_PATH)
	problem += ProfileStore.save(newer, SAVE_PATH)
	var newest: String = FileAccess.get_file_as_string(SAVE_PATH)
	var damaged_saves: Array[String] = [
		newest.replace("ember_fox", "ember_cat"),
		newest.left(40),
		newest.replace("\"save\": 1", "\"saved\": 1"),
	]
	for damaged: String in damaged_saves:
		_write(SAVE_PATH, damaged)
		var loaded: Profile = ProfileStore.load_from(SAVE_PATH)
		if not problem.is_empty() or ProfileStore.loaded_generation != 1:
			return "a damaged newest save didn't fall back a generation: " + problem
		if _text(loaded) != _text(older):
			return "the fallback isn't the save before the damaged one"
	for file: String in [SAVE_PATH, SAVE_PATH + ".1"]:
		_write(file, "{}")
	if ProfileStore.load_from(SAVE_PATH).problem.is_empty():
		return "a save with every generation damaged was read"
	SaveStore.remove(SAVE_PATH)
	_write(SAVE_PATH, _text(newer))
	if _text(ProfileStore.load_from(SAVE_PATH)) != _text(newer):
		return "a plain save from before checksums didn't load"
	return ""


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var _stored: bool = file.store_string(text)
	file.close()


## `profile`'s save text with `quests`, or none, beside it, as the game writes it (QuestKeeper,
## #855).
static func _text(profile: Profile, quests: QuestTracker = null) -> String:
	var keeper: QuestKeeper = QuestKeeper.new()
	if quests != null:
		keeper.tracker = quests
	var text: String = ProfileSave.to_text(profile, [keeper])
	keeper.free()
	return text


## `profile`'s save with `quests`, or none, beside it as data in save format `format`, from before
## the profile keyed its monsters on their short ids (#754): each monster numbered by its place from
## 1, the carried ones named by their numbers, and the next number beside them. What else changed
## since `format` is the caller's to change.
static func _numbered(profile: Profile, format: int, quests: QuestTracker = null) -> Dictionary:
	var data: Dictionary = JSON.parse_string(_text(profile, quests))
	var numbers: Dictionary = {}
	var monsters: Array = data["dominated_monsters"]
	for place: int in monsters.size():
		var entry: Dictionary = monsters[place]
		entry["id"] = place + 1
		numbers[entry["short_id"]] = place + 1
	var carried: Array = data["carried"]
	for place: int in carried.size():
		carried[place] = numbers[carried[place]]
	data["next_monster_id"] = monsters.size() + 1
	var _unnamed: bool = data.erase(FormatChanges.KEY)
	data["format"] = format
	return data


## The profile read from the save `text`, its quests read beside it into `_parsed_quests`, as the
## game reads them (QuestKeeper, #855).
func _parse(text: String) -> Profile:
	var keeper: QuestKeeper = QuestKeeper.new()
	var profile: Profile = ProfileSave.parse(text, [keeper])
	_parsed_quests = keeper.tracker
	keeper.free()
	return profile
