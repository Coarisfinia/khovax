class_name FactionContent
extends RefCounted
## The factions' content data (#483), which the factions slice owns (#412): one JSONC file per
## faction directly in its data/ (its own kind, so no folder repeats the slice's name, #442),
## checked against factions.schema.json beside them in CI. Everything else reads the factions
## through this.

const DIR: String = "res://slices/factions/data/"

## Every faction, by id.
var factions: Dictionary[String, Faction] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""


## Every faction file in `directory`, read and checked, with no instance in two factions' territory
## and no two factions with one symbol (#637).
static func load_factions(directory: String = DIR) -> FactionContent:
	var content: FactionContent = FactionContent.new()
	var taken: Dictionary[String, String] = {}
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		var faction: Faction = Faction.parse(file_id, texts[file_id])
		if faction.problem.is_empty():
			faction.problem = _hold(faction, taken)
		if not faction.problem.is_empty():
			content.problem = file_id + ".jsonc: " + faction.problem
			return content
		content.factions[faction.id] = faction
	return content


## Notes `faction`'s territory and symbol in `taken`, each instance and symbol by its faction's id;
## returns why one is another faction's already, or "": a symbol is the only thing telling two
## factions' territory apart (#68).
static func _hold(faction: Faction, taken: Dictionary[String, String]) -> String:
	for instance_name: String in faction.territory:
		if taken.has(instance_name):
			return "%s is %s's territory already" % [instance_name, taken[instance_name]]
		taken[instance_name] = faction.id
	# The space keeps symbols apart from instance names, which are ids.
	var symbol_key: String = "symbol " + faction.symbol
	if taken.has(symbol_key):
		return "its symbol %s is %s's already" % [faction.symbol, taken[symbol_key]]
	taken[symbol_key] = faction.id
	return ""
