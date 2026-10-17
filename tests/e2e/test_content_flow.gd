extends RefCounted
## Content flow (#72): the game's content data loads, and holds together where a schema can't
## check it. Every species file reads, with comments stripped; ids are unique and match their file;
## types come from the type chart, never two from one family; and broken entries are refused. Loot
## tables (#90) load, roll the same for the same stream, and a blank rolls on the instance's table.
## Tile blueprints (#116) load, the built-in ones with the numbers and traits regions always had,
## and broken ones are refused. Quests (#184) load with the steps they're written with, name only
## species that exist, and broken ones are refused.

## A species file's speed, archetype and abilities, as a valid species ends (#222).
const KIT: String = (
	", \"speed\": 1, \"archetype\": \"pusher\", \"special\": \"a_special\","
	+ " \"player_passive\": \"a_passive\", \"self_passive\": \"its_passive\""
)
## A quest step to reach a place, its id left open (#339).
const REACH: String = "{\"condition\": \"reached\", \"place\": \"%s\"}"


func run(_tree: SceneTree) -> String:
	var content: Content = Content.load_species()
	if not content.problem.is_empty():
		return "the species data didn't load: " + content.problem
	if not content.species.has("moss_toad") or content.species["storm_finch"].types.size() != 2:
		return "the placeholder species didn't load as written"
	var result: String = _check_strip()
	if result.is_empty():
		result = _check_refused()
	if result.is_empty():
		result = _check_loot_rolls()
	if result.is_empty():
		result = _check_loot_refused()
	if result.is_empty():
		result = _check_wild_species(content)
	if result.is_empty():
		result = _check_tiles()
	if result.is_empty():
		result = _check_quests()
	return result if not result.is_empty() else _check_kits(content)


## Every ability file reads, and every species names a special and two passives that exist and are
## of their kind, its special its own (#222, #228). A special two species share, an ability of the
## wrong kind, or one that doesn't exist is refused, and so is an ability file with a wrong id,
## kind, name or description.
func _check_kits(content: Content) -> String:
	var loaded: Content = Content.load_abilities()
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
	return _check_abilities_refused()


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
	var cases: Dictionary[String, String] = {
		ability % ["y", "special", "N"]: "its id must",
		ability % ["x", "attack", "N"]: "its kind",
		ability % ["x", "special", ""]: "it has a name",
		"{\"id\": \"x\", \"kind\": \"special\", \"name\": \"N\"}": "it has a name",
		ability.replace("}", ", \"power\": 1}") % ["x", "special", "N"]: "field power",
	}
	for text: String in cases:
		var problem: String = Ability.parse("x", text).problem
		if not problem.begins_with(cases[text]):
			return "expected an ability refusal starting %s, got: %s" % [cases[text], problem]
	return ""


## Why a step to reach the beach doesn't read, or "".
func _check_reach_step(content: Content) -> String:
	var beach: QuestDefinition = QuestDefinition.parse(
		"x",
		"{\"id\": \"x\", \"name\": \"N\", \"steps\": [%s]}" % (REACH % "beach"),
		content.species,
	)
	if not beach.problem.is_empty() or beach.steps[0].place != "beach":
		return "a step to reach the beach didn't read: " + beach.problem
	return ""


## Every quest file reads: the first domination is one domination of any species, and the toads'
## quest counts up three of one species, and a step to reach a place names it (#339). Quests with a
## wrong id, name, step, condition, species, place or count are refused, with a reason: a reached
## step without a place, or a place on another step, too.
func _check_quests() -> String:
	var content: Content = Content.load_quests()
	if not content.problem.is_empty():
		return "the quests didn't load: " + content.problem
	var first: QuestDefinition = content.quests.get("first_domination")
	var toads: QuestDefinition = content.quests.get("three_moss_toads")
	if first == null or first.name.is_empty() or first.steps.size() != 1 or toads == null:
		return "the quests didn't load as written"
	var any_domination: QuestStep = first.steps[0]
	var toad_step: QuestStep = toads.steps[0]
	if (any_domination.condition != "dominated"
			or not any_domination.species.is_empty()
			or any_domination.count != 1):
		return "the first domination isn't one domination of any species"
	if toad_step.species != "moss_toad" or toad_step.count != 3:
		return "the toads' quest isn't three moss toads"
	if not _check_reach_step(content).is_empty():
		return _check_reach_step(content)
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
		quest % ["x", "N", step % ", \"species\": \"ember_cat\""]: "step 0: its species",
		quest % ["x", "N", "{\"condition\": \"opened\", \"species\": \"moss_toad\"}"]: (
			"step 0: its species"
		),
		quest % ["x", "N", step % "" + ", " + step % ", \"count\": 0"]: "step 1: its count",
		quest % ["x", "N", step % ", \"count\": 1.5"]: "step 0: its count",
		quest % ["x", "N", step % ", \"when\": 1"]: "step 0: field when",
		quest % ["x", "N", "7"]: "step 0: it isn't",
	}
	for text: String in cases:
		var problem: String = QuestDefinition.parse("x", text, content.species).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	return ""


## Every tile blueprint file reads, its id matching its file; ground, water and rock keep their
## numbers and walkability; the rules number every kind by its file's number; forest, shrubs and
## a stump are walkable and a boulder isn't (#205), each with its model, and every model a blueprint
## names exists; the stump is drawn at scale 4, every other kind at 1, the default; no two kinds
## share a symbol (#68). Broken blueprints, and two with one number, are refused.
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
	}
	var plain: Array[String] = ["ground", "water", "rock"]
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
		if missing or tile.scale != (4.0 if tile.id == "stump" else 1.0):
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
		tile % ["x", "9", "#000000", walks, ", \"scale\": 9"]: "its scale",
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
			", \"scale\": 4"])
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
func _check_wild_species(content: Content) -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		var listed: Dictionary = InstanceBlueprints.WILD_SPECIES.get(instance_name, { })
		var named: Array = InstanceBlueprints.region_of(instance_name, 0).named_species.values()
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
	return Content.new().add_species("x", text)


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
		+ KIT.replace("\"a_special\"", "7") + "}": "it names a special",
	}
	for text: String in cases:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var twice: Content = Content.new()
	var valid: String = "{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1"
	valid += KIT + "}"
	var first: String = twice.add_species("x", valid)
	if not first.is_empty() or not twice.add_species("x", valid).begins_with("its id"):
		return "a second species with the same id was accepted"
	return ""


## The placeholder tables load. A roll on the toad's table gives 2 to 4 berries, or on its blank
## what the glade's table gives (1 to 2 moss, or a single berry), and the same stream rolls the
## same loot.
func _check_loot_rolls() -> String:
	var content: Content = Content.load_loot_tables()
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
		var blank: bool = loot.get("berry", 0) == 1 or loot.get("moss", 0) in [1, 2]
		if loot.size() != 1 or not (own or blank):
			return "seed %d rolled %s" % [seed_value, loot]
		hits[own] += 1
	if hits[true] == 0 or hits[false] == 0:
		return "the toad's rolls never gave its berries or never hit the blank"
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
		table % ["species", item % [1000, 1, 1]]: "a species table has exactly one",
		table % ["instance", "%s, %s" % [item % [500, 1, 1], blank % 500]]: "a species table",
		table % ["instance", item % [1000, 3, 2]]: "entry 0 needs",
		table % ["chest", item % [1000, 1, 1]]: "its kind",
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
