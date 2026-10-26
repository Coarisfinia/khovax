class_name RealmDocument
extends RefCounted
## A realm as a Markdown file, realms/<id>.md (#865): a title and prose explaining it, its
## instances drawn as an EmojiGrid in the region files' style. Each legend entry is either
## "the instance <id>", naming an instance blueprint, "the instance <id>, where the players start"
## for the instance the world starts in, or "no instance", which fills the picture between them.
## Under `## Codex`, its codex entry (#959) is the item "- Entry: <text>" and its name's meaning
## the item "- Gloss: <text>"; a realm without both is refused. Under `## Day and night`, its look
## by day and at night (#1247) is the items "- Day light: #rrggbb", "- Day ambience: #rrggbb",
## "- Night light: #rrggbb" and "- Night ambience: #rrggbb"; a realm without all four is refused.
## The realms are the files in DIR, found by listing it (Realms).

const INSTANCE: String = "the instance "
const START: String = ", where the players start"
const NO_INSTANCE: String = "no instance"
const CODEX: String = "## Codex"
const ENTRY: String = "- Entry: "
const GLOSS: String = "- Gloss: "
const DAY_AND_NIGHT: String = "## Day and night"
const DAY_LIGHT: String = "- Day light: "
const DAY_AMBIENCE: String = "- Day ambience: "
const NIGHT_LIGHT: String = "- Night light: "
const NIGHT_AMBIENCE: String = "- Night ambience: "


## Notes each instance `grid` draws on `realm`, by its tile; returns why it can't, or "".
static func _draw(realm: Realm, grid: EmojiGrid, meanings: Dictionary[String, String]) -> String:
	for tile: Vector2i in grid.symbols:
		var instance_id: String = meanings[grid.symbols[tile]]
		if realm.has(instance_id):
			return "the instance %s is drawn twice" % instance_id
		if not instance_id.is_empty():
			realm.instances[tile] = instance_id
	return ""


## The realm a Markdown realm document describes; its `problem` says what's wrong.
static func parse(text: String) -> Realm:
	var realm: Realm = Realm.new()
	var grid: EmojiGrid = EmojiGrid.read(text)
	realm.problem = grid.problem
	if not realm.problem.is_empty():
		return realm
	var starts: Array[String] = []
	var meanings: Dictionary[String, String] = _meanings(grid, starts)
	var unexplained: String = grid.unexplained(meanings)
	if not unexplained.is_empty():
		realm.problem = "the legend doesn't explain `%s`" % unexplained
	elif starts.size() > 1:
		realm.problem = "the players start in %s" % " and ".join(starts)
	else:
		realm.problem = _draw(realm, grid, meanings)
	if realm.problem.is_empty() and not starts.is_empty():
		realm.start = starts[0]
		if not realm.has(realm.start):
			realm.problem = "the players start in %s, which isn't drawn" % realm.start
	if realm.problem.is_empty():
		var codex: Dictionary[String, String] = _items(text, CODEX)
		realm.codex_entry = codex.get(ENTRY, "")
		realm.codex_gloss = codex.get(GLOSS, "")
		if realm.codex_entry.is_empty() or realm.codex_gloss.is_empty():
			realm.problem = "its codex entry and gloss are missing under %s (#959)" % CODEX
	if realm.problem.is_empty():
		realm.problem = _read_day_and_night(realm, _items(text, DAY_AND_NIGHT))
	return realm


## Notes the look by day and at night listed in `items` on `realm`; returns why it can't, or "".
static func _read_day_and_night(realm: Realm, items: Dictionary[String, String]) -> String:
	var colors: Array[int] = []
	for item: String in [DAY_LIGHT, DAY_AMBIENCE, NIGHT_LIGHT, NIGHT_AMBIENCE]:
		var color: String = items.get(item, "")
		if not _is_rgb(color):
			return "its day and night look needs %s#rrggbb under %s (#1247)" % [item, DAY_AND_NIGHT]
		colors.append(color.substr(1).hex_to_int())
	realm.day_light = colors[0]
	realm.day_ambience = colors[1]
	realm.night_light = colors[2]
	realm.night_ambience = colors[3]
	return ""


## Whether `color` is "#rrggbb": six hex digits, each checked alone, since a whole number may carry
## a sign (#1367).
static func _is_rgb(color: String) -> bool:
	if color.length() != 7 or not color.begins_with("#"):
		return false
	for digit: String in color.substr(1):
		if not digit.is_valid_hex_number():
			return false
	return true


## The items listed in `text`'s section under `heading` (up to its next heading): each item's
## lead-in ("- Entry: ") to the text after it.
static func _items(text: String, heading: String) -> Dictionary[String, String]:
	var items: Dictionary[String, String] = {}
	var inside: bool = false
	for line: String in text.split("\n"):
		var clean: String = line.strip_edges()
		if clean.begins_with("#"):
			inside = clean == heading
		elif inside and clean.begins_with("- ") and clean.contains(": "):
			var lead: String = clean.substr(0, clean.find(": ") + 2)
			items[lead] = clean.trim_prefix(lead)
	return items


## Each legend symbol's instance id, or "" where it draws none, with the instances it marks as the
## start added to `starts`.
static func _meanings(grid: EmojiGrid, starts: Array[String]) -> Dictionary[String, String]:
	var meanings: Dictionary[String, String] = {}
	for symbol: String in grid.legend:
		var meaning: String = grid.legend[symbol]
		if meaning == NO_INSTANCE:
			meanings[symbol] = ""
		elif meaning.begins_with(INSTANCE):
			meanings[symbol] = meaning.trim_prefix(INSTANCE).trim_suffix(START)
			if meaning.ends_with(START):
				starts.append(meanings[symbol])
	return meanings
