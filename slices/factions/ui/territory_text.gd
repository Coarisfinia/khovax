class_name TerritoryText
extends RefCounted
## How a faction's territory (#637) reads to the player: the holder's symbol, which tells the
## factions apart where it's marked, never a color (#68), and a line saying who holds an instance,
## by symbol and name. Never a rank (#484). The factions are read once, the first time they're
## needed.

const HELD_TEXT: String = "Held by %s %s"
const NOT_HELD_TEXT: String = "Held by no faction"
## The symbol of a holder the content doesn't know.
const UNKNOWN_SYMBOL: String = "?"

static var _content: FactionContent


## The symbol of the faction `faction_id`, or UNKNOWN_SYMBOL when the content doesn't know it.
static func symbol_of(faction_id: String) -> String:
	var faction: Faction = _factions().factions.get(faction_id)
	return faction.symbol if faction != null else UNKNOWN_SYMBOL


## The line saying the faction `faction_id` holds an instance, or that none does for "".
static func held_text(faction_id: String) -> String:
	if faction_id.is_empty():
		return NOT_HELD_TEXT
	var faction: Faction = _factions().factions.get(faction_id)
	var shown_name: String = faction.name if faction != null else faction_id.capitalize()
	return HELD_TEXT % [symbol_of(faction_id), TextTags.shown(shown_name)]


## The factions' content; when it doesn't load, no faction is known.
static func _factions() -> FactionContent:
	if _content == null:
		_content = FactionContent.cached()
		if not _content.problem.is_empty():
			push_warning("the factions can't be read for their territory: " + _content.problem)
	return _content
