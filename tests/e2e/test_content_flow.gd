extends RefCounted
## Content flow (#72): the game's content data loads, and holds together where a schema can't
## check it. Every species file reads, with comments stripped; ids are unique and match their file;
## types come from the type chart, never two from one family; and broken entries are refused.


func run(_tree: SceneTree) -> String:
	var content: Content = Content.load_species()
	if not content.problem.is_empty():
		return "the species data didn't load: " + content.problem
	if not content.species.has("moss_toad") or content.species["storm_finch"].types.size() != 2:
		return "the placeholder species didn't load as written"
	var result: String = _check_strip()
	if result.is_empty():
		result = _check_refused()
	return result


## Comments go, strings keep their slashes and stars, and line breaks stay where they were.
func _check_strip() -> String:
	var text: String = "{\n\"a\": \"x // y /* z */\", // gone\n/* gone\ntoo */ \"b\": 1\n}"
	var stripped: String = Jsonc.strip(text)
	var expected: String = "{\n\"a\": \"x // y /* z */\", \n\n \"b\": 1\n}"
	if stripped != expected:
		return "stripping comments gave %s" % stripped.c_escape()
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
	}
	for text: String in cases:
		var problem: String = _add_to_empty(text)
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var twice: Content = Content.new()
	var first: String = twice.add_species(
		"x",
		"{\"id\": \"x\", \"types\": [\"mana\"], \"hp\": 1, \"strength\": 1}",
	)
	if not first.is_empty() or twice.add_species("x", "{\"id\": \"x\"}").is_empty():
		return "a second species with the same id was accepted"
	return ""
