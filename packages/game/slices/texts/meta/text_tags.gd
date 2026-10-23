class_name TextTags
extends RefCounted
## Typed placeholder tags in player-facing text (#733): `${MONSTER:ombulumo}` names a species by
## its id and shows its current name ("Ombulumo"), so renaming one changes every text at once. A
## tag has a kind (MONSTER, FACTION, GEAR, PERSON, REALM, PLACE) and an id of that kind; the content
## flow refuses a text whose tag has an unknown kind or an id that doesn't exist. Tags are resolved
## when a text is
## shown (owner, #733), never when content loads, so saves and content keep the tags and never a
## resolved name. A tag shows the name as written: a plural or an article is part of the text
## around it.

## Each kind of tag, by the word that names it in a tag: a species, a faction, a piece of gear, a
## person (#1005), a realm and a place, an instance a realm draws (#1175).
const MONSTER: String = "MONSTER"
const FACTION: String = "FACTION"
const GEAR: String = "GEAR"
const PERSON: String = "PERSON"
const REALM: String = "REALM"
const PLACE: String = "PLACE"
## A tag: `${`, its kind's word, `:`, an id, `}`.
const TAG_PATTERN: String = "\\$\\{([A-Z_]+):([a-z][a-z0-9_]*)\\}"
## Where any tag starts, well formed or not.
const TAG_START: String = "${"
## The kinds whose names open a codex page when the player selects them (#959): a faction's lexicon
## entry, a species' bestiary entry (#1173), a person's page (#1005), and a realm's and a place's
## (#1175).
const CODEX_KINDS: Array[String] = [FACTION, MONSTER, PERSON, REALM, PLACE]

## The tags read from the game's content, read the first time one is shown.
static var _shown: TextTags = null
## Where `shown` reads the species from; the content flow points it at one that can't be read.
static var _species_directory: String = SpeciesContent.DIR
## Finds the tags in a text, for `tags_in`.
static var _finder: RegEx = RegEx.create_from_string(TAG_PATTERN)

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
	people_directory: String = PeopleContent.DIR,
) -> TextTags:
	var tags: TextTags = TextTags.new()
	var species: SpeciesContent = SpeciesContent.load_species(species_directory)
	var factions: FactionContent = FactionContent.load_factions(faction_directory)
	var gear: GearContent = GearContent.load_gear(gear_directory)
	var people: PeopleContent = PeopleContent.load_people(people_directory)
	tags.problem = species.problem + factions.problem + gear.problem + people.problem
	var monsters: Dictionary[String, String] = {}
	for id: String in species.species:
		monsters[id] = species.species[id].name
	var faction_names: Dictionary[String, String] = {}
	for id: String in factions.factions:
		faction_names[id] = factions.factions[id].name
	var gear_names: Dictionary[String, String] = {}
	for id: String in gear.items:
		gear_names[id] = gear.items[id].name
	var person_names: Dictionary[String, String] = {}
	for id: String in people.people:
		person_names[id] = people.people[id].name
	tags.names = {
		MONSTER: monsters,
		FACTION: faction_names,
		GEAR: gear_names,
		PERSON: person_names,
	}
	tags.names.merge(_realm_names())
	return tags


## The names of the realms and of the places they draw (#1175), by their kinds' words and ids.
static func _realm_names() -> Dictionary[String, Dictionary]:
	var realm_names: Dictionary[String, String] = {}
	var place_names: Dictionary[String, String] = {}
	for realm: Realm in Realms.all():
		realm_names[realm.id] = Realms.name_of(realm.id)
		for tile: Vector2i in realm.instances:
			place_names[realm.instances[tile]] = Realms.name_of(realm.instances[tile])
	return { REALM: realm_names, PLACE: place_names }


## `text` as the player reads it, every tag in it showing the current name it stands for. The
## content's names are read once, the first time: they don't change while the game runs.
static func shown(text: String) -> String:
	if not text.contains(TAG_START):
		return text
	if _shown == null:
		_shown = load_tags(_species_directory)
		# Warned once, when read (#949): every tag then shows as written.
		if not _shown.problem.is_empty():
			var why: String = _shown.problem
			push_warning("the text tags' names can't be read, so tags show as written: " + why)
	return _shown.resolve(text)


## The tag of the kind `kind` for the id `id`: `${KIND:id}`.
static func tag(kind: String, id: String) -> String:
	return "${%s:%s}" % [kind, id]


## Every well-formed tag in `text`, in order: its kind's word is group 1 and its id group 2.
static func tags_in(text: String) -> Array[RegExMatch]:
	return _finder.search_all(text)


## Makes `shown` read the species from `directory` the next time a tag is shown.
static func read_species_from(directory: String) -> void:
	_species_directory = directory
	_shown = null


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
