extends RefCounted
## Content flow (#72): the game's content data loads, and holds together where a schema can't
## check it. Every species file reads, with comments stripped; ids are unique and match their file;
## types come from the type chart, never two from one family; and broken entries are refused. Loot
## tables (#90) load, roll the same for the same stream, and a blank rolls on the instance's table.


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
	return result


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
	}
	for text: String in cases:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var twice: Content = Content.new()
	var valid: String = "{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1}"
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
		var loot: Dictionary[String, int] = toad.roll(Rng.new(seed_value, 1), glade)
		if loot != toad.roll(Rng.new(seed_value, 1), glade):
			return "seed %d rolled two different loots" % seed_value
		var own: bool = loot.get("berry", 0) >= 2 and loot["berry"] <= 4
		var blank: bool = loot.get("berry", 0) == 1 or loot.get("moss", 0) in [1, 2]
		if loot.size() != 1 or not (own or blank):
			return "seed %d rolled %s" % [seed_value, loot]
		hits[own] += 1
	if hits[true] == 0 or hits[false] == 0:
		return "the toad's rolls never gave its berries or never hit the blank"
	return ""


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
		var problem: String = LootTable.parse("x", text).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	return ""
