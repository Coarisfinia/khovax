class_name FactionContent
extends Content
## The factions' content data (#483), which the factions slice owns (#412): one JSONC file per
## faction directly in its data/ (its own kind, so no folder repeats the slice's name, #442),
## checked against factions.schema.json beside them in CI. Everything else reads the factions
## through this.

const DIR: String = "res://slices/factions/data/"

## Every faction, by id.
var factions: Dictionary[String, Faction] = {}
## Each instance in a faction's territory, and each faction's symbol (as "symbol <symbol>"), by
## the faction's id.
var _taken: Dictionary[String, String] = {}


## Every faction file in `directory`, read and checked, with no instance in two factions' territory
## and no two factions with one symbol (#637).
static func load_factions(directory: String = DIR) -> FactionContent:
	var content: FactionContent = FactionContent.new()
	content.read(directory)
	return content


## The factions, read once per session (ContentCatalog).
static func cached() -> FactionContent:
	return ContentCatalog.kept(DIR, load_factions)


func add(file_id: String, text: String) -> String:
	var faction: Faction = Faction.parse(file_id, text)
	if faction.problem.is_empty():
		faction.problem = _hold(faction)
	if faction.problem.is_empty():
		factions[faction.id] = faction
	return faction.problem


## Notes `faction`'s territory and symbol; returns why one is another faction's already, or "": a
## symbol is the only thing telling two factions' territory apart (#68).
func _hold(faction: Faction) -> String:
	for instance_name: String in faction.territory:
		if _taken.has(instance_name):
			return "%s is %s's territory already" % [instance_name, _taken[instance_name]]
		_taken[instance_name] = faction.id
	# The space keeps symbols apart from instance names, which are ids.
	var symbol_key: String = "symbol " + faction.symbol
	if _taken.has(symbol_key):
		return "its symbol %s is %s's already" % [faction.symbol, _taken[symbol_key]]
	_taken[symbol_key] = faction.id
	return ""
