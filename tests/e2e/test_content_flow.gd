extends RefCounted
## Content flow (#72): the game's content data loads, and holds together where a schema can't
## check it. Every species file reads, with comments stripped; ids are unique and match their file;
## types come from the type chart, never two from one family; every species has a name for the
## player (#351), one invented word (#717); and broken entries are refused. Loot tables (#90)
## load, roll the same for the same stream, and a blank rolls on the instance's table.
## Tile blueprints (#116) load, the built-in ones with the numbers and traits regions always had,
## and broken ones are refused. Quests (#184) load with the steps they're written with, name only
## species that exist, side quests name the area they start in (#473), choices lead to steps of
## their quest and ends close its own chain (#573), every path reaches an end (#576), and broken
## ones are refused; a quest can move
## the standing with a faction (#532). Factions (#483) load with their own names for the ranks of a
## standing, their symbols and the instances they hold (#637), and broken ones are refused. Quests
## and abilities carry path marks (#471). Dialogs
## (#618) load and read on line by line and answer by answer, and broken ones are refused. Every
## text tag (#733) in a dialog, a quest's name or an ability's description names content that
## exists, shows its current name, and broken tags are refused.

## A species file's speed, archetype, abilities (#222), name (#351) and strike type (#626), as a
## valid species ends.
const KIT: String = (
	", \"name\": \"Xo\", \"strike_type\": \"might\", \"speed\": 1, \"archetype\": \"pusher\","
	+ " \"special\": \"a_special\", \"player_passive\": \"a_passive\","
	+ " \"self_passive\": \"its_passive\""
)
## A quest step to reach a place, its id left open (#339).
const REACH: String = "{\"condition\": \"reached\", \"place\": \"%s\"}"
## A quest step to enter a region piece, its id left open (#350).
const ENTER: String = "{\"condition\": \"entered\", \"piece\": \"%s\"}"
## A quest step to enter an instance, its blueprint left open (#370).
const ENTER_INSTANCE: String = "{\"condition\": \"entered\", \"instance\": \"%s\"}"
## A quest step to choose an answer in a dialog, both ids left open (#636).
const ANSWERED: String = "{\"condition\": \"answered\", \"dialog\": \"%s\", \"answer\": \"%s\"}"
## A quest step with the id b that ends the chain x (#573).
const STEP_B: String = "{\"id\": \"b\", \"condition\": \"opened\", \"ends\": \"x\"}"
## A quest step to open a chest that ends the chain x (#576).
const OPENED_END: String = "{\"condition\": \"opened\", \"ends\": \"x\"}"
## A faction file x with a symbol (#637), its ranks up and down left open (#483).
const FACTION_TEXT: String = (
	"{\"id\": \"x\", \"name\": \"X\", \"symbol\": \"+\", \"ranks_up\": %s, \"ranks_down\": %s}"
)
## Five rank names, as a faction has each way.
const FIVE_RANKS: String = "[\"a\", \"b\", \"c\", \"d\", \"e\"]"


func run(_tree: SceneTree) -> String:
	var content: SpeciesData = SpeciesContent.load_species()
	if not content.problem.is_empty():
		return "the species data didn't load: " + content.problem
	if (not content.species.has("moss_toad")
			or content.species["moss_toad"].name != "Ombulumo"
			or content.species["storm_finch"].types.size() != 2
			or content.species["moss_toad"].strike_type != "growth"):
		return "the placeholder species didn't load as written"
	var checks: Array[Callable] = [
		_check_strip,
		_check_refused,
		_check_loot_rolls,
		_check_harvest_tables,
		_check_loot_refused,
		_check_wild_species.bind(content),
		_check_tiles,
		_check_quests,
		_check_factions,
		_check_dialogs,
		_check_dialogs_refused,
		_check_kits.bind(content),
		_check_text_tags,
	]
	for check: Callable in checks:
		var result: String = check.call()
		if not result.is_empty():
			return result
	return ""


## Every ability file reads, and every species names a special and two passives that exist and are
## of their kind, its special its own (#222, #228). A special two species share, an ability of the
## wrong kind, or one that doesn't exist is refused, and so is an ability file with a wrong id,
## kind, name or description, a special without its power and cooldown (#410) or a strike type on
## the chart (#626), or a passive with any of them.
func _check_kits(content: SpeciesData) -> String:
	var loaded: SpeciesData = SpeciesContent.load_abilities()
	if not loaded.problem.is_empty():
		return "the abilities didn't load: " + loaded.problem
	var problem: String = SpeciesKit.problem(content.species, loaded.abilities)
	if not problem.is_empty():
		return "the species' abilities don't hold together: " + problem
	var finch: Species = content.species["storm_finch"]
	var toad: Species = content.species["moss_toad"]
	var shared: Dictionary[String, Species] = { "a": toad, "b": _copy_kit(finch, toad.special) }
	if not SpeciesKit.problem(shared, loaded.abilities).contains("share the special"):
		return "two species sharing a special weren't refused"
	var wrong: Dictionary[String, Species] = { "b": _copy_kit(finch, finch.self_passive) }
	if not SpeciesKit.problem(wrong, loaded.abilities).contains("isn't an ability of that kind"):
		return "a passive named as a special wasn't refused"
	var missing: Dictionary[String, Species] = { "b": _copy_kit(finch, "no_such_ability") }
	if SpeciesKit.problem(missing, loaded.abilities).is_empty():
		return "a special that doesn't exist wasn't refused"
	var result: String = _check_path_marks(loaded.abilities)
	return result if not result.is_empty() else _check_abilities_refused()


## Quests and abilities read their path marks (#471) as written, none when they have none, and a
## quest's name shows its mark in words after it (#68); a path that isn't a mark is refused.
func _check_path_marks(abilities: Dictionary[String, Ability]) -> String:
	var quests: Dictionary[String, QuestDefinition] = QuestContent.load_quests().quests
	if (quests["three_moss_toads"].path != PathMark.SUPREMACY
			or quests["first_domination"].path != PathMark.NONE
			or abilities["storm_finch_gale_dive"].path != PathMark.SUPREMACY
			or abilities["moss_toad_damp_hide"].path != PathMark.NONE):
		return "the path marks didn't read as written"
	if quests["three_moss_toads"].shown_name() != "Dominate three Ombulumo (Supremacy)":
		return "a quest's name doesn't show its path mark in words"
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"path\": %s,"
	quest += " \"steps\": [{\"condition\": \"opened\"}]}"
	var ability: String = "{\"id\": \"x\", \"kind\": \"self_passive\", \"name\": \"N\","
	ability += " \"description\": \"d\", \"path\": %s}"
	for path: String in ["\"evil\"", "1", "\"\""]:
		if QuestDefinition.parse("x", quest % path, {}).problem != PathMark.PROBLEM:
			return "a quest with the path %s wasn't refused" % path
		if Ability.parse("x", ability % path).problem != PathMark.PROBLEM:
			return "an ability with the path %s wasn't refused" % path
	return ""


## A copy of `species`' kit with `special` as its special.
static func _copy_kit(species: Species, special: String) -> Species:
	var copy: Species = Species.new()
	copy.id = species.id + "_copy"
	copy.special = special
	copy.player_passive = species.player_passive
	copy.self_passive = species.self_passive
	return copy


func _check_abilities_refused() -> String:
	var ability: String = "{\"id\": \"%s\", \"kind\": \"%s\", \"name\": \"%s\","
	ability += " \"description\": \"d\"}"
	var special: String = ability.replace(
		"}",
		", \"power\": 3000, \"cooldown_seconds\": 8, \"strike_type\": \"titan\"}",
	)
	var cases: Dictionary[String, String] = {
		ability % ["y", "special", "N"]: "its id must",
		ability % ["x", "attack", "N"]: "its kind",
		ability % ["x", "special", ""]: "it has a name",
		"{\"id\": \"x\", \"kind\": \"special\", \"name\": \"N\"}": "it has a name",
		ability.replace("}", ", \"damage\": 1}") % ["x", "special", "N"]: "field damage",
		ability % ["x", "special", "N"]: "a special has a power and a cooldown",
		special.replace(", \"power\": 3000", "") % ["x", "special", "N"]: "a special has a power",
		special % ["x", "self_passive", "N"]: "a special has a power, a cooldown and a strike",
		special.replace("titan", "fire") % ["x", "special", "N"]: "a special has a strike type",
	}
	for text: String in cases:
		var problem: String = Ability.parse("x", text).problem
		if not problem.begins_with(cases[text]):
			return "expected an ability refusal starting %s, got: %s" % [cases[text], problem]
	var read: Ability = Ability.parse("x", special % ["x", "special", "N"])
	if (not read.problem.is_empty() or read.power != 3000 or read.cooldown_seconds != 8
			or read.strike_type != "titan"):
		return "a special's power, cooldown and strike type didn't read: " + read.problem
	return ""


## Why a step to reach the beach, one to enter the thicket and one to enter the glade don't read,
## naming them, or "".
func _check_named_steps(content: QuestData) -> String:
	var named: QuestDefinition = QuestDefinition.parse(
		"x",
		"{\"id\": \"x\", \"name\": \"N\", \"steps\": [%s, %s, %s]}" % [
			REACH % "beach",
			ENTER % "thicket",
			ENTER_INSTANCE % "glade\", \"ends\": \"x",
		],
		content.species,
	)
	if (not named.problem.is_empty()
			or named.steps[0].place != "beach"
			or named.steps[1].piece != "thicket"
			or named.steps[2].instance != "glade"
			or not named.steps[2].piece.is_empty()):
		return "a step to reach or enter something didn't read: " + named.problem
	return ""


## Why broken steps to enter an instance (#370) aren't refused, with a reason, or "": one naming
## both a piece and an instance, an instance on another step, an instance that isn't an id or
## isn't a blueprint. Then the answered steps.
func _check_instance_steps(content: QuestData) -> String:
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"steps\": [%s]}"
	var cases: Dictionary[String, String] = {
		quest % "{\"condition\": \"opened\", \"instance\": \"glade\"}": (
			"step 0: its piece or instance"
		),
		quest % (ENTER_INSTANCE % "glade\", \"piece\": \"start"): "step 0: its piece or instance",
		quest % (ENTER_INSTANCE % "The Glade"): "step 0: its instance must be an id",
		quest % (ENTER_INSTANCE % "nowhere"): "step 0: its instance must be an instance",
	}
	var problem: String = _unrefused(cases, content)
	return problem if not problem.is_empty() else _check_answered_steps(content)


## Why broken answered steps (#636) aren't refused, with a reason, or "": an answered step names a
## dialog and its answer, both, each an id, and no other step names either.
func _check_answered_steps(content: QuestData) -> String:
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"steps\": [%s]}"
	var cases: Dictionary[String, String] = {
		quest % "{\"condition\": \"answered\", \"dialog\": \"a\"}": "step 0: its dialog and answer",
		quest % "{\"condition\": \"opened\", \"answer\": \"a\"}": "step 0: its dialog and answer",
		quest % (ANSWERED % ["A Dialog", "a"]): "step 0: its dialog must",
		quest % (ANSWERED % ["a", "An Answer"]): "step 0: its answer must",
	}
	return _unrefused(cases, content)


## Why the side quests (#473) don't read, or "": the pond's chest starts on entering the pond, a
## quest without a start has none, and a start that isn't reaching a place or entering a piece or
## an instance, or that has a count, is refused. Then the standings quests move.
func _check_side_quests(content: QuestData) -> String:
	var pond: QuestDefinition = content.quests.get("pond_chest")
	var first: QuestDefinition = content.quests["first_domination"]
	if (pond == null or pond.starts_on == null or pond.starts_on.condition != "entered"
			or pond.starts_on.piece != "pond" or first.starts_on != null):
		return "the pond's chest doesn't start on entering the pond, or another quest has a start"
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"starts_on\": %s, \"steps\": [%s]}"
	var counted: String = "{\"condition\": \"entered\", \"piece\": \"pond\", \"count\": 1}"
	var cases: Dictionary[String, String] = {
		quest % ["{\"condition\": \"opened\"}", OPENED_END]: "its start must be one of",
		quest % ["{\"condition\": \"entered\"}", OPENED_END]: "its start: its piece or instance",
		quest % [counted, OPENED_END]: "its start happens once",
		quest % [REACH % "The Beach", OPENED_END]: "its start: its place must",
	}
	var result: String = _unrefused(cases, content)
	return result if not result.is_empty() else _check_quest_standings(content)


## Why the standings quests move (#532) don't read, or "": the first domination raises the
## Cartographer's Guild by one, the toads' quest moves none, and a standing that isn't an object,
## has another field, names no faction id, or changes by nothing, a fraction, text or more than the
## whole scale is refused.
func _check_quest_standings(content: QuestData) -> String:
	var raised: QuestStanding = content.quests["first_domination"].standing
	if (raised == null or raised.faction != "cartographers_guild" or raised.change != 1
			or content.quests["three_moss_toads"].standing != null):
		return "the first domination doesn't raise the guild by one, or another quest moves one"
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"standing\": %s, \"steps\": [%s]}"
	var standing: String = "{\"faction\": \"%s\", \"change\": %s}"
	var cases: Dictionary[String, String] = {
		quest % ["1", OPENED_END]: "its standing: it isn't",
		quest % [
			"{\"faction\": \"a\", \"change\": 1, \"by\": 1}",
			OPENED_END,
		]: "its standing: field by",
		quest % [standing % ["The Guild", "1"], OPENED_END]: "its standing: its faction",
		quest % ["{\"change\": 1}", OPENED_END]: "its standing: its faction",
		quest % [standing % ["a", "0"], OPENED_END]: "its standing: its change",
		quest % [standing % ["a", "11"], OPENED_END]: "its standing: its change",
		quest % [standing % ["a", "-11"], OPENED_END]: "its standing: its change",
		quest % [standing % ["a", "1.5"], OPENED_END]: "its standing: its change",
		quest % [standing % ["a", "\"1\""], OPENED_END]: "its standing: its change",
		quest % ["{\"faction\": \"a\"}", OPENED_END]: "its standing: its change",
	}
	var lowering: String = quest % [standing % ["a", "-10"], OPENED_END]
	var lowered: QuestDefinition = QuestDefinition.parse("x", lowering, {})
	if not lowered.problem.is_empty() or lowered.standing.change != -QuestStanding.MAX_CHANGE:
		return "a quest lowering a standing by the whole scale didn't read: " + lowered.problem
	var problem: String = _unrefused(cases, content)
	return problem if not problem.is_empty() else _check_quest_territories(content)


## Why territory quests (#638) don't read, or "": every one names an instance that exists and a
## faction, filed by the code a command hands it over by, and starts once the player enters that
## instance (the ground rules in AGENTS.md), while the quests that aren't territory
## quests name none; a territory that isn't an object, has another field, or doesn't name an
## instance and a faction by their ids is refused.
func _check_quest_territories(content: QuestData) -> String:
	var handed: int = 0
	for id: String in content.quests:
		var territory: QuestTerritory = content.quests[id].territory
		if territory == null:
			continue
		var by: int = Territory.code(territory.instance, territory.faction)
		if not InstanceBlueprints.exists(territory.instance) or not content.handovers.has(by):
			return "%s hands over %s, which doesn't exist or isn't filed" % [id, territory.instance]
		var start: QuestStep = content.quests[id].starts_on
		if start == null or start.condition != "entered" or start.instance != territory.instance:
			return "%s doesn't start once the player enters %s" % [id, territory.instance]
		handed += 1
	if handed == 0 or content.quests["first_domination"].territory != null:
		return "no quest hands a territory over, or the first domination does"
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"territory\": %s, \"steps\": [%s]}"
	var cases: Dictionary[String, String] = {
		quest % ["\"forest\"", OPENED_END]: "its territory: it isn't",
		quest % ["{\"instance\": \"forest\", \"faction\": \"a\", \"by\": 1}", OPENED_END]:
		"its territory: field by",
		quest % ["{\"instance\": \"Forest\", \"faction\": \"a\"}", OPENED_END]:
		"its territory: it names",
		quest % ["{\"instance\": \"forest\"}", OPENED_END]: "its territory: it names",
	}
	var problem: String = _unrefused(cases, content)
	return problem if not problem.is_empty() else _check_branches(content)


## Why branching quests (#573) don't read, or "": the glade's fork offers the pond and the thicket,
## each leading to its own step, and both end its chain. Choices that aren't two or more, aren't a
## place or an area, have a count, or lead nowhere are refused; so are a step with choices that has
## a condition or an end, two steps with one id, and an end naming another chain.
func _check_branches(content: QuestData) -> String:
	var fork: QuestDefinition = content.quests.get("glade_fork")
	if (fork == null or fork.steps[0].choices.size() != 2
			or fork.steps[0].choices[0].piece != "pond"
			or fork.next_index(0, "entered", "thicket") != 2
			or fork.steps[1].ends != "glade_fork" or fork.steps[2].ends != "glade_fork"):
		return "the glade's fork didn't read as a choice between two ends"
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"steps\": [%s, " + STEP_B + "]}"
	var choices: String = "{\"choices\": [%s]}"
	var to_b: String = "{\"condition\": \"entered\", \"piece\": \"pond\", \"next\": \"%s\"}"
	var two: String = to_b % "b" + ", " + to_b % "b"
	var cases: Dictionary[String, String] = {
		quest % (choices % (to_b % "b")): "step 0: its choices are a list of two",
		quest % (choices % (two + ", 7")): "step 0: choice 2: it isn't",
		quest % (choices % (to_b % "b" + ", {\"condition\": \"opened\", \"next\": \"b\"}")): (
			"step 0: choice 1: its condition"
		),
		quest % (choices % (two.replace("}", ", \"count\": 1}"))): "step 0: choice 0: field count",
		quest % (choices % (to_b % "b" + ", " + to_b % "c")): "step 0: a choice leads to c",
		quest % (choices % (to_b % "b" + ", " + to_b % "Bee")): "step 0: choice 1: the step",
		quest % ((choices % two).replace("{\"choices", "{\"condition\": \"opened\", \"choices")): (
			"step 0: a step with choices has no condition"
		),
		quest % ((choices % two).replace("{\"choices", "{\"ends\": \"x\", \"choices")): (
			"step 0: a step with choices leads on"
		),
		quest % STEP_B: "step 1: its id b",
		quest % "{\"condition\": \"opened\", \"ends\": \"y\"}": "step 0: it ends the chain y",
		quest % "{\"condition\": \"opened\", \"id\": \"B\"}": "step 0: its id must",
	}
	var problem: String = _unrefused(cases, content)
	return problem if not problem.is_empty() else _check_paths(content, quest, to_b)


## Why quests whose paths don't all reach an end (#576) aren't refused, or "": a path stopping at
## an untagged last step, in a branching quest or a linear one, and a loop without a way out are; a
## loop with a way out reads.
func _check_paths(content: QuestData, quest: String, to: String) -> String:
	var looping: String = "{\"id\": \"c\", \"choices\": [%s, %s]}"
	var way_out: String = quest % (looping % [to % "c", to % "b"])
	var parsed: QuestDefinition = QuestDefinition.parse("x", way_out, content.species)
	if not parsed.problem.is_empty():
		return "a loop with a way out didn't read: " + parsed.problem
	var fork: String = "{\"choices\": [%s, %s]}" % [to % "b", to % "c"]
	var stopping: String = "{\"id\": \"x\", \"name\": \"N\", \"steps\": [%s, %s, %s]}" % [
		fork,
		STEP_B,
		"{\"id\": \"c\", \"condition\": \"opened\"}",
	]
	var cases: Dictionary[String, String] = {
		stopping: "step 2: a path stops there, but it isn't tagged",
		quest.replace(", " + STEP_B, "") % (REACH % "beach"): "step 0: a path stops there",
		quest % (looping % [to % "c", to % "c"]): "step 0: no path on from it reaches an end",
	}
	return _unrefused(cases, content)


## Why one of the quests in `cases` isn't refused with the reason it maps to, or "".
static func _unrefused(cases: Dictionary[String, String], content: QuestData) -> String:
	for text: String in cases:
		var problem: String = QuestDefinition.parse("x", text, content.species).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	return ""


## Every quest file reads: the first domination is reaching the beach, then one domination of
## any species (#321), and the toads' quest counts up three of one species, a step to reach a
## place names it (#339), and one to enter a region piece names the piece (#350), or an instance
## its blueprint (#370). Quests with a wrong id, name, step, condition, species, place, piece,
## instance or count are refused, with a reason: a reached step without a place, or a place on
## another step, too, and the same for an entered step and its piece or instance, which it names
## one of, never both, and the same for an answered step and its dialog and answer (#636).
func _check_quests() -> String:
	var content: QuestData = QuestContent.load_quests()
	if not content.problem.is_empty():
		return "the quests didn't load: " + content.problem
	var first: QuestDefinition = content.quests.get("first_domination")
	var toads: QuestDefinition = content.quests.get("three_moss_toads")
	if first == null or first.name.is_empty() or first.steps.size() != 2 or toads == null:
		return "the quests didn't load as written"
	if first.steps[0].condition != "reached" or first.steps[0].place != "beach":
		return "the first domination doesn't lead to the beach first"
	var any_domination: QuestStep = first.steps[1]
	var toad_step: QuestStep = toads.steps[0]
	if (any_domination.condition != "dominated"
			or any_domination.species != null
			or any_domination.count != 1):
		return "the first domination isn't one domination of any species"
	var toad: Species = toad_step.species if toad_step.species != null else Species.new()
	if toad.id != "moss_toad" or toad.name != "Ombulumo" or toad_step.count != 3:
		return "the toads' quest isn't three moss toads"
	if not _check_named_steps(content).is_empty():
		return _check_named_steps(content)
	if not _check_instance_steps(content).is_empty():
		return _check_instance_steps(content)
	if not _check_side_quests(content).is_empty():
		return _check_side_quests(content)
	var quest: String = "{\"id\": \"%s\", \"name\": \"%s\", \"steps\": [%s]}"
	var step: String = "{\"condition\": \"dominated\"%s}"
	var cases: Dictionary[String, String] = {
		quest % ["y", "N", step % ""]: "its id must",
		quest % ["x", " ", step % ""]: "it needs a name",
		quest % ["x", "N", ""]: "it needs at least one step",
		quest % ["x", "N", "{\"condition\": \"defeated\"}"]: "step 0: its condition",
		quest % ["x", "N", "{\"condition\": \"reached\"}"]: "step 0: its place",
		quest % ["x", "N", step % ", \"place\": \"beach\""]: "step 0: its place",
		quest % ["x", "N", REACH % "The Beach"]: "step 0: its place must",
		quest % ["x", "N", "{\"condition\": \"entered\"}"]: "step 0: its piece",
		quest % ["x", "N", step % ", \"piece\": \"thicket\""]: "step 0: its piece",
		quest % ["x", "N", ENTER % "The Thicket"]: "step 0: its piece must",
		quest % ["x", "N", step % ", \"species\": \"ember_cat\""]: "step 0: its species",
		quest % ["x", "N", "{\"condition\": \"opened\", \"species\": \"moss_toad\"}"]: (
			"step 0: its species"
		),
		quest % ["x", "N", step % "" + ", " + step % ", \"count\": 0"]: "step 1: its count",
		quest % ["x", "N", step % ", \"count\": 1.5"]: "step 0: its count",
		quest % ["x", "N", step % ", \"when\": 1"]: "step 0: field when",
		quest % ["x", "N", "7"]: "step 0: it isn't",
	}
	return _unrefused(cases, content)


## Every tile blueprint file reads, its id matching its file; ground, water and rock keep their
## numbers and walkability; the rules number every kind by its file's number; forest, shrubs and
## a stump are walkable and a boulder isn't (#205), each with its model, and sand is plain and
## walkable (#321); every model a blueprint names exists; the stump is drawn at 400 hundredths
## of its size (#588), every other kind at 100, the default; no two kinds share a symbol (#68).
## Broken blueprints, and two with one number, are refused.
func _check_tiles() -> String:
	var content: Content = Content.load_tiles()
	if not content.problem.is_empty():
		return "the tile blueprints didn't load: " + content.problem
	var walkable: Dictionary[String, bool] = {
		"ground": true,
		"water": false,
		"rock": false,
		"forest": true,
		"shrubs": true,
		"boulder": false,
		"stump": true,
		"sand": true,
	}
	var plain: Array[String] = ["ground", "water", "rock", "sand"]
	for id: String in walkable:
		var kind: int = TileKinds.number_of(id)
		if (not content.tiles.has(id) or TileKinds.is_walkable(kind) != walkable[id]
				or content.tiles[id].model.is_empty() != plain.has(id)):
			return "tile blueprint %s is missing, not as walkable as written, or (un)decorated" % id
	var built_in: Array[int] = [Region.GROUND, Region.WATER, Region.BLOCKED]
	if built_in != [content.tiles["ground"].number, content.tiles["water"].number,
			content.tiles["rock"].number]:
		return "the built-in tile kinds don't keep their numbers"
	var symbols: Dictionary[String, String] = {}
	for tile: TileBlueprint in content.tiles.values():
		if TileKinds.number_of(tile.id) != tile.number or TileKinds.id_of(tile.number) != tile.id:
			return "the rules don't number tile blueprint %s by its file" % tile.id
		if symbols.has(tile.symbol):
			return "tile blueprints %s and %s share one symbol" % [symbols[tile.symbol], tile.id]
		symbols[tile.symbol] = tile.id
		var missing: bool = not tile.model.is_empty() and not ResourceLoader.exists(tile.model)
		if missing or tile.scale != (400 if tile.id == "stump" else TileBlueprint.FULL_SCALE):
			return "tile blueprint %s's model %s doesn't exist, or it's drawn at scale %s" % [
				tile.id,
				tile.model,
				tile.scale,
			]
	var result: String = _check_tiles_refused()
	return result if not result.is_empty() else _check_tile_numbers_unique()


## Tile blueprints with a wrong id, number, color, symbol (#68), scale, crown (#232) or trait are
## refused, with a reason; the largest scale is read, and so is a crown's reach and clearance.
func _check_tiles_refused() -> String:
	var tile: String = (
		"{\"id\": \"%s\", \"number\": %s, \"color\": \"%s\", \"symbol\": \"x\", "
		+ "\"traits\": {%s}%s}"
	)
	var walks: String = "\"walkable\": true"
	var cases: Dictionary[String, String] = {
		tile % ["y", "9", "#000000", walks, ""]: "its id must",
		tile % ["x", "-1", "#000000", walks, ""]: "its number",
		tile % ["x", "1.5", "#000000", walks, ""]: "its number",
		tile % ["x", "\"9\"", "#000000", walks, ""]: "its number",
		tile % ["x", "9", "green", walks, ""]: "its color",
		tile % ["x", "9", "#000000", "", ""]: "its traits",
		tile % ["x", "9", "#000000", walks + ", \"swims\": true", ""]: "field swims",
		tile % ["x", "9", "#000000", walks, ", \"size\": 1"]: "field size",
		tile % ["x", "9", "#000000", walks, ", \"scale\": 0"]: "its scale",
		tile % ["x", "9", "#000000", walks, ", \"scale\": 401"]: "its scale",
		tile % ["x", "9", "#000000", walks, ", \"scale\": 1.5"]: "its scale",
		tile % ["x", "9", "#000000", walks, ", \"scale\": \"2\""]: "its scale",
		tile % ["x", "9", "#000000", walks, ", \"reach\": 9"]: "its reach",
		tile % ["x", "9", "#000000", walks, ", \"clearance\": -1"]: "its reach",
		tile.replace(", \"symbol\": \"x\"", "") % ["x", "9", "#000000", walks, ""]: "its symbol",
		tile.replace("\"x\", ", "\"xy\", ") % ["x", "9", "#000000", walks, ""]: "its symbol",
	}
	for text: String in cases:
		var problem: String = TileBlueprint.parse("x", text).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var largest: TileBlueprint = TileBlueprint.parse("x", tile % ["x", "9", "#000000", walks,
			", \"scale\": 400"])
	if not largest.problem.is_empty() or largest.scale != TileBlueprint.MAX_SCALE:
		return "the largest scale is refused or misread: %s" % largest.problem
	var crown: TileBlueprint = TileBlueprint.parse("x", tile % ["x", "9", "#000000", walks,
			", \"reach\": 1, \"clearance\": 40"])
	if (not crown.problem.is_empty()
			or crown.reach != 1
			or crown.clearance != 40):
		return "a crown's reach or clearance is refused or misread: %s" % crown.problem
	return ""


## Two tile blueprints with the same number are refused: a number names one kind forever.
func _check_tile_numbers_unique() -> String:
	var directory: String = "user://tile_numbers_test/"
	var _made: Error = DirAccess.make_dir_recursive_absolute(directory)
	var tile: String = "{\"id\": \"%s\", \"number\": 7, \"color\": \"#000000\", "
	tile += "\"symbol\": \"%s\", \"traits\": {\"walkable\": true}}"
	for id: String in ["a", "b"]:
		var file: FileAccess = FileAccess.open(directory + id + ".jsonc", FileAccess.WRITE)
		var _stored: bool = file.store_string(tile % [id, id])
		file.close()
	var problem: String = Content.load_tiles(directory).problem
	for id: String in ["a", "b"]:
		var _removed: Error = DirAccess.remove_absolute(directory + id + ".jsonc")
	var _gone: Error = DirAccess.remove_absolute(directory)
	if not problem.begins_with("b.jsonc: its number 7"):
		return "two tile blueprints with one number weren't refused: %s" % problem
	return ""


## Every blueprint lists the species its unnamed spots roll from, and every species a blueprint
## lists or a region piece names is one the species data has (#133).
func _check_wild_species(content: SpeciesData) -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		var listed: Dictionary = InstanceBlueprints.WILD_SPECIES.get(instance_name, { })
		var named: Array[String] = []
		for spot: WildSpot in InstanceBlueprints.region_of(instance_name, 0).wild_spots.values():
			named.append(spot.species)
		if listed.is_empty():
			return "the %s blueprint lists no species for its wild monsters" % instance_name
		for species: Variant in listed.keys() + named:
			if not content.species.has(str(species)):
				return "%s places a species that doesn't exist: %s" % [instance_name, species]
	return ""


## Comments go, strings keep their slashes and stars, and line breaks stay where they were.
func _check_strip() -> String:
	var text: String = "{\n\"a\": \"x // y /* z */\", // gone\n/* gone\ntoo */ \"b\": 1\n}"
	var stripped: String = Jsonc.strip(text)
	var expected: String = "{\n\"a\": \"x // y /* z */\", \n\n \"b\": 1\n}"
	if stripped != expected:
		return "stripping comments gave %s" % stripped.c_escape()
	# An escaped quote doesn't end a string, and an escaped backslash doesn't escape the quote.
	var escaped: String = "[\"q\\\" // text\", \"c:\\\\\"] // gone"
	if Jsonc.strip(escaped) != "[\"q\\\" // text\", \"c:\\\\\"] ":
		return "an escaped quote or backslash ended a string at the wrong place"
	# A comment that's never closed stays, so the text can't parse.
	var unclosed: JSON = JSON.new()
	if unclosed.parse(Jsonc.strip("{\"a\": 1} /* never closed")) == OK:
		return "an unclosed comment was silently dropped"
	return ""


## Why a species file named x with this text is refused in otherwise empty content, or "".
func _add_to_empty(text: String) -> String:
	return SpeciesData.new().add_species("x", text)


## Entries a schema might let through or that clash with others are refused, with a reason.
func _check_refused() -> String:
	var cases: Dictionary[String, String] = {
		"{\"id\": \"other\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1}": "its id",
		# Mana and Arcane are one family's two types.
		"{\"id\": \"x\", \"types\": [\"mana\", \"arcane\"], \"hp\": 1, \"strength\": 1}": (
			"type arcane"
		),
		"{\"id\": \"x\", \"types\": [\"fire\"], \"hp\": 1, \"strength\": 1}": "type fire",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1.5, \"strength\": 1}": "hp and strength",
		"{\"id\": \"x\", \"types\": [], \"hp\": 1, \"strength\": 1}": "a species has one",
		"{\"id\": 7, \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1}": "its id must be",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1, \"y\": 1}": "field y",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1}": "speed is",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("pusher", "digger") + "}": "its archetype",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("might", "fire") + "}": "its strike type",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"a_special\"", "7") + "}": "it names a special",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"name\": \"Xo\", ", "") + "}": "it needs a name",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"Xo\"", "\" \"") + "}": "it needs a name",
		# A description isn't a name (#717): two words, or small letters only.
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"Xo\"", "\"Moss Toad\"") + "}": "it needs a name",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"Xo\"", "\"xo\"") + "}": "it needs a name",
	}
	for text: String in cases:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var twice: SpeciesData = SpeciesData.new()
	var valid: String = "{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
	valid += KIT + "}"
	var first: String = twice.add_species("x", valid)
	if not first.is_empty() or not twice.add_species("x", valid).begins_with("its id"):
		return "a second species with the same id was accepted"
	return ""


## The placeholder tables load. A roll on the toad's table gives 2 to 4 berries, or on its blank
## what the glade's table gives (1 to 2 moss, a single berry or a single revive herb, #656), and the
## same stream rolls the same loot. The glade's own rolls and its chests' give a revive herb now
## and then.
func _check_loot_rolls() -> String:
	var content: LootData = LootContent.load_loot_tables()
	if not content.problem.is_empty():
		return "the loot tables didn't load: " + content.problem
	var toad: LootTable = content.loot_tables["moss_toad"]
	var glade: LootTable = content.loot_tables["glade"]
	var hits: Dictionary[bool, int] = { true: 0, false: 0 }
	for seed_value: int in 100:
		var loot: Dictionary[String, int] = _roll(toad, glade, seed_value)
		if loot != _roll(toad, glade, seed_value):
			return "seed %d rolled two different loots" % seed_value
		var own: bool = loot.get("berry", 0) >= 2 and loot["berry"] <= 4
		var single: bool = loot.get("berry", 0) == 1 or loot.get(ReviveItem.ID, 0) == 1
		var blank: bool = single or loot.get("moss", 0) in [1, 2]
		if loot.size() != 1 or not (own or blank):
			return "seed %d rolled %s" % [seed_value, loot]
		hits[own] += 1
	if hits[true] == 0 or hits[false] == 0:
		return "the toad's rolls never gave its berries or never hit the blank"
	var herb_tables: Array[String] = ["glade", "glade_chest"]
	for table_id: String in herb_tables:
		var herbs: int = 0
		for seed_value: int in 200:
			var rolled: int = _roll(content.loot_tables[table_id], null, seed_value).get(
				ReviveItem.ID,
				0,
			)
			herbs += rolled
		if herbs == 0:
			return "the %s table's rolls never gave a revive herb" % table_id
	return ""


## Every species has its own harvest table (#687), apart from its domination loot table: each loads
## as a harvest table named after a species, and a felled toad's rolls give what dominating it
## never does.
func _check_harvest_tables() -> String:
	var content: LootData = LootContent.load_loot_tables(LootContent.HARVEST_DIR)
	if not content.problem.is_empty():
		return "the harvest tables didn't load: " + content.problem
	var species: SpeciesData = SpeciesContent.load_species()
	for species_id: String in species.species:
		var table: LootTable = content.loot_tables.get(species_id)
		if table == null or table.kind != LootTable.HARVEST:
			return "%s has no harvest table" % species_id
	var toad: LootTable = content.loot_tables["moss_toad"]
	var dominated: LootTable = LootContent.load_loot_tables().loot_tables["moss_toad"]
	for seed_value: int in 100:
		for item: String in _roll(toad, null, seed_value):
			if dominated.items.has(item):
				return "a felled toad dropped %s, which dominating it gives" % item
	return ""


## One roll on `table` from a fresh stream of `seed_value`.
func _roll(table: LootTable, instance_table: LootTable, seed_value: int) -> Dictionary[String, int]:
	return table.roll(Rng.new(seed_value, 1), instance_table)


## Loot tables that don't add up, misplace the blank or break an entry are refused, with a reason.
func _check_loot_refused() -> String:
	var item: String = "{\"item\": \"a\", \"chance\": %d, \"min\": %d, \"max\": %d}"
	var blank: String = "{\"blank\": true, \"chance\": %d}"
	var table: String = "{\"id\": \"x\", \"kind\": \"%s\", \"entries\": [%s]}"
	var cases: Dictionary[String, String] = {
		table % ["instance", item % [500, 1, 1]]: "the chances add up",
		table % ["species", item % [1000, 1, 1]]: "a species or harvest table has exactly one",
		table % ["harvest", item % [1000, 1, 1]]: "a species or harvest table has exactly one",
		table % ["instance", "%s, %s" % [item % [500, 1, 1], blank % 500]]: "a species or harvest",
		table % ["instance", item % [1000, 3, 2]]: "entry 0 needs",
		table % ["vault", item % [1000, 1, 1]]: "its kind",
		table % ["chest", "%s, %s" % [item % [500, 1, 1], blank % 500]]: "a species or harvest",
		table % ["instance", "{\"blank\": true, \"chance\": 1000, \"min\": 1}"]: "field min",
		"{\"id\": \"y\", \"kind\": \"instance\", \"entries\": []}": "its id must",
		"{\"id\": true, \"kind\": \"instance\", \"entries\": []}": "its id must",
		table % ["instance", "{\"item\": true, \"chance\": 1000, \"min\": 1, \"max\": 1}"]: (
			"entry 0 needs"
		),
	}
	for text: String in cases:
		var problem: String = LootTableFile.parse("x", text).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	return ""


## The factions load, each with its own name for every rank but neutral (#483): the Cartographer's
## Guild's (#484) run from Apprentice Charter up to Charted in Legend and from Betrayer down. A
## faction file with a wrong id, no name, an unknown field, or not five rank names with more than
## spaces each way is refused.
func _check_factions() -> String:
	var content: FactionContent = FactionContent.load_factions()
	if not content.problem.is_empty() or not content.factions.has("cartographers_guild"):
		return "the factions didn't load: " + content.problem
	var guild: Faction = content.factions["cartographers_guild"]
	var names: Array[String] = []
	for standing: int in [Standings.LOWEST, -1, 0, 1, Standings.HIGHEST]:
		names.append(guild.rank_name(standing))
	var expected: Array[String] = [
		"Edge of the Chart", "Betrayer", "", "Apprentice Charter", "Charted in Legend",
	]
	if names != expected:
		return "the Cartographer's Guild's ranks read %s" % [names]
	var five: String = FIVE_RANKS
	var faction: String = FACTION_TEXT
	var cases: Dictionary[String, String] = {
		faction.replace("\"x\"", "\"y\"") % [five, five]: "its id must",
		faction.replace("\"X\"", "\" \"") % [five, five]: "it needs a name",
		faction % [five, "[\"a\", \"b\", \"c\", \"d\"]"]: "it needs 5 rank names",
		faction % [five, "[\"a\", \"b\", \"c\", \"d\", \"e\", \"f\"]"]: "it needs 5 rank names",
		faction % ["[\"a\", \"b\", \"c\", \"d\", \" \"]", five]: "it needs 5 rank names",
		faction % ["[\"a\", \"b\", \"c\", \"d\", 5]", five]: "it needs 5 rank names",
		faction.replace("}", ", \"z\": 1}") % [five, five]: "field z",
	}
	var refused: String = _factions_refused(cases)
	return refused if not refused.is_empty() else _check_faction_territory(content)


## Why any faction text among `cases` isn't refused with the beginning of the reason it's mapped to,
## or "".
func _factions_refused(cases: Dictionary[String, String]) -> String:
	for text: String in cases:
		var refusal: String = Faction.parse("x", text).problem
		if not refusal.begins_with(cases[text]):
			return "a broken faction gave %s, not %s" % [refusal, cases[text]]
	return ""


## The Cartographer's Guild is marked by its symbol and holds the glade, where the player starts
## (#637, #712), when a world starts, and every faction's territory names instance blueprints that
## exist. A faction file without a symbol, with a longer one, or with a territory that isn't a list
## of instance ids, each once, is refused, and so are two factions holding one instance or sharing a
## symbol.
func _check_faction_territory(content: FactionContent) -> String:
	var guild: Faction = content.factions["cartographers_guild"]
	if guild.symbol != "+" or " ".join(guild.territory) != "glade":
		return "the guild isn't marked + or doesn't hold the glade: %s %s" % [
			guild.symbol,
			guild.territory,
		]
	for each: Faction in content.factions.values():
		for instance_name: String in each.territory:
			if not InstanceBlueprints.exists(instance_name):
				return "%s's territory %s isn't an instance blueprint" % [each.id, instance_name]
	var faction: String = FACTION_TEXT % [FIVE_RANKS, FIVE_RANKS]
	var symbol: String = "\"symbol\": \"+\", "
	var territory: String = faction.replace("}", ", \"territory\": %s}")
	var refused: String = _factions_refused({
		faction.replace(symbol, ""): "it needs a symbol",
		faction.replace(symbol, "\"symbol\": \"+++\", "): "it needs a symbol",
		territory % "\"basic\"": "its territory must",
		territory % "[\"Basic\"]": "its territory must",
		territory % "[\"basic\", \"basic\"]": "its territory must",
	})
	if not refused.is_empty():
		return refused
	var held: String = territory % "[\"basic\"]"
	var twice: String = _pair_problem(held, held)
	if not twice.contains("basic is x's territory already"):
		return "two factions holding one instance gave %s" % twice
	var shared: String = _pair_problem(held, territory % "[\"glade\"]")
	if not shared.contains("its symbol + is x's already"):
		return "two factions sharing a symbol gave %s" % shared
	return ""


## Why the factions in two faction files, x from `text_x` and y from `text_y` with its id made y,
## are refused together, or "".
func _pair_problem(text_x: String, text_y: String) -> String:
	var directory: String = "user://test_factions/"
	var _made: Error = DirAccess.make_dir_recursive_absolute(directory)
	var texts: Dictionary[String, String] = { "x": text_x, "y": text_y.replace("\"x\"", "\"y\"") }
	for id: String in texts:
		var file: FileAccess = FileAccess.open(directory + id + ".jsonc", FileAccess.WRITE)
		var _stored: bool = file.store_string(texts[id])
		file.close()
	var problem: String = FactionContent.load_factions(directory).problem
	for id: String in texts:
		var _removed: Error = DirAccess.remove_absolute(directory + id + ".jsonc")
	return problem


## The dialogs load (#618): the guild scout's greeting reads on from its first line to its second,
## where asking about the glade leads to the line about it and the farewell ends it, as the glade
## line's only answer does too. An answer the line doesn't offer leads nowhere.
func _check_dialogs() -> String:
	var content: DialogContent = DialogContent.load_dialogs()
	if not content.problem.is_empty() or not content.dialogs.has("guild_scout_greeting"):
		return "the dialogs didn't load: " + content.problem
	var greeting: Dialog = content.dialogs["guild_scout_greeting"]
	var walked: Array[int] = [
		greeting.after(0),
		greeting.after(1, "ask_about_glade"),
		greeting.after(1, "leave_scout"),
		greeting.after(2, "promise_to_look"),
		greeting.after(1, "no_such_answer"),
		greeting.after(0, "ask_about_glade"),
	]
	if greeting.speaker != "Guild Scout" or walked != [1, 2, -1, -1, -1, -1]:
		return "the guild scout's greeting reads %s, by %s" % [walked, greeting.speaker]
	return ""


## Dialog files with a wrong id, no speaker or lines, a line without text, an answer without an id,
## two lines or answers sharing an id, or an answer leading to no line are refused (#618).
func _check_dialogs_refused() -> String:
	var dialog: String = "{\"id\": \"x\", \"speaker\": \"S\", \"lines\": [%s]}"
	var line: String = "{\"id\": \"a\", \"text\": \"T\", \"answers\": [%s]}"
	var answer: String = "{\"id\": \"%s\", \"text\": \"T\", \"next\": \"%s\"}"
	var cases: Dictionary[String, String] = {
		dialog.replace("\"x\"", "\"y\"") % "{\"text\": \"T\"}": "its id must",
		dialog.replace("\"S\"", "\" \"") % "{\"text\": \"T\"}": "it needs a speaker",
		dialog % "": "it needs a list",
		dialog % "{\"text\": \" \"}": "line 0: a line needs a text",
		dialog % "{\"text\": \"T\", \"answers\": []}": "line 0: a line's answers",
		dialog % (line % "{\"text\": \"T\"}"): "line 0: an answer needs an id",
		dialog % (line % (answer % ["b", "z"])): "line 0: answer b leads to z",
		dialog % ("%s, {\"id\": \"a\", \"text\": \"T\"}" % (line % (answer % ["b", "a"]))): (
			"line 1: another line"
		),
		dialog % (line % ("%s, %s" % [answer % ["b", "a"], answer % ["b", "a"]])): (
			"line 0: another answer"
		),
		dialog % "{\"text\": \"T\", \"z\": 1}": "line 0: field z",
	}
	for text: String in cases:
		var refusal: String = Dialog.parse("x", text).problem
		if not refusal.begins_with(cases[text]):
			return "a broken dialog gave %s, not %s" % [refusal, cases[text]]
	return ""


## Every text tag (#733) in the texts that show them (a dialog's speaker, lines and answers, a
## quest's name, an ability's description) names content that exists, and shows its current name;
## a tag of an unknown kind, with an id that doesn't exist, or written wrong is refused.
func _check_text_tags() -> String:
	var tags: TextTags = TextTags.load_tags()
	if not tags.problem.is_empty():
		return "the text tags' names didn't load: " + tags.problem
	var texts: Array[String] = []
	for dialog: Dialog in DialogContent.load_dialogs().dialogs.values():
		texts.append(dialog.speaker)
		for line: DialogLine in dialog.lines:
			texts.append(line.text)
			for answer: DialogAnswer in line.answers:
				texts.append(answer.text)
	for quest: QuestDefinition in QuestContent.load_quests().quests.values():
		texts.append(quest.name)
	for ability: Ability in SpeciesContent.load_abilities().abilities.values():
		texts.append(ability.description)
	for text: String in texts:
		if not tags.problem_in(text).is_empty():
			return "the text \"%s\" has a broken tag: %s" % [text, tags.problem_in(text)]
	var glade: String = DialogContent.load_dialogs().dialogs["guild_scout_greeting"].lines[2].text
	if not TextTags.shown(glade).begins_with("A glade, thick with Ombulumo. Something"):
		return "the scout's glade line shows %s" % TextTags.shown(glade)
	var shown: String = tags.resolve("${FACTION:cartographers_guild} sells ${GEAR:berry_pouch}")
	if shown != "Cartographer's Guild sells Berry pouch":
		return "faction and gear tags show %s" % shown
	var cases: Dictionary[String, String] = {
		"${BEAST:moss_toad}": "its kind must be one of",
		"${MONSTER:no_such_toad}": "no MONSTER has the id no_such_toad",
		"${MONSTER:Moss Toad}": "a tag is written",
		"${MONSTER:moss_toad": "a tag is written",
	}
	for text: String in cases:
		if not tags.problem_in(text).contains(cases[text]):
			return "the broken tag %s wasn't refused: %s" % [text, tags.problem_in(text)]
	return ""
