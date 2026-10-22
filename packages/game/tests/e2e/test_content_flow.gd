extends RefCounted
## Content flow (#72): the game's content data loads, and holds together where a schema can't
## check it. Every species file reads, with comments stripped; ids are unique and match their file;
## types come from the type chart, never two from one family; every species has a name for the
## player (#351), one invented word (#717); and broken entries are refused. Loot tables (#90)
## load, roll the same for the same stream, and a blank rolls on the instance's table.
## Tile blueprints (#116) load, the built-in ones with the traits regions always had, and broken
## ones are refused. Quests (#184) load with the steps they're written with, name only
## species that exist, side quests name the area they start in (#473), choices lead to steps of
## their quest and ends close its own chain (#573), every path reaches an end (#576), and broken
## ones are refused; a quest can move
## the standing with a faction (#532). Factions (#483) load with their own names for the ranks of a
## standing, their symbols and the instances they hold (#637), and broken ones are refused. Quests
## and abilities carry path marks (#471). Dialogs
## (#618) load and read on line by line and answer by answer, state whether they lock and which
## answers commit (#891), and broken ones are refused; a region placing more people with locking
## dialogs than Dialog.MOST_LOCKING_PER_REGION is warned about in CI, without failing. Every
## text tag (#733) in a dialog, a quest's name or an ability's description names content that
## exists, shows its current name, and broken tags are refused; tags whose content can't be read
## are warned about (#949). No two things share an id or a name, whatever their kinds, in any case
## (#909). Every content kind is read ahead in the background (#816).

## A species file's speed, abilities (#222), name (#351) and strike type (#626), as a
## valid species ends.
const KIT: String = (
	", \"name\": \"Xo\", \"strike_type\": \"might\", \"speed\": 1,"
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
## A blueprint file x on the rule set small (#941), its last fields left open.
const BLUEPRINT: String = "{\"id\": \"x\", \"rules\": \"small\", \"wild_species\": {\"a\": 1}%s}"
## What ContentTerms says of a name that breaks its kind's shape.
const REFUSED: String = "isn't a name its kind allows"
## Each kind's name rule (#909) on names it allows ("" expected) and names it refuses (what the
## problem holds), as "<kind> <id> <name> <related>", with "-" for no name or no related.
const NAME_CASES: Dictionary[String, String] = {
	"species ombulumo Ombulumo growth": "",
	"special ombulumo_bulum_bolom Bulum-bolom ombulumo": "",
	"passive ombulumo_mulbo_lulbo Mulbo-lulbo ombulumo": "",
	"passive tikazzir_zirki_kirki Zirki-kirki tikazzir": "",
	"realm ardvaun - -": "",
	"instance dhorvone_stolm - -": "",
	"instance senwel_sael - -": "",
	"instance thudren_orl - -": "",
	"region lymwen_hoall - lumwen_hoal": "",
	"region dhyrvone_stolmm - dhorvone_stolm": "",
	"piece north_hold_of_lumwen_hoal - -": "",
	"place sealed_passage - -": "",
	"faction amvrel_velmarai Amvrel_Velmarai -": "",
	"person teska_na_amvrel Teska_na_Amvrel -": "",
	"person ardwe_vo_selin Ardwe_vo_Selin -": "",
	"unique kel_varun Kel'varun -": "",
	"gear berry_pouch Berry_pouch -": "",
	"species xo Xo_Xa -": REFUSED,
	"species zo Kiruzzi might": "its id must",
	"species kiruzzi Kiruzzi growth": REFUSED,
	"species kirdhuzi Kirdhuzi might": "Kirdhuzi has a land-speech sound",
	"special ombulumo_bulum_bulum Bulum-bulum ombulumo": REFUSED,
	"special ombulumo_tizik_tazak Tizik-tazak ombulumo": REFUSED,
	"passive ombulumo_mulbo_mulbo Mulbo-mulbo ombulumo": REFUSED,
	"passive tikazzir_tizik_tazak Tizik-tazak tikazzir": REFUSED,
	"realm zarvaun - -": "Zarvaun has a beast-call's letter",
	"realm Ardvaun - -": "its id must be lower case",
	"instance glade - -": REFUSED,
	"instance amvrel_hoal - -": "Amvrel Hoal has the faction word Amvrel",
	"region lumwen_hoal_corrupted - lumwen_hoal": REFUSED,
	"region lymwen_hoal - lumwen_hoal": REFUSED,
	"faction amvrel_velmar Amvrel_Velmar -": REFUSED,
	"person teska_na_selin Teska_na_Selin -": REFUSED,
	"unique zar_omera Zar'omera -": REFUSED,
	"gear kel_spikes Kel_spikes -": "Kel spikes has the unique word Kel",
	"gear bonsai Bonsai -": "Bonsai has a last word in -ai",
}
## A rule set file small (#941), its rules left open.
const RULE_SET: String = "{\"id\": \"small\", \"features\": [%s]}"


func run(tree: SceneTree) -> String:
	var content: SpeciesContent = SpeciesContent.load_species()
	if not content.problem.is_empty():
		return "the species data didn't load: " + content.problem
	if (not content.species.has("ombulumo")
			or content.species["ombulumo"].name != "Ombulumo"
			or content.species["tikazzir"].types.size() != 2
			or content.species["ombulumo"].strike_type != "growth"):
		return "the placeholder species didn't load as written"
	var checks: Array[Callable] = [
		_check_strip,
		_check_refused,
		_check_loot_rolls,
		_check_harvest_tables,
		_check_instance_tables,
		_check_loot_refused,
		_check_wild_species.bind(content),
		_check_blueprints,
		_check_rule_sets,
		_check_realms,
		_check_tiles,
		_check_quests,
		_check_factions,
		_check_dialogs,
		_check_dialogs_refused,
		_warn_locking_dialogs,
		_check_command_codes,
		_check_kits.bind(content),
		_check_text_tags,
		_check_text_tags_unread.bind(tree),
		_check_terms,
		_check_prefetched,
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
func _check_kits(content: SpeciesContent) -> String:
	var loaded: AbilityContent = AbilityContent.load_abilities()
	if not loaded.problem.is_empty():
		return "the abilities didn't load: " + loaded.problem
	var problem: String = SpeciesKit.problem(content.species, loaded.abilities)
	if not problem.is_empty():
		return "the species' abilities don't hold together: " + problem
	var finch: Species = content.species["tikazzir"]
	var toad: Species = content.species["ombulumo"]
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
	if (quests["three_ombulumo"].path != PathMark.SUPREMACY
			or quests["first_domination"].path != PathMark.NONE
			or abilities["tikazzir_tizik_tazak"].path != PathMark.SUPREMACY
			or abilities["ombulumo_bolmu_wolmu"].path != PathMark.NONE):
		return "the path marks didn't read as written"
	if quests["three_ombulumo"].shown_name() != "Dominate three Ombulumo (Supremacy)":
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
func _check_named_steps(content: QuestContent) -> String:
	var named: QuestDefinition = QuestDefinition.parse(
		"x",
		"{\"id\": \"x\", \"name\": \"N\", \"steps\": [%s, %s, %s]}" % [
			REACH % "beach",
			ENTER % "thicket",
			ENTER_INSTANCE % (FlowSteps.GLADE + "\", \"ends\": \"x"),
		],
		content.species,
	)
	if (not named.problem.is_empty()
			or named.steps[0].place != "beach"
			or named.steps[1].piece != "thicket"
			or named.steps[2].instance != FlowSteps.GLADE
			or not named.steps[2].piece.is_empty()):
		return "a step to reach or enter something didn't read: " + named.problem
	return ""


## Why steps naming an instance don't read, or "": a chest opened and a piece entered there, each
## counting only there (#769), and a step to enter it (#370). An instance that isn't an id or isn't
## a blueprint is refused, with a reason, and so is one on a start waiting on an event, which
## happens everywhere. Then the answered steps.
func _check_instance_steps(content: QuestContent) -> String:
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"steps\": [%s]}"
	var there: String = ", \"instance\": \"%s\"" % FlowSteps.GLADE
	var opened: String = "{\"condition\": \"opened\"%s}" % there
	var entered: String = ENTER % ("start\"" + there + ", \"ends\": \"x")
	var tied: QuestDefinition = QuestDefinition.parse(
		"x",
		quest % (opened + ", " + entered),
		content.species,
	)
	var piece: QuestStep = tied.steps[1] if tied.steps.size() == 2 else QuestStep.new()
	if (not tied.problem.is_empty() or tied.steps[0].instance != FlowSteps.GLADE
			or piece.instance != FlowSteps.GLADE or piece.piece != "start"
			or piece.enters_instance()
			or not piece.counts(
				QuestStep.ENTERED,
				"start",
				FlowSteps.GLADE,
			) or piece.counts(QuestStep.ENTERED, "start", "")
			or tied.steps[0].counts(QuestStep.OPENED, "", FlowSteps.FOREST)):
		return "steps counting only in the glade didn't read, or counted elsewhere: " + tied.problem
	var waiting: String = "{\"id\": \"x\", \"name\": \"N\", \"starts_on\": %s, \"steps\": [%s]}"
	var cases: Dictionary[String, String] = {
		quest % (ENTER_INSTANCE % "The Glade"): "step 0: its instance must be an id",
		waiting % ["{\"condition\": \"emitted\", \"event\": \"e\"%s}" % there, OPENED_END]: (
			"its start: its instance is where it counts"
		),
	}
	var problem: String = _unrefused(cases, content)
	return problem if not problem.is_empty() else _check_answered_steps(content)


## Why broken answered steps (#636) aren't refused, with a reason, or "": an answered step names a
## dialog and its answer, both, each an id, and no other step names either.
func _check_answered_steps(content: QuestContent) -> String:
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
func _check_side_quests(content: QuestContent) -> String:
	var pond: QuestDefinition = content.quests.get("pond_chest")
	var first: QuestDefinition = content.quests["first_domination"]
	if (pond == null or pond.starts_on == null or pond.starts_on.condition != QuestStep.ENTERED
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
## Amvrel Velmarai by one, the toads' quest moves none, and a standing that isn't an object,
## has another field, names no faction id, or changes by nothing, a fraction, text or more than the
## whole scale is refused.
func _check_quest_standings(content: QuestContent) -> String:
	var raised: QuestStanding = content.quests["first_domination"].standing
	if (raised == null or raised.faction != "amvrel_velmarai" or raised.change != 1
			or content.quests["three_ombulumo"].standing != null):
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
## faction, filed by the code a command hands it over by, starts once the player enters that
## instance and has every step count only there (#769, the ground rules in AGENTS.md), while the
## quests that aren't territory quests name none; a territory that isn't an object, has another
## field, or doesn't name an instance and a faction by their ids is refused, and so is a territory
## quest with a step that doesn't name its instance, or names another.
func _check_quest_territories(content: QuestContent) -> String:
	var handed: int = 0
	for id: String in content.quests:
		var territory: QuestTerritory = content.quests[id].territory
		if territory == null:
			continue
		var by: int = Territory.code(territory.instance, territory.faction)
		if not InstanceBlueprints.exists(territory.instance) or not content.handovers.has(by):
			return "%s hands over %s, which doesn't exist or isn't filed" % [id, territory.instance]
		var start: QuestStep = content.quests[id].starts_on
		if (start == null
				or start.condition != QuestStep.ENTERED
				or start.instance != territory.instance):
			return "%s doesn't start once the player enters %s" % [id, territory.instance]
		for step: QuestStep in content.quests[id].steps:
			if step.instance != territory.instance:
				return "%s has a step that doesn't count only in %s" % [id, territory.instance]
		handed += 1
	if handed == 0 or content.quests["first_domination"].territory != null:
		return "no quest hands a territory over, or the first domination does"
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"territory\": %s, \"steps\": [%s]}"
	var forest_name: String = FlowSteps.FOREST
	var forest: String = "{\"instance\": \"%s\", \"faction\": \"a\"}" % forest_name
	var unnamed: String = "step 0: a territory quest's steps name its instance " + forest_name
	var cases: Dictionary[String, String] = {
		quest % ["\"%s\"" % forest_name, OPENED_END]: "its territory: it isn't",
		quest % [forest.replace("}", ", \"by\": 1}"), OPENED_END]:
		"its territory: field by",
		quest % [forest.replace(forest_name, forest_name.capitalize()), OPENED_END]:
		"its territory: it names",
		quest % ["{\"instance\": \"%s\"}" % forest_name, OPENED_END]: "its territory: it names",
		quest % [forest, OPENED_END]: unnamed,
		quest % [forest, OPENED_END.replace("{", "{\"instance\": \"%s\", " % FlowSteps.GLADE)]: (
			"step 0: a territory quest's steps name"
		),
	}
	var problem: String = _unrefused(cases, content)
	return problem if not problem.is_empty() else _check_branches(content)


## Why branching quests (#573) don't read, or "": the glade's fork offers the pond and the thicket,
## each leading to its own step, and both end its chain. Choices that aren't two or more, aren't a
## place or an area, have a count, or lead nowhere are refused; so are a step with choices that has
## a condition or an end, two steps with one id, and an end naming another chain.
func _check_branches(content: QuestContent) -> String:
	var fork_id: String = "lumwen_hoal_fork"
	var fork: QuestDefinition = content.quests.get(fork_id)
	if (fork == null or fork.steps[0].choices.size() != 2
			or fork.steps[0].choices[0].piece != "pond"
			or fork.next_index(0, QuestStep.ENTERED, "thicket", "") != 2
			or fork.steps[1].ends != fork_id or fork.steps[2].ends != fork_id):
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
func _check_paths(content: QuestContent, quest: String, to: String) -> String:
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
static func _unrefused(cases: Dictionary[String, String], content: QuestContent) -> String:
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
## one of, never both, and the same for an answered step and its dialog and answer (#636), and a
## quest target (#625).
func _check_quests() -> String:
	var content: QuestContent = QuestContent.load_quests()
	if not content.problem.is_empty():
		return "the quests didn't load: " + content.problem
	var first: QuestDefinition = content.quests.get("first_domination")
	var toads: QuestDefinition = content.quests.get("three_ombulumo")
	if first == null or first.name.is_empty() or first.steps.size() != 2 or toads == null:
		return "the quests didn't load as written"
	if first.steps[0].condition != QuestStep.REACHED or first.steps[0].place != "beach":
		return "the first domination doesn't lead to the beach first"
	var any_domination: QuestStep = first.steps[1]
	var toad_step: QuestStep = toads.steps[0]
	if (any_domination.condition != QuestStep.DOMINATED
			or any_domination.quarry.species != null
			or any_domination.count != 1):
		return "the first domination isn't one domination of any species"
	var toad: Species = toad_step.quarry.species
	toad = toad if toad != null else Species.new()
	if toad.id != "ombulumo" or toad.name != "Ombulumo" or toad_step.count != 3:
		return "the toads' quest isn't three Ombulumo"
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
		quest % ["x", "N", "{\"condition\": \"opened\", \"species\": \"ombulumo\"}"]: (
			"step 0: its species"
		),
		quest % ["x", "N", step % "" + ", " + step % ", \"count\": 0"]: "step 1: its count",
		quest % ["x", "N", step % ", \"count\": 1.5"]: "step 0: its count",
		quest % ["x", "N", step % ", \"when\": 1"]: "step 0: field when",
		quest % ["x", "N", "7"]: "step 0: it isn't",
	}
	return _unrefused(cases, content) + _check_target_steps(content)


## Why a step asking for a quest target (#625) isn't read, or isn't refused when it's no id (an
## upper-case one, or one ending in a newline, #944), sits on a step other than a domination, comes
## with a species or counts more than once, or "".
func _check_target_steps(content: QuestContent) -> String:
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"steps\": [{\"condition\": \"%s\"%s}]}"
	var target: String = ", \"target\": \"%s\""
	var asked: String = quest % ["dominated", target % "old_toad" + ", \"ends\": \"x\""]
	var read: QuestDefinition = QuestDefinition.parse("x", asked, {})
	if not read.problem.is_empty() or read.steps[0].quarry.target != "old_toad":
		return "a step asking for the quest target old_toad didn't read: " + read.problem
	var cases: Dictionary[String, String] = {
		quest % ["dominated", target % "Old"]: "step 0: its target must",
		quest % ["dominated", target % "old\\n"]: "step 0: its target must",
		quest % ["opened", target % "old_toad"]: "step 0: its target",
		quest % ["dominated", target % "old_toad" + ", \"count\": 2"]: "step 0: its target",
		quest % ["dominated", target % "old_toad" + ", \"species\": \"ombulumo\""]: (
			"step 0: its target"
		),
	}
	return _unrefused(cases, content)


## Every tile blueprint file reads, its id matching its file; ground, water and rock are the
## built-in
## kinds and keep their walkability; the rules know every kind by its file's name (#802); forest,
## shrubs and a stump are walkable and a boulder isn't (#205), each with its model, and sand is
## plain and walkable (#321); every model a blueprint names exists; the stump is drawn at 400
## hundredths of its size (#588), every other kind at 100, the default; no two kinds share a symbol
## (#68). Broken blueprints are refused.
func _check_tiles() -> String:
	var content: TileContent = TileContent.load_tiles()
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
		if (not content.tiles.has(id) or TileKinds.is_walkable(id) != walkable[id]
				or content.tiles[id].model.is_empty() != plain.has(id)):
			return "tile blueprint %s is missing, not as walkable as written, or (un)decorated" % id
	for built_in: String in [Region.GROUND, Region.WATER, Region.BLOCKED]:
		if not content.tiles.has(built_in):
			return "the built-in tile kind %s has no tile blueprint" % built_in
	var symbols: Dictionary[String, String] = {}
	for tile: TileBlueprint in content.tiles.values():
		if not TileKinds.has(tile.id):
			return "the rules don't know tile blueprint %s by its file's name" % tile.id
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
	return _check_tiles_refused()


## Tile blueprints with a wrong id, color, symbol (#68), scale, crown (#232) or trait are
## refused, with a reason, and so is one still giving a number (#802); the largest scale is read,
## and so is a crown's reach and clearance.
func _check_tiles_refused() -> String:
	var tile: String = (
		"{\"id\": \"%s\", \"color\": \"%s\", \"symbol\": \"x\", "
		+ "\"traits\": {%s}%s}"
	)
	var walks: String = "\"walkable\": true"
	var cases: Dictionary[String, String] = {
		tile % ["y", "#000000", walks, ""]: "its id must",
		tile % ["x", "#000000", walks, ", \"number\": 9"]: "field number",
		tile % ["x", "green", walks, ""]: "its color",
		tile % ["x", "#000000", "", ""]: "its traits",
		tile % ["x", "#000000", walks + ", \"swims\": true", ""]: "field swims",
		tile % ["x", "#000000", walks, ", \"size\": 1"]: "field size",
		tile % ["x", "#000000", walks, ", \"scale\": 0"]: "its scale",
		tile % ["x", "#000000", walks, ", \"scale\": 401"]: "its scale",
		tile % ["x", "#000000", walks, ", \"scale\": 1.5"]: "its scale",
		tile % ["x", "#000000", walks, ", \"scale\": \"2\""]: "its scale",
		tile % ["x", "#000000", walks, ", \"reach\": 9"]: "its reach",
		tile % ["x", "#000000", walks, ", \"clearance\": -1"]: "its reach",
		tile.replace(", \"symbol\": \"x\"", "") % ["x", "#000000", walks, ""]: "its symbol",
		tile.replace("\"x\", ", "\"xy\", ") % ["x", "#000000", walks, ""]: "its symbol",
	}
	for text: String in cases:
		var problem: String = TileBlueprint.parse("x", text).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var largest: TileBlueprint = TileBlueprint.parse("x", tile % ["x", "#000000", walks,
			", \"scale\": 400"])
	if not largest.problem.is_empty() or largest.scale != TileBlueprint.MAX_SCALE:
		return "the largest scale is refused or misread: %s" % largest.problem
	var crown: TileBlueprint = TileBlueprint.parse("x", tile % ["x", "#000000", walks,
			", \"reach\": 1, \"clearance\": 40"])
	if (not crown.problem.is_empty()
			or crown.reach != 1
			or crown.clearance != 40):
		return "a crown's reach or clearance is refused or misread: %s" % crown.problem
	return ""


## Every blueprint lists the species its unnamed spots roll from, and every species a blueprint
## lists or a region piece of its own or of a variant's region names is one the species data has
## (#133, #953). A variant region naming a species the data lacks is refused.
func _check_wild_species(content: SpeciesContent) -> String:
	for instance_name: String in InstanceBlueprints.names():
		var problem: String = _wild_species_problem(instance_name, content.species)
		if not problem.is_empty():
			return problem
	var lacking: Dictionary[String, Species] = content.species.duplicate()
	var _gone: bool = lacking.erase("tikazzir")
	var refused: String = _wild_species_problem(FlowSteps.GLADE, lacking)
	var expected: String = "%s places a species that doesn't exist: tikazzir" % (
		FlowSteps.CORRUPTED_GLADE
	)
	if not refused.ends_with(expected):
		return "the glade's corrupted variant naming an unknown species wasn't refused: " + refused
	return ""


## Why the named blueprint's wild species don't all exist in `species`, or "": the ones it lists
## and the ones its own region and each variant's region name.
func _wild_species_problem(instance_name: String, species: Dictionary[String, Species]) -> String:
	var listed: Dictionary = InstanceBlueprints.blueprint(instance_name).wild_species
	if listed.is_empty():
		return "the %s blueprint lists no species for its wild monsters" % instance_name
	for named: Variant in listed:
		if not species.has(str(named)):
			return "%s lists a species that doesn't exist: %s" % [instance_name, named]
	var regions: Array[String] = [""]
	for chosen_by: PackedStringArray in InstanceBlueprints.blueprint(instance_name).variants:
		if not chosen_by[1].is_empty():
			regions.append(chosen_by[1])
	for variant_name: String in regions:
		var region: Region = InstanceBlueprints.region_of(instance_name, 0, variant_name)
		for meaning: String in region.placed(WildSpotPlacements.KIND).values():
			var named: String = WildSpot.read(meaning).species
			if not species.has(named):
				return "%s's region %s places a species that doesn't exist: %s" % [
					instance_name,
					variant_name if not variant_name.is_empty() else instance_name,
					named,
				]
	return ""


## The glade's blueprint reads as written (#823): its rules, loot tables and variants in their
## order. What its region holds brings the rest (#879): its people only to the glade itself, its
## chests to its corrupted variant too, through its chest table. A blueprint file with a wrong id,
## an unknown field, no species, a weight below 1, a chest table without a loot table, or a variant
## without its region is refused.
func _check_blueprints() -> String:
	var glade: Blueprint = InstanceBlueprints.blueprint(FlowSteps.GLADE)
	if glade == null or glade.loot_table != "glade" or glade.chest_table != "glade_chest":
		return "the glade's blueprint didn't load as written"
	if glade.features[0] != MovementFeature.ID or glade.features.has(ChestFeature.ID):
		return "the glade's features read %s" % [glade.features]
	var own: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 0, 0)
	var corrupted: GameState = InstanceBlueprints.create(
		FlowSteps.GLADE,
		0,
		0,
		FlowSteps.CORRUPTED_GLADE,
	)
	if (
		own.feature(NpcFeature.ID) == null
		or corrupted.feature(NpcFeature.ID) != null
		or corrupted.feature(ChestFeature.ID) == null
	):
		return "the glade's region didn't bring its people and chests"
	var first: PackedStringArray = (
		glade.variants[0] if not glade.variants.is_empty() else PackedStringArray()
	)
	if first != PackedStringArray([WorldFlags.EVENT_FLAG + FlowSteps.GLADE_PURIFIED, ""]):
		return "the glade's variants read %s" % [glade.variants]
	return _blueprints_refused({
		BLUEPRINT.replace("\"x\"", "\"y\"") % "": "its id must",
		BLUEPRINT % ", \"z\": 1": "field z",
		BLUEPRINT.replace("\"a\": 1", "") % "": "its wild_species",
		BLUEPRINT.replace("\"a\": 1", "\"a\": 0") % "": "its wild_species",
		BLUEPRINT % ", \"chest_table\": \"c\"": "a blueprint with a chest table",
		BLUEPRINT % ", \"variants\": [{\"flag\": \"f\"}]": "its variants",
		BLUEPRINT % ", \"turned\": 1": "turned must",
	})


## A blueprint's rules are its rule set's, less the ones it drops, then the ones it adds (#941). A
## blueprint naming an unknown rule set, dropping a rule its set lacks, adding one it has, an
## unknown or repeated rule or one its region brings, or leaving no rule is refused, and so is a
## rule set file with a wrong id, no rule, or an unknown, repeated or region-brought one.
func _check_rule_sets() -> String:
	var changed: Blueprint = Blueprint.parse(
		"x",
		BLUEPRINT % ", \"drop_rules\": [\"fog\"], \"add_rules\": [\"movement\", \"trail\"]",
		_small_rule_set(),
	)
	if PackedStringArray(changed.features) != PackedStringArray(["movement", "trail"]):
		return "a blueprint dropping and adding rules read %s" % [changed.features]
	var set_cases: Dictionary[String, String] = {
		RULE_SET.replace("small", "big") % "\"fog\"": "its id must",
		RULE_SET % "": "its features",
		RULE_SET % "\"flying\"": "its features",
		RULE_SET % "\"fog\", \"fog\"": "its features",
		RULE_SET % "\"exits\"": "its features",
	}
	for text: String in set_cases:
		var refused: String = RuleSet.parse("small", text).problem
		if not refused.begins_with(set_cases[text]):
			return "a broken rule set gave %s, not %s" % [refused, set_cases[text]]
	return _blueprints_refused({
		BLUEPRINT.replace("small", "big") % "": "its rules must be",
		BLUEPRINT % ", \"drop_rules\": [\"fog\"]": "its rules must leave",
		BLUEPRINT % ", \"drop_rules\": [\"trail\"]": "its drop_rules",
		BLUEPRINT % ", \"drop_rules\": [\"flying\"]": "its drop_rules",
		BLUEPRINT % ", \"add_rules\": [\"fog\"]": "its add_rules",
		BLUEPRINT % ", \"add_rules\": [\"flying\"]": "its add_rules",
		BLUEPRINT % ", \"add_rules\": [\"trail\", \"trail\"]": "its add_rules",
		BLUEPRINT % ", \"add_rules\": [\"exits\"]": "its add_rules",
	})


## Why a blueprint file in `cases` wasn't refused with the reason it maps to, read against
## _small_rule_set, or "".
func _blueprints_refused(cases: Dictionary[String, String]) -> String:
	for text: String in cases:
		var refusal: String = Blueprint.parse("x", text, _small_rule_set()).problem
		if not refusal.begins_with(cases[text]):
			return "a broken blueprint gave %s, not %s" % [refusal, cases[text]]
	return ""


## The rule set "small", holding only fog, by its id.
func _small_rule_set() -> Dictionary[String, RuleSet]:
	return { "small": RuleSet.parse("small", RULE_SET % "\"fog\"") }


## Every realm file (#865) reads, found by listing its folder, and draws instances that exist,
## each once, whose regions read, so every exit leads to the instance drawn beside it on that side.
## The realms mark one start, the glade (#712). A realm file drawing an instance twice, with a
## symbol its legend doesn't explain, marking two starts or one it doesn't draw, or without its
## codex entry and gloss (#959) is refused.
func _check_realms() -> String:
	var starts: Array[String] = []
	for realm: Realm in Realms.all():
		if not realm.problem.is_empty() or realm.instances.is_empty():
			return "realm %s didn't read: %s" % [realm.id, realm.problem]
		for instance_id: String in realm.instances.values():
			if not InstanceBlueprints.exists(instance_id):
				return "realm %s draws %s, which doesn't exist" % [realm.id, instance_id]
			var problem: String = InstanceBlueprints.region_of(instance_id, 0).problem
			if not problem.is_empty():
				return "realm %s's %s didn't read: %s" % [realm.id, instance_id, problem]
		if not realm.start.is_empty():
			starts.append(realm.start)
	if starts != [FlowSteps.GLADE] or Realms.start() != FlowSteps.GLADE:
		return "the realms mark %s as the start" % [starts]
	var text: String = "# R\n\n## Tiles\n\n```\n%s\n```\n\n## Legend\n\n- `🌲`: the instance %s\n"
	text += "- `🟦`: no instance\n"
	var forest: String = FlowSteps.FOREST
	var start: String = forest + RealmDocument.START
	var glade_start: String = "- `🌳`: the instance %s, where the players start\n" % FlowSteps.GLADE
	var cases: Dictionary[String, String] = {
		text % ["🌲🌲🌲", forest]: "the instance %s is drawn twice" % forest,
		text % ["⬜🌲⬜", forest]: "the legend doesn't explain `⬜`",
		text % ["🟦🌲🌳", start] + glade_start: (
			"the players start in %s and %s" % [forest, FlowSteps.GLADE]
		),
		text % ["🟦🌲🟦", forest] + glade_start: (
			"the players start in %s, which isn't drawn" % FlowSteps.GLADE
		),
		text % ["🟦🌲🟦", forest] + "\n## Codex\n\n- Gloss: g\n": (
			"its codex entry and gloss are missing under %s (#959)" % RealmDocument.CODEX
		),
	}
	for case: String in cases:
		var refusal: String = RealmDocument.parse(case).problem
		if refusal != cases[case]:
			return "a broken realm gave %s, not %s" % [refusal, cases[case]]
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


## Why a species file named xo with this text is refused in otherwise empty content, or "".
func _add_to_empty(text: String) -> String:
	return SpeciesContent.new().add("xo", text)


## Entries a schema might let through or that clash with others are refused, with a reason.
func _check_refused() -> String:
	var cases: Dictionary[String, String] = {
		"{\"id\": \"other\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1}": "its id",
		# Mana and Arcane are one family's two types.
		"{\"id\": \"xo\", \"types\": [\"mana\", \"arcane\"], \"hp\": 1, \"strength\": 1}": (
			"type arcane"
		),
		"{\"id\": \"xo\", \"types\": [\"fire\"], \"hp\": 1, \"strength\": 1}": "type fire",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1.5, \"strength\": 1}": "hp and strength",
		"{\"id\": \"xo\", \"types\": [], \"hp\": 1, \"strength\": 1}": "a species has one",
		"{\"id\": 7, \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1}": "its id must match",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1, \"y\": 1}": "field y",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1}": "speed is",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("might", "fire") + "}": "its strike type",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"a_special\"", "7") + "}": "it names a special",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"name\": \"Xo\", ", "") + "}": "it needs a name",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"Xo\"", "\" \"") + "}": "it needs a name",
		# A description isn't a name (#717): two words, or small letters only.
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"Xo\"", "\"Moss Toad\"") + "}": "it needs a name",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"Xo\"", "\"xo\"") + "}": "it needs a name",
		# Its id is its name in lower case (#763).
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"Xo\"", "\"Zo\"") + "}": "its id must be its name",
	}
	for text: String in cases:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var twice: SpeciesContent = SpeciesContent.new()
	var valid: String = "{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
	valid += KIT + "}"
	var first: String = twice.add("xo", valid)
	if not first.is_empty() or not twice.add("xo", valid).begins_with("its id"):
		return "a second species with the same id was accepted"
	return ""


## The placeholder tables load. A roll on the toad's table gives 2 to 4 berries, or on its blank
## what the glade's table gives (1 to 2 moss, a single berry or a single revive herb, #656), and the
## same stream rolls the same loot.
func _check_loot_rolls() -> String:
	var content: LootContent = LootContent.load_loot_tables()
	if not content.problem.is_empty():
		return "the loot tables didn't load: " + content.problem
	var toad: LootTable = content.loot_tables["ombulumo"]
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
	return _check_revive_herbs(content)


## The glade's own rolls and its chests' give a revive herb (#656) now and then.
func _check_revive_herbs(content: LootContent) -> String:
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


## Every species has its own harvest table (#687) and its own domination loot table (#943), so
## neither a felled nor a dominated one drops nothing: each loads as a table of its kind named after
## a species, and a felled toad's rolls give what dominating it never does.
func _check_harvest_tables() -> String:
	var content: LootContent = LootContent.load_loot_tables(LootContent.HARVEST_DIR)
	if not content.problem.is_empty():
		return "the harvest tables didn't load: " + content.problem
	var species: SpeciesContent = SpeciesContent.load_species()
	for species_id: String in species.species:
		var table: LootTable = content.loot_tables.get(species_id)
		if table == null or table.kind != LootTable.HARVEST:
			return "%s has no harvest table" % species_id
		if LootContent.table_for(species_id, LootTable.SPECIES) == null:
			return "%s has no domination loot table" % species_id
	var toad: LootTable = content.loot_tables["ombulumo"]
	var dominated: LootTable = LootContent.load_loot_tables().loot_tables["ombulumo"]
	for seed_value: int in 100:
		for item: String in _roll(toad, null, seed_value):
			if dominated.items.has(item):
				return "a felled toad dropped %s, which dominating it gives" % item
	return ""


## Every blueprint whose rules roll a species' table names an instance table that loads (#943), so
## a blank rolled in it is never nothing (#90), and its instance's rolling features hold that table
## and every species' table of their kind.
func _check_instance_tables() -> String:
	var species: Array[String] = []
	species.assign(SpeciesContent.load_species().species.keys())
	var rolling: Array[String] = [DominationLootFeature.ID, HarvestFeature.ID]
	for instance_name: String in InstanceBlueprints.names():
		var named: Blueprint = InstanceBlueprints.blueprint(instance_name)
		var rolls: bool = rolling.any(func(rule: String) -> bool: return named.features.has(rule))
		if rolls and LootContent.table_for(named.loot_table, LootTable.INSTANCE) == null:
			return "%s rolls loot but has no instance loot table" % instance_name
		var state: GameState = InstanceBlueprints.create(instance_name, 0, 0)
		for rule: String in rolling:
			var feature: SpeciesLootFeature = state.feature(rule) as SpeciesLootFeature
			if feature == null:
				continue
			var tabled: bool = species.all(func(id: String) -> bool: return feature.tables.has(id))
			if feature.instance_table == null or not tabled:
				return "%s's %s misses its instance's or a species' table" % [instance_name, rule]
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


## The factions load, each with its own name for every rank but neutral (#483): the Amvrel
## Velmarai's (#484) run from Apprentice Charter up to Charted in Legend and from Betrayer down. A
## faction file with a wrong id, no name, an unknown field, or not five rank names with more than
## spaces each way is refused.
func _check_factions() -> String:
	var content: FactionContent = FactionContent.load_factions()
	if not content.problem.is_empty() or not content.factions.has("amvrel_velmarai"):
		return "the factions didn't load: " + content.problem
	var guild: Faction = content.factions["amvrel_velmarai"]
	var names: Array[String] = []
	for standing: int in [Standings.LOWEST, -1, 0, 1, Standings.HIGHEST]:
		names.append(guild.rank_name(standing))
	var expected: Array[String] = [
		"Edge of the Chart", "Betrayer", "", "Apprentice Charter", "Charted in Legend",
	]
	if names != expected:
		return "the Amvrel Velmarai's ranks read %s" % [names]
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


## The Amvrel Velmarai is marked by its symbol and holds the glade, where the player starts
## (#637, #712), when a world starts, and every faction's territory names instance blueprints that
## exist. A faction file without a symbol, with a longer one, or with a territory that isn't a list
## of instance ids, each once, is refused, and so are two factions holding one instance or sharing a
## symbol.
func _check_faction_territory(content: FactionContent) -> String:
	var guild: Faction = content.factions["amvrel_velmarai"]
	if guild.symbol != "+" or " ".join(guild.territory) != FlowSteps.GLADE:
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
		territory % ("\"%s\"" % FlowSteps.BASIC): "its territory must",
		territory % ("[\"%s\"]" % FlowSteps.BASIC.capitalize()): "its territory must",
		territory % ("[\"%s\", \"%s\"]" % [FlowSteps.BASIC, FlowSteps.BASIC]): "its territory must",
	})
	if not refused.is_empty():
		return refused
	var held: String = territory % ("[\"%s\"]" % FlowSteps.BASIC)
	var twice: String = _pair_problem(held, held)
	if not twice.contains(FlowSteps.BASIC + " is x's territory already"):
		return "two factions holding one instance gave %s" % twice
	var shared: String = _pair_problem(held, territory % ("[\"%s\"]" % FlowSteps.GLADE))
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


## The dialogs load (#618): Teska na Amvrel's greeting reads on from its first line to its second,
## where asking about Lumwen Hoal leads to the line about it and the farewell ends it, as that
## line's only answer does too. An answer the line doesn't offer leads nowhere. The greeting doesn't
## lock, and only the promise, which a quest may count, commits (#891).
func _check_dialogs() -> String:
	var content: DialogContent = DialogContent.load_dialogs()
	if not content.problem.is_empty() or not content.dialogs.has("teska_na_amvrel_greeting"):
		return "the dialogs didn't load: " + content.problem
	var greeting: Dialog = content.dialogs["teska_na_amvrel_greeting"]
	var walked: Array[int] = [
		greeting.after(0),
		greeting.after(1, "ask_about_lumwen_hoal"),
		greeting.after(1, "leave_scout"),
		greeting.after(2, "promise_to_look"),
		greeting.after(1, "no_such_answer"),
		greeting.after(0, "ask_about_lumwen_hoal"),
	]
	if greeting.speaker != "Teska na Amvrel" or walked != [1, 2, -1, -1, -1, -1]:
		return "Teska na Amvrel's greeting reads %s, by %s" % [walked, greeting.speaker]
	var commits: Array[bool] = []
	for answer_id: String in ["ask_about_lumwen_hoal", "leave_scout", "promise_to_look"]:
		commits.append(greeting.answer_of(answer_id).commits)
	if greeting.lock or commits != [false, false, true]:
		return "the greeting's lock reads %s and its answers commit %s" % [greeting.lock, commits]
	return ""


## Prints a CI warning (#891), without failing, for every instance whose region places more people
## with locking dialogs than Dialog.MOST_LOCKING_PER_REGION: locking dialogs are for rare story
## beats.
func _warn_locking_dialogs() -> String:
	var dialogs: Dictionary[String, Dialog] = DialogContent.load_dialogs().dialogs
	for instance_name: String in InstanceBlueprints.names():
		var state: GameState = InstanceBlueprints.create(instance_name, 0, 0)
		var people: NpcFeature = state.feature(NpcFeature.ID) as NpcFeature
		var locking: int = 0
		if people != null:
			for spot: NpcSpot in people.spots.values():
				var dialog: Dialog = dialogs.get(spot.dialog)
				locking += 1 if dialog != null and dialog.lock else 0
		if locking > Dialog.MOST_LOCKING_PER_REGION:
			# A CI warning annotation on stdout, which GitHub shows without failing the run.
			# gdstyle:ignore=quality/no-debug-print
			print("::warning::%s places %d people with locking dialogs, more than %d (#891)" % [
				instance_name, locking, Dialog.MOST_LOCKING_PER_REGION,
			])
	return ""


## Dialog files with a wrong id, no speaker or lines, a line without text, an answer without an id,
## two lines or answers sharing an id, or an answer leading to no line are refused (#618), and so
## are one that doesn't state whether it locks, or an answer whose commits isn't true or false
## (#891), and one that holds its player (it locks, or a committing answer leads on) up to a last
## line without answers, which would hold them forever (#1014), and one with a line nothing leads
## to from its first (#1029).
func _check_dialogs_refused() -> String:
	var dialog: String = "{\"id\": \"x\", \"speaker\": \"S\", \"lock\": false, \"lines\": [%s]}"
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
		dialog.replace("\"lock\": false, ", "") % "{\"text\": \"T\"}": "it must state lock",
		dialog.replace("false", "1") % "{\"text\": \"T\"}": "it must state lock",
		dialog % (line % "{\"id\": \"b\", \"text\": \"T\", \"commits\": 1}"): (
			"line 0: answer b's commits"
		),
		dialog.replace("false", "true") % "{\"text\": \"T\"}, {\"text\": \"Farewell\"}": (
			"line 1: it holds its player"
		),
		dialog % ("%s, {\"id\": \"c\", \"text\": \"Farewell\"}" % (line % (
			answer.replace("\"T\",", "\"T\", \"commits\": true,") % ["b", "c"]
		))): "line 1: it holds its player",
		dialog % ("%s, {\"text\": \"Unread\"}" % (line % (answer % ["b", "a"]))): (
			"line 1: nothing leads to it"
		),
	}
	for text: String in cases:
		var refusal: String = Dialog.parse("x", text).problem
		if not refusal.begins_with(cases[text]):
			return "a broken dialog gave %s, not %s" % [refusal, cases[text]]
	return ""


## Command codes (#818): no id's code is CommandCodes.NONE, and filing one refuses NONE and a code
## another value holds, while the same value filed again is kept.
func _check_command_codes() -> String:
	var by_code: Dictionary[int, String] = {}
	var filed: Array[bool] = [
		CommandCodes.file(by_code, CommandCodes.of("a"), "a"),
		CommandCodes.file(by_code, CommandCodes.of("a"), "a"),
		CommandCodes.file(by_code, CommandCodes.of("a"), "b"),
		CommandCodes.file(by_code, CommandCodes.of(""), ""),
	]
	if filed != [true, true, false, false] or by_code.size() != 1:
		return "filing command codes gave %s, kept %s" % [filed, by_code]
	if CommandCodes.of("") != CommandCodes.NONE or CommandCodes.of("a") == CommandCodes.NONE:
		return "an id's command code is NONE, or no id's isn't"
	return ""


## Every text tag (#733) in the texts that show them (a dialog's speaker, lines and answers, a
## quest's name, an ability's name and description, a faction's name and ranks, a piece of gear's
## name, #752) names content that exists, and shows its current name;
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
	for ability: Ability in AbilityContent.load_abilities().abilities.values():
		texts.append_array([ability.name, ability.description])
	for faction: Faction in FactionContent.load_factions().factions.values():
		texts.append(faction.name)
		texts.append_array(faction.ranks_up + faction.ranks_down)
	for item: GearItem in GearContent.load_gear().items.values():
		texts.append(item.name)
	for text: String in texts:
		if not tags.problem_in(text).is_empty():
			return "the text \"%s\" has a broken tag: %s" % [text, tags.problem_in(text)]
	var greeting: Dialog = DialogContent.load_dialogs().dialogs["teska_na_amvrel_greeting"]
	var ahead: String = greeting.lines[2].text
	if not TextTags.shown(ahead).begins_with("Lumwen Hoal, thick with Ombulumo. Something"):
		return "the scout's Lumwen Hoal line shows %s" % TextTags.shown(ahead)
	var shown: String = tags.resolve("${FACTION:amvrel_velmarai} sells ${GEAR:berry_pouch}")
	if shown != "Amvrel Velmarai sells Berry pouch":
		return "faction and gear tags show %s" % shown
	var fang: GearItem = GearItem.new()
	fang.name = "${MONSTER:ombulumo} fang"
	fang.rarity = "loose"
	if fang.described() != "Ombulumo fang (Loose)":
		return "a gear name's tag shows as %s" % fang.described()
	var cases: Dictionary[String, String] = {
		"${BEAST:ombulumo}": "its kind must be one of",
		"${MONSTER:no_such_toad}": "no MONSTER has the id no_such_toad",
		"${MONSTER:Moss Toad}": "a tag is written",
		"${MONSTER:ombulumo": "a tag is written",
	}
	for text: String in cases:
		if not tags.problem_in(text).contains(cases[text]):
			return "the broken tag %s wasn't refused: %s" % [text, tags.problem_in(text)]
	return ""


## Text tags whose content can't be read are warned about, and show as written (#949).
func _check_text_tags_unread(tree: SceneTree) -> String:
	# The factions' files, read as species, are a species directory that can't be read.
	TextTags.read_species_from(FactionContent.DIR)
	tree.call("expect_warning", "the text tags' names can't be read")
	var unread: String = TextTags.shown("${MONSTER:ombulumo}")
	TextTags.read_species_from(SpeciesContent.DIR)
	if unread != "${MONSTER:ombulumo}":
		return "a tag shows %s when its content can't be read" % unread
	return ""


## No two things in the content share an id or a name (#909), but those ContentTerms lists, and each
## keeps to its kind's name rule but those it lists. Two things sharing one in another case are
## refused, a thing whose id is its name isn't, a listed term that no longer clashes must be
## dropped, and a known duplicate holds for its two things only. The adopted names keep their kinds'
## rules, and names breaking one, or with another kind's mark, are refused.
func _check_terms() -> String:
	var problem: String = ContentTerms.collected().problem()
	if not problem.is_empty():
		return "the content's terms don't hold together: " + problem
	var none: Dictionary[String, int] = {}
	var terms: ContentTerms = ContentTerms.new()
	terms.add("species", "kiruzzi", "Kiruzzi", "might")
	terms.add("faction", "odun_selai", "Odun Selai")
	if not terms.problem(none, none).is_empty():
		return "a species and a faction whose ids are their names were refused"
	terms.add("gear", "kiruzzi_pouch", "KIRUZZI")
	if not terms.problem(
		none,
		none,
	).begins_with("kiruzzi names species kiruzzi and gear kiruzzi_pouch"):
		return "a gear's name that's a species' id in capitals wasn't refused"
	var gone: Dictionary[String, int] = { "kiruzzi": 909, "zo": 909 }
	if not terms.problem(gone, none).begins_with("KNOWN_DUPLICATES' zo"):
		return "a known duplicate that no longer clashes wasn't refused"
	var known: Dictionary[String, int] = { "kiruzzi": 909 }
	terms.add("item", "kiruzzi")
	if not terms.problem(
		known,
		none,
	).begins_with("kiruzzi names species kiruzzi and gear kiruzzi_pouch and item kiruzzi"):
		return "a third thing sharing a known duplicate wasn't refused"
	return _check_name_rules()


## Each kind's name rule (#909) on NAME_CASES.
func _check_name_rules() -> String:
	var cases: Dictionary[String, String] = NAME_CASES
	var named: ContentTerms = ContentTerms.new()
	for entry: String in cases:
		var parts: PackedStringArray = entry.split(" ")
		var given: String = "" if parts[2] == "-" else parts[2].replace("_", " ")
		named.add(
			parts[0],
			parts[1].replace("_of_", " of "),
			given,
			"" if parts[3] == "-" else parts[3],
		)
	for entry: String in cases:
		var parts: PackedStringArray = entry.split(" ")
		var found: String = named.broken["%s %s" % [parts[0], parts[1].replace("_of_", " of ")]]
		var expected: String = cases[entry]
		if not found.is_empty() if expected.is_empty() else not found.contains(expected):
			return "the name rule on %s gave %s" % [
				entry,
				found if not found.is_empty() else "nothing",
			]
	return ""


## Every content kind is read ahead in the background (#816, InstanceContent.kinds): each directory
## a `<Kind>Content` reads (its constants ending in DIR) is one of the kinds' keys. Region files
## are read per region (RegionFiles), so they're not a kind.
func _check_prefetched() -> String:
	var keys: Array[String] = InstanceContent.kinds().keys()
	for named: Dictionary in ProjectSettings.get_global_class_list():
		if named["base"] != &"Content" or named["class"] == &"RegionFiles":
			continue
		var path: String = named["path"]
		var constants: Dictionary = (load(path) as Script).get_script_constant_map()
		for constant: String in constants:
			if constant.ends_with("DIR") and not keys.has(constants[constant]):
				return "%s's %s isn't read ahead (InstanceContent.kinds)" % [
					named["class"],
					constant,
				]
	return ""
