extends RefCounted
## Content flow (#72): the game's content data loads, and holds together where a schema can't
## check it. Every species file reads, with comments stripped; ids are unique and match their file;
## types come from the type chart, never two from one family; every species has a name for the
## player (#351), one invented word (#717), behaviour traits that can form a daily schedule
## (#1200: exactly one sleep rhythm, at least one need) and a model that exists (#1223), and one
## that ascends (#1252) ascends into another species, never in a loop, with a material the tables
## drop and a recipe makes (#1349); and broken entries are refused, broken recipes too. Every
## species has a development web (#677), whose nodes
## open as the ones next to them are taken and grant a leaning, a stronger special or a passive no
## species has (#1404), and broken webs are refused. Loot tables (#90) load,
## roll the same for the same stream, and a blank rolls on the instance's table; every item a table
## names is a piece of gear or a material (#774). Every piece of gear has a model that exists
## (#1581).
## Tile blueprints (#116) load, the built-in ones with the traits regions always had, and broken
## ones are refused. Quests (#184) load with the steps they're written with, name only
## species that exist, side quests name the area they start in (#473), choices lead to steps of
## their quest and ends close its own chain (#573), every path reaches an end (#576), and broken
## ones are refused; a quest can move the standing with a faction (#532). Factions (#483) load with
## their own names for the ranks of a standing, their symbols and the instances they hold (#637),
## and broken ones are refused. Quests and abilities carry path marks (#471). People (#1005) load
## with their names and codex entries, and every person a legend places is one, speaking the dialog
## it opens; broken ones are refused. Dialogs (#618) load, spoken by a person, and read on line by
## line and answer by answer, state whether they lock and which answers commit (#891), and broken
## ones are refused; a region placing more people with locking dialogs than
## Dialog.MOST_LOCKING_PER_REGION is warned about in CI, without failing. Every text tag (#733) in a
## dialog, a quest's name or an ability's description names content that exists, shows its current
## name, and broken tags are refused; tags whose content can't be read are warned about (#949). No
## two things share an id or a name, whatever their kinds, in any case (#909). Every content kind is
## read ahead in the background (#816).

## A model a species can wear (#1223).
const MODEL: String = "res://assets/mana-wolf/mana_wolf.glb"
## The tile blueprints whose pack's model is drawn larger, in hundredths: too small to read
## from the camera as the pack made it.
const SCALED: Dictionary[String, int] = { "stump": 400, "cracked_rock": 350, "rubble": 400 }
## A species file's speed, abilities (#222), name (#351), strike type (#626), codex entry (#1173),
## behaviour traits (#1200) and model (#1223), as a valid species ends.
const KIT: String = (
	", \"name\": \"Xo\", \"strike_type\": \"might\", \"speed\": 1,"
	+ " \"special\": \"a_special\", \"player_passive\": \"a_passive\","
	+ " \"self_passive\": \"its_passive\", \"codex\": {\"entry\": \"e\", \"gloss\": \"g\"},"
	+ " \"behaviour\": [\"diurnal\", \"grazer\"], \"model\": \"" + MODEL + "\""
)
## A valid species file's start, before its KIT.
const XO: String = "{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
## A species file's ascension (#1252), after its KIT: into which species and at what level left
## open.
const ASCENSION: String = (
	", \"ascension\": {\"into\": \"%s\", \"level\": %s, \"material\": \"m\"}"
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
## A faction file x with a symbol (#637) and a codex entry (#959), its ranks up and down left open
## (#483).
const FACTION_TEXT: String = (
	"{\"id\": \"x\", \"name\": \"X\", \"symbol\": \"+\", \"ranks_up\": %s, \"ranks_down\": %s, "
	+ "\"codex\": {\"entry\": \"e\", \"gloss\": \"g\"}}"
)
## Five rank names, as a faction has each way.
const FIVE_RANKS: String = "[\"a\", \"b\", \"c\", \"d\", \"e\"]"
## A blueprint file x on the rule set small (#941) with a codex entry (#1175), its last fields left
## open.
const BLUEPRINT: String = (
	"{\"id\": \"x\", \"rules\": \"small\", \"wild_species\": {\"a\": 1}, "
	+ "\"codex\": {\"entry\": \"e\", \"gloss\": \"g\"}%s}"
)
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
			or content.species["ombulumo"].strike_type != "growth"
			or content.species["ombulumo"].behaviour != ["nocturnal", "grazer", "drinker"]):
		return "the placeholder species didn't load as written"
	var checks: Array[Callable] = [
		_check_strip,
		_check_refused,
		_check_behaviour_refused,
		_check_model_refused,
		_check_ascensions.bind(content),
		_check_ascension_habitats.bind(content),
		_check_ascension_quests.bind(content),
		_check_ascensions_refused,
		_check_development_webs.bind(content),
		_check_development_refused,
		_check_loot_rolls,
		_check_harvest_tables,
		_check_instance_tables,
		_check_loot_refused,
		_check_loot_items,
		_check_wild_species.bind(content),
		_check_blueprints,
		_check_rule_sets,
		_check_realms,
		_check_tiles,
		_check_quests,
		_check_factions,
		_check_people,
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
		ability.replace("}", ", \"channel_seconds\": 2}") % ["x", "self_passive", "N"]: (
			"a special has a power, a cooldown and a strike"
		),
		special.replace("}", ", \"channel_seconds\": 0}") % ["x", "special", "N"]: (
			"a special's hold"
		),
	}
	for text: String in cases:
		var problem: String = Ability.parse("x", text).problem
		if not problem.begins_with(cases[text]):
			return "expected an ability refusal starting %s, got: %s" % [cases[text], problem]
	var read: Ability = Ability.parse("x", special % ["x", "special", "N"])
	if (not read.problem.is_empty() or read.power != 3000 or read.cooldown_seconds != 8
			or read.strike_type != "titan"):
		return "a special's power, cooldown and strike type didn't read: " + read.problem
	var held: Ability = Ability.parse(
		"x",
		special.replace("}", ", \"channel_seconds\": 3}") % ["x", "special", "N"],
	)
	if not held.problem.is_empty() or held.channel_seconds != 3 or read.channel_seconds != 0:
		return "a special's hold didn't read (#1163): " + held.problem
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
	return problem if not problem.is_empty() else _check_quest_alignment(content)


## Why the alignment quests enforce (#1326) doesn't read, or "": a floor and a ceiling read for two
## factions, while an alignment that isn't a list, is empty, has an entry that isn't an object, has
## another field, names no faction id or one that doesn't exist, sets no bound, a bound off the
## scale
## or a fraction, a floor above its ceiling, or names a faction twice is refused.
func _check_quest_alignment(content: QuestContent) -> String:
	var quest: String = "{\"id\": \"x\", \"name\": \"N\", \"alignment\": %s, \"steps\": [%s]}"
	var both: String = (
		"[{\"faction\": \"odun_kragothai\", \"at_least\": 1}, "
		+ "{\"faction\": \"sorn_lumawenai\", \"at_most\": -1}]"
	)
	var read: QuestDefinition = QuestDefinition.parse("x", quest % [both, OPENED_END], {})
	if (not read.problem.is_empty() or read.alignment.size() != 2
			or read.alignment[0].at_least != 1 or read.alignment[0].at_most != Standings.HIGHEST
			or read.alignment[1].at_most != -1 or read.alignment[1].at_least != Standings.LOWEST):
		return "an alignment raising one faction and holding another didn't read: " + read.problem
	var entry: String = "[{\"faction\": \"%s\", %s}]"
	var cases: Dictionary[String, String] = {
		quest % ["1", OPENED_END]: "its alignment must be a list",
		quest % ["[]", OPENED_END]: "its alignment must be a list",
		quest % ["[1]", OPENED_END]: "its alignment: it isn't",
		quest % [
			entry % ["a", "\"at_least\": 1, \"by\": 1"],
			OPENED_END,
		]: "its alignment: field by",
		quest % [
			entry % ["The Guild", "\"at_least\": 1"],
			OPENED_END,
		]: "its alignment: its faction",
		quest % ["[{\"faction\": \"a\"}]", OPENED_END]: "its alignment: it sets neither",
		quest % [entry % ["a", "\"at_least\": 6"], OPENED_END]: "its alignment: its ranks",
		quest % [entry % ["a", "\"at_most\": -6"], OPENED_END]: "its alignment: its ranks",
		quest % [entry % ["a", "\"at_least\": 1.5"], OPENED_END]: "its alignment: its ranks",
		quest % [
			entry % ["a", "\"at_least\": 2, \"at_most\": 1"],
			OPENED_END,
		]: "its alignment: its at_least",
		quest % [
			"[{\"faction\": \"a\", \"at_least\": 1}, {\"faction\": \"a\", \"at_most\": 2}]",
			OPENED_END,
		]: "its alignment names a twice",
	}
	var vanished: String = quest % [entry % ["zz_vanished", "\"at_least\": 1"], OPENED_END]
	if not content.add("x", vanished).begins_with("its alignment's faction"):
		return "a quest enforcing alignment with a faction that doesn't exist was read"
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
			or fork.next_index(0, QuestStep.ENTERED, "thicket", FlowSteps.GLADE) != 2
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
## built-in kinds and keep their walkability; the rules know every kind by its file's name (#802);
## forest, shrubs and a stump are walkable and a boulder isn't (#205), each with its model, and sand
## is plain and walkable (#321); every model a blueprint names exists; the stump is drawn at 400
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
		if missing or tile.scale != SCALED.get(tile.id, TileBlueprint.FULL_SCALE):
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


## The glade's blueprint reads as written (#823): its rules, loot tables, variants in their order
## and codex entry (#1175). What its region holds brings the rest (#879): its people only to the
## glade itself, its chests to its corrupted variant too, through its chest table. A blueprint file
## with a wrong id, an unknown field, no species, a weight below 1, a chest table without a loot
## table, a variant without its region, a variant's region with a codex entry but no gloss or its
## own region with one (#1448), or without a codex entry and gloss is refused. A variant's region
## without a codex entry is the instance changed (#1590), which the world flow loads.
func _check_blueprints() -> String:
	var glade: Blueprint = InstanceBlueprints.blueprint(FlowSteps.GLADE)
	if glade == null or glade.loot_table != "glade" or glade.chest_table != "glade_chest":
		return "the glade's blueprint didn't load as written"
	if (glade.codex_gloss != "the soft clearing"
			or not glade.codex_entry.begins_with("The clearing")):
		return "the glade's codex entry reads %s" % glade.codex_gloss
	var opening: Array[String] = [HostSettingsFeature.ID, MovementFeature.ID]
	if glade.features.slice(0, 2) != opening or glade.features.has(ChestFeature.ID):
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
	var variants: String = _glade_variants_problem(glade)
	if not variants.is_empty():
		return variants
	var variant: String = ", \"variants\": [{\"flag\": \"f\", \"region\": \"%s\"%s}]"
	var codex: String = ", \"codex\": {\"entry\": \"e\", \"gloss\": \"g\"}"
	return _blueprints_refused({
		BLUEPRINT.replace("\"x\"", "\"y\"") % "": "its id must",
		BLUEPRINT % ", \"z\": 1": "field z",
		BLUEPRINT.replace("\"a\": 1", "") % "": "its wild_species",
		BLUEPRINT.replace("\"a\": 1", "\"a\": 0") % "": "its wild_species",
		BLUEPRINT % ", \"chest_table\": \"c\"": "a blueprint with a chest table",
		BLUEPRINT % ", \"variants\": [{\"flag\": \"f\"}]": "its variants",
		BLUEPRINT % (variant % ["r", ", \"codex\": {\"entry\": \"e\"}"]): "its variants",
		BLUEPRINT % (variant % ["", codex]): "its variants",
		BLUEPRINT % ", \"turned\": 1": "turned must",
		BLUEPRINT.replace("\"g\"", "\" \"") % "": "it needs a codex entry",
		BLUEPRINT.replace(", \"codex\": {\"entry\": \"e\", \"gloss\": \"g\"}", "") % "": (
			"it needs a codex entry"
		),
	})


## Why the glade's variants don't read in their order, or its corrupted variant's region without
## its codex entry (#1448), or "".
func _glade_variants_problem(glade: Blueprint) -> String:
	var first: PackedStringArray = (
		glade.variants[0] if not glade.variants.is_empty() else PackedStringArray()
	)
	if first != PackedStringArray([WorldFlags.EVENT_FLAG + FlowSteps.GLADE_PURIFIED, ""]):
		return "the glade's variants read %s" % [glade.variants]
	var corrupted: PackedStringArray = glade.variant_codex.get(
		FlowSteps.CORRUPTED_GLADE,
		PackedStringArray(),
	)
	if (glade.variant_codex.size() != 1
			or corrupted.size() != 2
			or corrupted[1] != "the soft clearing, gone wild"):
		return "the glade's variants' codex entries read %s" % [glade.variant_codex]
	return ""


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
## codex entry and gloss (#959) or its look by day and at night (#1247, a signed colour too, #1367)
## is refused.
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
	# A signed colour reads as a whole number, but isn't six hex digits (#1367).
	var signed: String = "\n## Day and night\n\n- Day light: #-fffff\n- Day ambience: #000000\n"
	signed += "- Night light: #000000\n- Night ambience: #000000\n"
	var no_look: String = (
		"its day and night look needs %s#rrggbb under %s (#1247)"
		% [RealmDocument.DAY_LIGHT, RealmDocument.DAY_AND_NIGHT]
	)
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
		text % ["🟦🌲🟦", forest] + "\n## Codex\n\n- Entry: e\n- Gloss: g\n": no_look,
		text % ["🟦🌲🟦", forest] + "\n## Codex\n\n- Entry: e\n- Gloss: g\n" + signed: no_look,
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
		# Its codex entry and gloss (#1173), each with more than spaces.
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace("\"g\"", "\" \"") + "}": "it needs a codex entry",
		"{\"id\": \"xo\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
		+ KIT.replace(", \"codex\": {\"entry\": \"e\", \"gloss\": \"g\"}", "") + "}": (
			"it needs a codex entry"
		),
	}
	for text: String in cases:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var twice: SpeciesContent = SpeciesContent.new()
	var valid: String = XO + KIT + "}"
	var first: String = twice.add("xo", valid)
	if not first.is_empty() or not twice.add("xo", valid).begins_with("its id"):
		return "a second species with the same id was accepted"
	return ""


## A species without a model (#1223) is refused: one it doesn't name, one that isn't there, or a
## file that isn't a glTF model under assets/.
func _check_model_refused() -> String:
	var texts: Array[String] = [
		XO + KIT.replace(", \"model\": \"" + MODEL + "\"", "") + "}",
		XO + KIT.replace(MODEL, "res://assets/mana-wolf/no_wolf.glb") + "}",
		XO + KIT.replace(MODEL, "res://CREDITS.md") + "}",
		XO + KIT.replace(MODEL, "res://assets/../assets/mana-wolf/mana_wolf.glb") + "}",
	]
	for text: String in texts:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with("it needs a model"):
			return "a species without a model was refused with: " + problem
	return ""


## A species whose behaviour can't form a daily schedule (#1200) is refused, naming what's missing:
## a sleep rhythm, more than one, a need, a trait that isn't one or is named twice, or the list; and
## so is a sleepless light sleeper (#1230).
func _check_behaviour_refused() -> String:
	var cases: Dictionary[String, String] = {
		XO + KIT.replace("\"diurnal\", ", "") + "}": "its behaviour lacks a sleep rhythm",
		XO + KIT.replace("\"diurnal\"", "\"diurnal\", \"sleepless\"") + "}": (
			"its behaviour has more than one sleep rhythm (diurnal, sleepless)"
		),
		XO + KIT.replace(", \"grazer\"", ", \"pack_type\"") + "}": "its behaviour lacks a need",
		XO + KIT.replace(
			"\"grazer\"",
			"\"grazer\", \"grazer\"",
		) + "}": "its behaviour names grazer",
		XO + KIT.replace("\"grazer\"", "\"flying\"") + "}": "its behaviour names flying",
		XO + KIT.replace("\"diurnal\"", "\"sleepless\", \"light_sleeper\"") + "}": (
			"its behaviour is sleepless and light_sleeper"
		),
		XO + KIT.replace(", \"behaviour\": [\"diurnal\", \"grazer\"]", "") + "}": (
			"it needs a behaviour list"
		),
	}
	for text: String in cases:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with(cases[text]):
			return "a species' behaviour gave %s, not %s" % [problem, cases[text]]
	return ""


## Every species' ascension material (#1252) is one the player can find: a loot or harvest table
## drops it, and it's a material (MaterialContent, #774), not a piece of gear.
func _check_ascensions(content: SpeciesContent) -> String:
	var dropped: Array[String] = []
	for directory: String in [LootContent.DIR, LootContent.HARVEST_DIR]:
		for table: LootTable in LootContent.load_loot_tables(directory).loot_tables.values():
			dropped.append_array(table.items)
	var materials: Array[String] = MaterialContent.load_materials().ids
	for species_id: String in content.ascensions:
		var material: String = content.ascensions[species_id].material
		if not dropped.has(material) or not materials.has(material):
			return "%s's ascension material %s is no material a table drops" % [
				species_id,
				material,
			]
	return ""


## Every species' ascension material lies in its grown species' habitat too (#1260): some instance
## whose wild monsters roll that species has treasure chests and loot on the ground, and both its
## chest table and its instance table can give the material.
func _check_ascension_habitats(content: SpeciesContent) -> String:
	for species_id: String in content.ascensions:
		var ascension: SpeciesAscension = content.ascensions[species_id]
		var found: bool = false
		for instance_name: String in InstanceBlueprints.names():
			var named: Blueprint = InstanceBlueprints.blueprint(instance_name)
			if named.wild_species.has(ascension.into):
				found = found or _holds_in_chests(instance_name, ascension.material)
		if not found:
			return "%s's ascension material %s lies in no chest and on no ground where %s lives" % [
				species_id,
				ascension.material,
				ascension.into,
			]
	return ""


## Every species' ascension material is a quest's reward too (#1348): some quest gives it when it
## finishes, and its steps count where the species it ascends into lives. Then its recipe's check.
func _check_ascension_quests(content: SpeciesContent) -> String:
	var quests: QuestContent = QuestContent.load_quests()
	if not quests.problem.is_empty():
		return "the quests didn't load: " + quests.problem
	for species_id: String in content.ascensions:
		var ascension: SpeciesAscension = content.ascensions[species_id]
		var found: bool = false
		for quest: QuestDefinition in quests.quests.values():
			found = found or (
				quest.materials.has(ascension.material)
				and _counts_where_lives(quest, ascension.into)
			)
		if not found:
			return "no quest gives %s's ascension material %s where %s lives" % [
				species_id,
				ascension.material,
				ascension.into,
			]
	return _check_ascension_recipes(content)


## Every species' ascension material can be crafted too (#1349, the owner's pick 3 on #1260): a
## recipe makes it. Then the broken recipes' check.
func _check_ascension_recipes(content: SpeciesContent) -> String:
	var recipes: RecipeContent = RecipeContent.load_recipes()
	if not recipes.problem.is_empty():
		return "the recipes didn't load: " + recipes.problem
	for species_id: String in content.ascensions:
		var material: String = content.ascensions[species_id].material
		if not recipes.recipes.has(material):
			return "no recipe makes %s's ascension material %s" % [species_id, material]
	return _check_recipes_refused()


## A recipe file (#1349) is refused when its id isn't its file's, it has a field it can't, it needs
## nothing, a count that isn't whole from 1, the material it makes, or something that's no
## material, or it makes something that's no material.
func _check_recipes_refused() -> String:
	var cases: Dictionary[String, String] = {
		"{\"id\": \"y\", \"needs\": {\"moss\": 1}}": "its id must",
		"{\"id\": \"bone\", \"needs\": {\"moss\": 1}, \"x\": 1}": "field x",
		"{\"id\": \"bone\", \"needs\": {}}": "its needs name",
		"{\"id\": \"bone\"}": "its needs name",
		"{\"id\": \"bone\", \"needs\": {\"moss\": 0}}": "its needs give",
		"{\"id\": \"bone\", \"needs\": {\"moss\": 1.5}}": "its needs give",
		"{\"id\": \"bone\", \"needs\": {\"bone\": 2}}": "it needs bone",
		"{\"id\": \"bone\", \"needs\": {\"mos\": 2}}": "it makes or needs mos",
		"[\"bone\"]": Content.NOT_AN_OBJECT,
	}
	var refusing: RecipeContent = RecipeContent.new()
	for text: String in cases:
		var file_id: String = "x" if cases[text] == "its id must" else "bone"
		var problem: String = refusing.add(file_id, text)
		if not problem.begins_with(cases[text]):
			return "a recipe was refused with %s, not %s" % [problem, cases[text]]
	var making: String = "{\"id\": \"mos\", \"needs\": {\"moss\": 1}}"
	var made_up: String = refusing.add("mos", making)
	if not made_up.begins_with("it makes or needs mos"):
		return "a recipe making no material was refused with " + made_up
	return ""


## Whether every step of `quest` counts in an instance whose wild monsters roll `species_id`.
func _counts_where_lives(quest: QuestDefinition, species_id: String) -> bool:
	for step: QuestStep in quest.steps:
		for trigger: QuestStep in step.triggers():
			var named: Blueprint = InstanceBlueprints.blueprint(trigger.instance)
			if named == null or not named.wild_species.has(species_id):
				return false
	return true


## Whether an instance of `instance_name` has chests and loot on its ground, and both its chest
## table and its instance table can give `material`.
func _holds_in_chests(instance_name: String, material: String) -> bool:
	var chests: ChestFeature = (
		InstanceBlueprints.create(instance_name, 0, 0).feature(ChestFeature.ID) as ChestFeature
	)
	return (
		chests != null
		and not chests.chests.is_empty()
		and not chests.loot_spots.is_empty()
		and chests.table != null
		and chests.table.items.has(material)
		and chests.ground_table.items.has(material)
	)


## A species' ascension (#1252) is refused when it lacks the species, the level or the material,
## asks for level 1, which every monster starts at, or names another field; and the species are
## refused when one ascends into itself or a species there isn't, or two ascend into each other.
func _check_ascensions_refused() -> String:
	var cases: Dictionary[String, String] = {
		XO + KIT + ", \"ascension\": {\"into\": \"zo\", \"level\": 2}}": "its ascension names",
		XO + KIT + ASCENSION % ["zo", "1"] + "}": "its ascension's level",
		XO + KIT + ASCENSION % ["zo", "2.5"] + "}": "its ascension's level",
		XO + KIT + ASCENSION.replace(
			"}",
			", \"y\": 1}",
		) % ["zo", "2"] + "}": "its ascension's field y",
		XO + KIT + ", \"ascension\": 7}": "its ascension names",
	}
	for text: String in cases:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with(cases[text]):
			return "an ascension was refused with %s, not %s" % [problem, cases[text]]
	var pairs: Dictionary[String, String] = {
		"xo": "isn't another species",
		"yo": "isn't another species",
		"zo": "xo's ascensions come back",
	}
	for into: String in pairs:
		var problem: String = _pair_ascension_problem(into)
		if not problem.contains(pairs[into]):
			return "xo ascending into %s gave %s" % [into, problem]
	return ""


## Why the species xo, ascending into `into`, and zo, ascending into xo, can't be together, or "".
func _pair_ascension_problem(into: String) -> String:
	var both: SpeciesContent = SpeciesContent.new()
	var zo: String = XO.replace("xo", "zo") + KIT.replace("Xo", "Zo")
	var added: String = both.add("xo", XO + KIT + ASCENSION % [into, "2"] + "}")
	added += both.add("zo", zo + ASCENSION % ["xo", "2"] + "}")
	return added if not added.is_empty() else both.ascension_problem()


## Every species has a development web (#677) and every web is a species'. In the toad's, its four
## directions' first nodes are open from the start; taking one opens the next along its direction,
## and a bridge or a portal opens the node it leads to; its nodes lean as written (#1358), and two
## grant a stronger special and a passive (#1404).
func _check_development_webs(content: SpeciesContent) -> String:
	var loaded: DevelopmentContent = DevelopmentContent.load_webs()
	if not loaded.problem.is_empty():
		return "the development webs didn't load: " + loaded.problem
	var species_ids: Array[String] = []
	var web_ids: Array[String] = []
	species_ids.assign(content.species.keys())
	web_ids.assign(loaded.webs.keys())
	species_ids.sort()
	web_ids.sort()
	if web_ids != species_ids:
		return "the development webs are %s, not one for each species %s" % [web_ids, species_ids]
	var web: DevelopmentWeb = loaded.webs["ombulumo"]
	var cases: Dictionary[String, Array] = {
		"": ["sturdy_1", "heavy_1", "swift_1", "deep_1"],
		"sturdy_1": ["sturdy_2", "heavy_1", "swift_1", "deep_1"],
		"sturdy_1 sturdy_2": ["sturdy_3", "heavy_1", "heavy_2", "swift_1", "deep_1"],
		"sturdy_1 sturdy_2 sturdy_3": ["heavy_1", "heavy_2", "swift_1", "swift_3", "deep_1"],
	}
	for taken: String in cases:
		var taken_nodes: Array[String] = []
		taken_nodes.assign(taken.split(" ", false))
		var open: Array[String] = web.open_nodes(taken_nodes)
		if open != cases[taken]:
			return "with %s taken, the toad's web opened %s, not %s" % [taken, open, cases[taken]]
	var heavy: DevelopmentLeaning = web.leanings["heavy_3"]
	if web.nodes.size() != 14 or heavy.strength != 80 or heavy.speed != -30 or heavy.hp != 0:
		return "the toad's web didn't load as written"
	var granting: DevelopmentLeaning = web.leanings["heavy_4"]
	if (web.specials != { "heavy_4": 200 } or web.passives != { "deep_4": "ombulumo_lombu_bombu" }
			or granting.hp != 0 or granting.strength != 0 or granting.speed != 0):
		return "the toad's web's special and passive nodes didn't load as written"
	return _check_development_passives(loaded.webs, content)


## Every passive a web grants (#1404) is a passive in the ability data that no species has yet and
## no other node grants; a special, an unknown ability, a species' own passive or one granted twice
## is refused.
func _check_development_passives(
	webs: Dictionary[String, DevelopmentWeb],
	content: SpeciesContent,
) -> String:
	var abilities: Dictionary[String, Ability] = AbilityContent.load_abilities().abilities
	var problem: String = DevelopmentPassives.problem(webs, content.species, abilities)
	if not problem.is_empty():
		return "the development webs' passives don't hold together: " + problem
	var toad: DevelopmentWeb = webs["ombulumo"]
	var cases: Dictionary[String, String] = {
		"ombulumo_bulum_bolom": "isn't a passive",
		"no_such_ability": "isn't a passive",
		"ombulumo_bolmu_wolmu": "a passive a species already has",
		"tikazzir_kazri_tazri": "both grant",
	}
	for passive: String in cases:
		toad.passives["deep_4"] = passive
		problem = DevelopmentPassives.problem(webs, content.species, abilities)
		if not problem.contains(cases[passive]):
			return "a web granting %s was refused with \"%s\"" % [passive, problem]
	toad.passives["deep_4"] = "ombulumo_lombu_bombu"
	return ""


## Webs a schema might let through, or whose links don't fit a web, are refused with a reason.
func _check_development_refused() -> String:
	var web: String = (
		"{\"species\": \"xo\", \"directions\": [{\"id\": \"a\", \"nodes\": [%s]}, "
		+ "{\"id\": \"b\", \"nodes\": [{\"leaning\": {\"hp\": 1}}, {\"leaning\": {\"hp\": 1}}]}, "
		+ "{\"id\": \"c\", \"nodes\": [{\"leaning\": {\"hp\": 1}}]}], "
		+ "\"bridges\": [%s], \"portals\": [%s]}"
	)
	var node: String = "{\"leaning\": {\"hp\": 1}}"
	var cases: Dictionary[String, String] = {
		web % [node, "[\"a_1\", \"b_1\"]", "[\"a_1\", \"b_2\"]"]: "",
		web.replace("\"xo\"", "\"yo\"") % [node, "", ""]: "its species must",
		web % ["", "", ""]: "direction a has a node",
		web % ["{\"leaning\": {}}", "", ""]: "node a_1: its leaning shifts one stat",
		web % ["{\"leaning\": {\"hp\": 0}}", "", ""]: "node a_1: its leaning shifts hp",
		web % ["{\"leaning\": {\"hp\": 501}}", "", ""]: "node a_1: its leaning shifts hp",
		web % ["{\"leaning\": {\"luck\": 1}}", "", ""]: "node a_1: its leaning's field luck",
		web % [node, "[\"a_1\", \"d_1\"]", ""]: "each bridge links two",
		web % [node, "[\"b_1\", \"b_2\"]", ""]: "bridge b_1-b_2 links two directions",
		web % [node, "[\"a_1\", \"b_2\"], [\"b_2\", \"a_1\"]", ""]: "bridge b_2-a_1 links two",
		web % [node + ", " + node + ", " + node, "[\"a_3\", \"b_1\"]", ""]: "bridge a_3-b_1",
		web % [node, "", "[\"a_1\", \"b_1\"]"]: "portal a_1-b_1 links two directions' outermost",
		web.replace(", \"portals\": [%s]", "") % [node, ""]: "its web lists its portals",
		web.replace(", {\"id\": \"c\"", ", {\"id\": \"a\"") % [node, "", ""]: "each direction's id",
		web % ["{\"special\": 200}", "", ""]: "",
		web % ["{\"passive\": \"xo_ab_cd\"}", "", ""]: "",
		web % ["{}", "", ""]: "node a_1: it grants one of",
		web % ["{\"special\": 200, \"leaning\": {\"hp\": 1}}", "", ""]: "node a_1: it grants one",
		web % ["{\"special\": 0}", "", ""]: "node a_1: its special grows",
		web % ["{\"special\": 1001}", "", ""]: "node a_1: its special grows",
		web % ["{\"passive\": \"Not an id\"}", "", ""]: "node a_1: its passive is",
	}
	for text: String in cases:
		var problem: String = _add_web(text)
		if not problem.begins_with(cases[text]) or problem.is_empty() != cases[text].is_empty():
			return "a development web was refused with \"%s\", not \"%s\": %s" % [
				problem,
				cases[text],
				text,
			]
	return ""


## Why the web file xo with the text `text` can't be read, or "".
func _add_web(text: String) -> String:
	return DevelopmentContent.new().add("xo", text)


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


## Every item a loot, harvest or chest table names exists (#774): a piece of gear or a material,
## each read from its own data. A table naming an item that's neither is refused, and so is a
## material file with a wrong id or a field it can't have; then the gear's models (#1581).
func _check_loot_items() -> String:
	var materials: MaterialContent = MaterialContent.load_materials()
	if not materials.problem.is_empty():
		return "the materials didn't load: " + materials.problem
	var gear: GearContent = GearContent.load_gear()
	var tables: Array[LootTable] = []
	for directory: String in [LootContent.DIR, LootContent.HARVEST_DIR]:
		tables.append_array(LootContent.load_loot_tables(directory).loot_tables.values())
	var problem: String = _unknown_item(tables, gear, materials)
	if not problem.is_empty():
		return problem
	var item: String = "{\"item\": \"%s\", \"chance\": 250, \"min\": 1, \"max\": 1}"
	var entries: Array[String] = []
	for named: String in ["moss", "thorn_spikes", "warding_charm", "mos"]:
		entries.append(item % named)
	var text: String = "{\"id\": \"x\", \"kind\": \"chest\", \"entries\": [%s]}"
	var made_up: LootTable = LootTableFile.parse("x", text % ", ".join(entries))
	problem = _unknown_item([made_up], gear, materials)
	if not made_up.problem.is_empty() or not problem.begins_with("x's table names mos,"):
		return "a table naming an item there isn't was refused with %s" % problem
	var cases: Dictionary[String, String] = {
		"{\"id\": \"y\"}": "its id must",
		"{\"id\": \"x\", \"name\": \"X\"}": "field name",
		"[\"x\"]": Content.NOT_AN_OBJECT,
	}
	var refusing: MaterialContent = MaterialContent.new()
	for refused: String in cases:
		problem = refusing.add("x", refused)
		if not problem.begins_with(cases[refused]):
			return "a material file was refused with %s, not %s" % [problem, cases[refused]]
	return _check_gear_models()


## Every piece of gear loads with a model that exists (#1581): every item has one. A gear file
## without one, or naming one that isn't a glTF model under assets/, is refused.
func _check_gear_models() -> String:
	var gear: GearContent = GearContent.load_gear()
	if not gear.problem.is_empty() or gear.items.is_empty():
		return "the gear didn't load: " + gear.problem
	for item: GearItem in gear.items.values():
		if not ResourceLoader.exists(item.model):
			return "%s's model %s doesn't exist" % [item.id, item.model]
	var text: String = (
		"{\"id\": \"x\", \"name\": \"X\", \"slot\": \"throw\", \"rarity\": \"loose\"%s}"
	)
	for model: String in ["", ", \"model\": \"res://assets/none.glb\"", ", \"model\": 5"]:
		var refused: GearItem = GearItem.parse("x", text % model)
		if not refused.problem.begins_with("it needs a model"):
			return "gear with the model \"%s\" was refused with %s" % [model, refused.problem]
	var kept: GearItem = GearItem.parse("x", text % (", \"model\": \"%s\"" % MODEL))
	return "" if kept.problem.is_empty() else "gear with a model was refused: " + kept.problem


## Why one of `tables` names an item that's neither a piece of `gear` nor one of `materials`, or "".
func _unknown_item(
		tables: Array[LootTable],
		gear: GearContent,
		materials: MaterialContent,
) -> String:
	for table: LootTable in tables:
		for item: String in table.items:
			if not item.is_empty() and not gear.items.has(item) and not materials.ids.has(item):
				return "%s's table names %s, which is no gear or material (#774)" % [table.id, item]
	return ""


## The factions load, each with its own name for every rank but neutral (#483): the Amvrel
## Velmarai's (#484) run from Apprentice Charter up to Charted in Legend and from Betrayer down. A
## faction file with a wrong id, no name, an unknown field, not five rank names with more than
## spaces each way, or without a codex entry and gloss (#959) is refused.
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
		faction.replace("\"codex\"", "\"z\"") % [five, five]: "field z",
		faction.replace(", \"codex\": {\"entry\": \"e\", \"gloss\": \"g\"}", "") % [five, five]: (
			"it needs a codex entry"
		),
		faction.replace("\"entry\": \"e\"", "\"entry\": \" \"") % [five, five]: (
			"it needs a codex entry"
		),
		faction.replace(", \"gloss\": \"g\"", "") % [five, five]: "it needs a codex entry",
		faction.replace("\"gloss\": \"g\"", "\"gloss\": \" \"") % [five, five]: (
			"it needs a codex entry"
		),
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
	var territory: String = faction.trim_suffix("}") + ", \"territory\": %s}"
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
	return _check_faction_enemies(content)


## The Amvrel Velmarai, the Story guild, is allied until the postgame and has no enemies,
## so none names it, and the Odun Kragothai and the Sorn Lumawenai are each other's, both
## starting one rank below neutral (#1310, #1324, #1323, #1378). A faction whose enemies aren't a
## list of faction ids, each once and never its
## own, or that is allied until the postgame and has enemies, is refused, and so is an enemy
## that isn't a faction naming it back; two factions naming each other load as enemies.
func _check_faction_enemies(content: FactionContent) -> String:
	var guild: Faction = content.factions["amvrel_velmarai"]
	if not guild.enemies.is_empty() or not guild.allied_until_postgame:
		return "the Story guild has enemies, or isn't allied until the postgame (#1324)"
	if (not content.factions.has("odun_kragothai")
			or " ".join(content.factions["odun_kragothai"].enemies) != "sorn_lumawenai"):
		return "the Odun Kragothai and the Sorn Lumawenai aren't enemies (#1323)"
	for id: String in ["odun_kragothai", "sorn_lumawenai"]:
		if content.factions[id].starting_standing != -1 or guild.starting_standing != 0:
			return "Supremacy and Harmony don't start one rank below neutral (#1378)"
	var faction: String = FACTION_TEXT % [FIVE_RANKS, FIVE_RANKS]
	var enemies: String = faction.trim_suffix("}") + ", \"enemies\": %s}"
	var refused: String = _factions_refused({
		enemies % "\"y\"": "its enemies must",
		enemies % "[\"x\"]": "its enemies must",
		enemies % "[\"y\", \"y\"]": "its enemies must",
		enemies % "[\"Y\"]": "its enemies must",
		(enemies % "[\"y\"]").trim_suffix("}") + ", \"allied_until_postgame\": true}": (
			"a faction allied until the postgame has no enemies"
		),
		faction.trim_suffix("}") + ", \"allied_until_postgame\": 1}": "its allied_until_postgame",
		faction.trim_suffix("}") + ", \"starting_standing\": 6}": "its starting_standing",
		faction.trim_suffix("}") + ", \"starting_standing\": -0.5}": "its starting_standing",
	})
	if not refused.is_empty():
		return refused
	# Faction y, with its own symbol, naming x as its enemy, or naming none.
	var x_start: String = "\"x\", \"name\": \"X\", \"symbol\": \"+"
	var y_start: String = "\"y\", \"name\": \"Y\", \"symbol\": \"-"
	var y: String = (enemies % "[\"x\"]").replace(x_start, y_start)
	var texts: Dictionary[String, String] = {
		"x": enemies % "[\"y\"]",
		"y": y.replace(", \"enemies\": [\"x\"]", ""),
	}
	var one_way: String = FlowSteps.written_content(FactionContent.load_factions, texts).problem
	if not one_way.contains("its enemy y isn't a faction naming it back"):
		return "an enemy not naming its enemy back gave %s" % one_way
	texts["y"] = y
	var mutual: FactionContent = FlowSteps.written_content(FactionContent.load_factions, texts)
	if not mutual.problem.is_empty() or " ".join(mutual.factions["y"].enemies) != "x":
		return "two factions naming each other didn't load as enemies: %s" % mutual.problem
	return ""


## Why the factions in two faction files, x from `text_x` and y from `text_y` with its id made y,
## are refused together, or "".
func _pair_problem(text_x: String, text_y: String) -> String:
	var texts: Dictionary[String, String] = { "x": text_x, "y": text_y.replace("\"x\"", "\"y\"") }
	return FlowSteps.written_content(FactionContent.load_factions, texts).problem


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
	if greeting.speaker != "teska_na_amvrel" or walked != [1, 2, -1, -1, -1, -1]:
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
		var locking: int = 0
		for spot: NpcSpot in _placed_spots(instance_name):
			var dialog: Dialog = dialogs.get(spot.dialog)
			locking += 1 if dialog != null and dialog.lock else 0
		if locking > Dialog.MOST_LOCKING_PER_REGION:
			# A CI warning annotation on stdout, which GitHub shows without failing the run.
			# gdstyle:ignore=quality/no-debug-print
			print("::warning::%s places %d people with locking dialogs, more than %d (#891)" % [
				instance_name, locking, Dialog.MOST_LOCKING_PER_REGION,
			])
	return ""


## Dialog files with a wrong id, no speaker or one that's no person's id (#1005), no lines, a line
## without text, an answer without an id,
## two lines or answers sharing an id, or an answer leading to no line are refused (#618), and so
## are one that doesn't state whether it locks, or an answer whose commits isn't true or false
## (#891), and one that holds its player (it locks, or a committing answer leads on) up to a last
## line without answers, which would hold them forever (#1014), and one with a line nothing leads
## to from its first (#1029).
func _check_dialogs_refused() -> String:
	var dialog: String = "{\"id\": \"x\", \"speaker\": \"s\", \"lock\": false, \"lines\": [%s]}"
	var line: String = "{\"id\": \"a\", \"text\": \"T\", \"answers\": [%s]}"
	var answer: String = "{\"id\": \"%s\", \"text\": \"T\", \"next\": \"%s\"}"
	var cases: Dictionary[String, String] = {
		dialog.replace("\"x\"", "\"y\"") % "{\"text\": \"T\"}": "its id must",
		dialog.replace("\"s\"", "\" \"") % "{\"text\": \"T\"}": "it needs a speaker",
		dialog.replace("\"s\"", "\"Teska na Amvrel\"") % "{\"text\": \"T\"}": "it needs a speaker",
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
	var nobody: String = FlowSteps.written_content(
		DialogContent.load_dialogs,
		{ "x": dialog % "{\"text\": \"T\"}" },
	).problem
	if not nobody.contains("its speaker s is no person"):
		return "a dialog spoken by no person gave %s" % nobody
	return ""


## The people load (#1005): Teska na Amvrel with their name and codex entry, and every person a
## region's legend places is one, and speaks the dialog talking to them opens. A person file with a
## wrong id, no name, an unknown field, or without a codex entry and gloss is refused. The unique
## items, the other kind whose codex entry lives in its content file, are checked next (#1449).
func _check_people() -> String:
	var content: PeopleContent = PeopleContent.load_people()
	var scout: Person = content.people.get("teska_na_amvrel")
	if not content.problem.is_empty() or scout == null or scout.name != "Teska na Amvrel":
		return "the people didn't load: " + content.problem
	if scout.codex_gloss != "Teska, sworn to the guild" or not scout.codex_entry.begins_with("A "):
		return "Teska na Amvrel's codex entry reads %s" % scout.codex_gloss
	var placed: String = _placed_people_problem(content)
	if not placed.is_empty():
		return placed
	var person: String = (
		"{\"id\": \"x\", \"name\": \"X\", \"codex\": {\"entry\": \"e\", \"gloss\": \"g\"}}"
	)
	var cases: Dictionary[String, String] = {
		person.replace("\"x\"", "\"y\""): "its id must",
		person.replace("\"X\"", "\" \""): "it needs a name",
		person.replace("\"codex\"", "\"z\""): "field z",
		person.replace("\"e\"", "\" \""): "it needs a codex entry",
		person.replace(", \"gloss\": \"g\"", ""): "it needs a codex entry",
		"[]": Content.NOT_AN_OBJECT,
	}
	for text: String in cases:
		var refusal: String = Person.parse("x", text).problem
		if not refusal.begins_with(cases[text]):
			return "a broken person gave %s, not %s" % [refusal, cases[text]]
	return _check_unique_items()


## The unique items load (#1449): Vis'omera, gear of rarity bound, with its codex entry, and its
## UNIQUE_ITEM tag shows its name; no other gear has that tag. Unique gear without a codex entry and
## gloss is refused, and so is other gear with one.
func _check_unique_items() -> String:
	var gear: Dictionary[String, GearItem] = GearContent.load_gear().items
	var charm: GearItem = gear.get("vis_omera")
	if charm == null or not charm.is_unique() or charm.codex.size() != 2:
		return "Vis'omera didn't load as a unique item with a codex entry"
	if charm.codex[1] != "the ward that keeps them near" or not charm.codex[0].begins_with("A "):
		return "Vis'omera's codex entry reads %s" % [charm.codex]
	var tags: TextTags = TextNames.load_tags()
	if (tags.resolve("${UNIQUE_ITEM:vis_omera}") != "Vis'omera"
			or tags.problem_in("${UNIQUE_ITEM:warding_charm}").is_empty()):
		return "the unique item tags name %s" % [tags.names.get(TextTags.UNIQUE_ITEM)]
	var codex: String = ", \"codex\": {\"entry\": \"e\", \"gloss\": \"g\"}"
	# With a model, which every piece of gear needs (#1581).
	var unique: String = (
		"{\"id\": \"x\", \"name\": \"Vis'x\", \"slot\": \"ward\", \"rarity\": \"bound\""
		+ ", \"model\": \"" + MODEL + "\"%s}"
	)
	var cases: Dictionary[String, String] = {
		unique % "": "a unique item",
		unique % codex.replace("\"g\"", "\" \""): "its codex needs",
		(unique % codex).replace("bound", "loose"): "a unique item",
	}
	for text: String in cases:
		var refusal: String = GearItem.parse("x", text).problem
		if not refusal.begins_with(cases[text]):
			return "a broken unique item gave %s, not %s" % [refusal, cases[text]]
	return GearItem.parse("x", unique % codex).problem


## Why a person a region's legend places isn't one of `content`'s people, or doesn't speak the
## dialog talking to them opens, or "".
func _placed_people_problem(content: PeopleContent) -> String:
	var dialogs: Dictionary[String, Dialog] = DialogContent.load_dialogs().dialogs
	for instance_name: String in InstanceBlueprints.names():
		for spot: NpcSpot in _placed_spots(instance_name):
			if not content.people.has(spot.id):
				return "%s places %s, who is no person (#1005)" % [instance_name, spot.id]
			var said: Dialog = dialogs.get(spot.dialog)
			if not spot.dialog.is_empty() and (said == null or said.speaker != spot.id):
				return "%s's %s opens %s, which they don't speak" % [
					instance_name,
					spot.id,
					spot.dialog,
				]
	return ""


## The people a new instance of `instance_name` places, as its legend says.
static func _placed_spots(instance_name: String) -> Array[NpcSpot]:
	var state: GameState = InstanceBlueprints.create(instance_name, 0, 0)
	var people: NpcFeature = state.feature(NpcFeature.ID) as NpcFeature
	var spots: Array[NpcSpot] = []
	if people != null:
		spots.assign(people.spots.values())
	return spots


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


## Every text tag (#733) in the texts that show them (a dialog's lines and answers, a
## quest's name, an ability's name and description, a faction's name and ranks, a piece of gear's
## name, #752) names content that exists, and shows its current name;
## a tag of an unknown kind, with an id that doesn't exist, or written wrong is refused.
func _check_text_tags() -> String:
	var tags: TextTags = TextNames.load_tags()
	if not tags.problem.is_empty():
		return "the text tags' names didn't load: " + tags.problem
	var texts: Array[String] = []
	for dialog: Dialog in DialogContent.load_dialogs().dialogs.values():
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
	var shown: String = tags.resolve(
		"${PERSON:teska_na_amvrel} of the ${FACTION:amvrel_velmarai} sells ${GEAR:berry_pouch}"
		# A variant's region of its own is a place too (#1448).
		+ " in ${PLACE:edhra_tewk} of ${REALM:ardvaun}, by ${PLACE:lymwen_hoall}",
	)
	var expected: String = "in Edhra Tewk of Ardvaun, by Lymwen Hoall"
	if shown != "Teska na Amvrel of the Amvrel Velmarai sells Berry pouch " + expected:
		return "person, faction, gear, place and realm tags show %s" % shown
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
	return _check_nested_tag(tags)


## A tag in a name shows its name too, as when a faction's name is a link (#1447).
static func _check_nested_tag(tags: TextTags) -> String:
	tags.names[TextTags.FACTION]["zz_nested"] = "${MONSTER:ombulumo} kin"
	var shown: String = tags.resolve("the ${FACTION:zz_nested}")
	return "" if shown == "the Ombulumo kin" else "a tag in a faction's name shows as " + shown


## Text tags whose content can't be read are warned about, and show as written (#949).
func _check_text_tags_unread(tree: SceneTree) -> String:
	# The factions' files, read as species, are a species directory that can't be read.
	TextTags.read_names_with(func() -> TextTags: return TextNames.load_tags(FactionContent.DIR))
	tree.call("expect_warning", "the text tags' names can't be read")
	var unread: String = TextTags.shown("${MONSTER:ombulumo}")
	TextNames.wire()
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
