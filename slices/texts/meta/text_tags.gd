class_name TextTags
extends RefCounted
## Typed placeholder tags in player-facing text (#733): `${MONSTER:ombulumo}` names a species by
## its id and shows its current name ("Ombulumo"), so renaming one changes every text at once. A
## tag has a kind (MONSTER, FACTION, GEAR) and an id of that kind; the content flow refuses a text
## whose tag has an unknown kind or an id that doesn't exist. Tags are resolved when a text is
## shown (owner, #733), never when content loads, so saves and content keep the tags and never a
## resolved name. A tag shows the name as written: a plural or an article is part of the text
## around it.

## Each kind of tag, by the word that names it in a tag: a species, a faction, a piece of gear.
const MONSTER: String = "MONSTER"
const FACTION: String = "FACTION"
const GEAR: String = "GEAR"
## A tag: `${`, its kind's word, `:`, an id, `}`.
const TAG_PATTERN: String = "\\$\\{([A-Z_]+):([a-z][a-z0-9_]*)\\}"
## Where any tag starts, well formed or not.
const TAG_START: String = "${"

## The tags read from the game's content, read the first time one is shown.
static var _shown: TextTags = null

## Every name a tag can show, by its kind's word and its id.
var names: Dictionary[String, Dictionary] = {}
## Why the content couldn't be read, or "" when it could.
var problem: String = ""
var _pattern: RegEx = RegEx.create_from_string(TAG_PATTERN)


## The names every kind of tag shows, read from the content in the given directories.
static func load_tags(
	species_directory: String = SpeciesContent.DIR,
	faction_directory: String = FactionContent.DIR,
	gear_directory: String = GearContent.DIR,
) -> TextTags:
	var tags: TextTags = TextTags.new()
	var species: SpeciesContent = SpeciesContent.load_species(species_directory)
	var factions: FactionContent = FactionContent.load_factions(faction_directory)
	var gear: GearContent = GearContent.load_gear(gear_directory)
	tags.problem = species.problem + factions.problem + gear.problem
	var monsters: Dictionary[String, String] = {}
	for id: String in species.species:
		monsters[id] = species.species[id].name
	var faction_names: Dictionary[String, String] = {}
	for id: String in factions.factions:
		faction_names[id] = factions.factions[id].name
	var gear_names: Dictionary[String, String] = {}
	for id: String in gear.items:
		gear_names[id] = gear.items[id].name
	tags.names = { MONSTER: monsters, FACTION: faction_names, GEAR: gear_names }
	return tags


## `text` as the player reads it, every tag in it showing the current name it stands for. The
## content's names are read once, the first time: they don't change while the game runs.
static func shown(text: String) -> String:
	if not text.contains(TAG_START):
		return text
	if _shown == null:
		_shown = load_tags()
	return _shown.resolve(text)


## `text` with every tag replaced by the name it stands for; a tag that stands for nothing stays as
## written, which the content flow never lets through.
func resolve(text: String) -> String:
	var resolved: String = ""
	var from: int = 0
	for found: RegExMatch in _pattern.search_all(text):
		var kind_names: Dictionary = names.get(found.get_string(1), {})
		var tag_name: String = kind_names.get(found.get_string(2), found.get_string())
		resolved += text.substr(from, found.get_start() - from) + tag_name
		from = found.get_end()
	return resolved + text.substr(from)


## Why a tag in `text` stands for nothing, or "": every `${` starts a whole tag, of a known kind,
## naming an id of that kind that exists.
func problem_in(text: String) -> String:
	var tags: int = 0
	for found: RegExMatch in _pattern.search_all(text):
		tags += 1
		var kind: String = found.get_string(1)
		if not names.has(kind):
			return "tag %s: its kind must be one of %s" % [found.get_string(), names.keys()]
		if not names[kind].has(found.get_string(2)):
			return "tag %s: no %s has the id %s" % [found.get_string(), kind, found.get_string(2)]
	if text.count(TAG_START) != tags:
		return "a tag is written ${KIND:id}, an id of lowercase words joined by underscores"
	return ""
