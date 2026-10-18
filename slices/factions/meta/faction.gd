class_name Faction
extends RefCounted
## A faction (#483), read from content data (the factions slice's data/, #72, #412): a player-facing
## name and its own names for the ranks of the player's standing with it (Standings), five each way
## from neutral, which has none.

## A faction file's fields, as its schema (slices/factions/data/factions.schema.json) allows them.
const FIELDS: Array[String] = ["id", "name", "ranks_up", "ranks_down"]

var id: String = ""
## The player-facing name.
var name: String = ""
## The ranks' names above neutral, from standing 1 up to Standings.HIGHEST.
var ranks_up: Array[String] = []
## The ranks' names below neutral, from standing -1 down to Standings.LOWEST.
var ranks_down: Array[String] = []
## Why the faction couldn't be read, or "" when it could.
var problem: String = ""


## A faction read from a faction file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> Faction:
	var faction: Faction = Faction.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		faction.problem = "not a JSON object"
		return faction
	var data: Dictionary = json.data
	faction.id = Content.text_of(data.get("id"))
	faction.name = Content.text_of(data.get("name"))
	faction.problem = Content.unknown_field(data, FIELDS)
	if faction.problem.is_empty():
		faction.problem = faction._check(file_id, data.get("ranks_up"), data.get("ranks_down"))
	return faction


## The name of the rank at `standing`, or "" at neutral, where the player holds no rank with it.
func rank_name(standing: int) -> String:
	if standing > 0:
		return ranks_up[mini(standing, ranks_up.size()) - 1]
	if standing < 0:
		return ranks_down[mini(-standing, ranks_down.size()) - 1]
	return ""


## Why the read fields are wrong, or "", and the ranks read from `raw_up` and `raw_down` when they
## aren't.
func _check(file_id: String, raw_up: Variant, raw_down: Variant) -> String:
	if id != file_id or not Content.is_id(id):
		return "its id must match the file name and be lowercase words with underscores"
	if name.strip_edges().is_empty():
		return "it needs a name"
	if not _read_ranks(raw_up, ranks_up) or not _read_ranks(raw_down, ranks_down):
		return "it needs %d rank names each way, each with more than spaces" % Standings.HIGHEST
	return ""


## Whether `raw` holds a name for every rank one way, each with more than spaces; reads them into
## `names`.
static func _read_ranks(raw: Variant, names: Array[String]) -> bool:
	var entries: Array = raw if raw is Array else []
	for entry: Variant in entries:
		var rank: String = Content.text_of(entry)
		if rank.strip_edges().is_empty():
			return false
		names.append(rank)
	return entries.size() == Standings.HIGHEST
