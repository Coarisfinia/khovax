class_name Faction
extends RefCounted
## A faction (#483), read from content data (the factions slice's data/, #72, #412): a player-facing
## name, a symbol that tells it apart where it's marked (#68), its own names for the ranks of the
## player's standing with it (Standings), five each way from neutral, which has none, and the
## instances it holds when a world starts (its territory, #637; Territory), the factions it is an
## enemy of (#1310; Standings.align), and its codex entry, which its lexicon page shows (#959).

## Its schema, which says the fields a faction file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/factions/data/factions.schema.json"
## The most characters a symbol has, so it fits in its mark.
const SYMBOL_LENGTH: int = 2

var id: String = ""
## The player-facing name. It may hold text tags (#733), so whatever shows it shows it through
## TextTags.shown (#752).
var name: String = ""
## What marks it, one or two characters (#68): its territory on the Survey, beside its name.
var symbol: String = ""
## The ranks' names above neutral, from standing 1 up to Standings.HIGHEST. Like the
## name, every rank's name may hold text tags, shown through TextTags.shown.
var ranks_up: Array[String] = []
## The ranks' names below neutral, from standing -1 down to Standings.LOWEST.
var ranks_down: Array[String] = []
## The instances it holds when a world starts, by blueprint name, each once (#637).
var territory: Array[String] = []
## The factions it is an enemy of, by id, each once (#1310); FactionContent checks that each is a
## faction naming it back.
var enemies: Array[String] = []
## The standing every player starts at with it (#1378), from Standings.LOWEST to
## Standings.HIGHEST: neutral (0) unless its data says otherwise.
var starting_standing: int = 0
## Whether it stays allied with the player until the postgame once they've joined it (#1324): their
## standing with it never drops below the first rank (Standings.align). It is no faction's enemy.
var allied_until_postgame: bool = false
## Its codex entry (#959): a short text about it and where its name comes from.
var codex_entry: String = ""
## What its name means, hand-written (#959), e.g. "the guild of those who chart".
var codex_gloss: String = ""
## Why the faction couldn't be read, or "" when it could.
var problem: String = ""


## A faction read from a faction file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> Faction:
	var faction: Faction = Faction.new()
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		faction.problem = Content.NOT_AN_OBJECT
		return faction
	var data: Dictionary = parsed
	faction.id = Content.text_of(data.get("id"))
	faction.name = Content.text_of(data.get("name"))
	faction.symbol = Content.text_of(data.get("symbol"))
	faction.problem = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	var allied: Variant = data.get("allied_until_postgame", false)
	if faction.problem.is_empty() and not allied is bool:
		faction.problem = "its allied_until_postgame must be true or false"
	faction.allied_until_postgame = allied is bool and allied
	# Anything but a whole number on the scale reads as one below it, which is refused.
	var start: Variant = data.get("starting_standing", 0)
	faction.starting_standing = JsonNumbers.whole(
		start, Standings.LOWEST, Standings.HIGHEST, Standings.LOWEST - 1
	)
	if faction.problem.is_empty() and faction.starting_standing < Standings.LOWEST:
		faction.problem = "its starting_standing must be a whole number from %d to %d" % [
			Standings.LOWEST,
			Standings.HIGHEST,
		]
	if faction.problem.is_empty():
		faction.problem = faction._check(file_id, data.get("ranks_up"), data.get("ranks_down"))
	if faction.problem.is_empty() and not faction._read_territory(data.get("territory", [])):
		faction.problem = "its territory must list instance ids, each once"
	if faction.problem.is_empty() and not faction._read_enemies(data.get("enemies", [])):
		faction.problem = "its enemies must list faction ids, each once, never its own"
	if (faction.problem.is_empty()
			and faction.allied_until_postgame
			and not faction.enemies.is_empty()):
		faction.problem = "a faction allied until the postgame has no enemies (#1324)"
	if faction.problem.is_empty() and not faction._read_codex(data.get("codex")):
		faction.problem = "it needs a codex entry and gloss (#959)"
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
	var wrong_id: String = Content.id_problem(id, file_id)
	if not wrong_id.is_empty():
		return wrong_id
	if name.strip_edges().is_empty():
		return "it needs a name"
	if symbol.strip_edges().is_empty() or symbol.length() > SYMBOL_LENGTH:
		return "it needs a symbol of 1 to %d characters" % SYMBOL_LENGTH
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


## Whether `raw` lists instance ids, each once; reads them into `territory`.
func _read_territory(raw: Variant) -> bool:
	return _read_ids(raw, territory)


## Whether `raw` lists faction ids, each once and none its own; reads them into `enemies`.
func _read_enemies(raw: Variant) -> bool:
	return _read_ids(raw, enemies) and not enemies.has(id)


## Whether `raw` lists ids, each once; reads them into `ids`.
static func _read_ids(raw: Variant, ids: Array[String]) -> bool:
	if not raw is Array:
		return false
	var entries: Array = raw
	for entry: Variant in entries:
		var each: String = Content.text_of(entry)
		if not Content.is_id(each) or ids.has(each):
			return false
		ids.append(each)
	return true


## Whether `raw` holds a codex entry and gloss, each with more than spaces; reads them.
func _read_codex(raw: Variant) -> bool:
	var codex: Array[String] = Content.codex_of(raw)
	if codex.is_empty():
		return false
	codex_entry = codex[0]
	codex_gloss = codex[1]
	return true
