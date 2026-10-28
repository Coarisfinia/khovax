class_name TextTags
extends RefCounted
## Typed placeholder tags in player-facing text (#733): `${MONSTER:ombulumo}` names a species by
## its id and shows its current name ("Ombulumo"), so renaming one changes every text at once. A
## tag has a kind (MONSTER, FACTION, GEAR, PERSON, REALM, PLACE, UNIQUE_ITEM) and an id of that
## kind; the content flow refuses a text whose tag has an unknown kind or an id that doesn't exist.
## Tags are resolved when a text is shown (owner, #733), never when content loads, so saves and
## content keep the tags and never a resolved name. A tag shows the name as written: a plural or an
## article is part of the text around it.

## Each kind of tag, by the word that names it in a tag: a species, a faction, a piece of gear, a
## person (#1005), a realm and a place, an instance a realm draws (#1175) or a variant's region of
## its own (#1448), and a unique item, gear of rarity bound (#1449), which GEAR names too.
const MONSTER: String = "MONSTER"
const FACTION: String = "FACTION"
const GEAR: String = "GEAR"
const PERSON: String = "PERSON"
const REALM: String = "REALM"
const PLACE: String = "PLACE"
const UNIQUE_ITEM: String = "UNIQUE_ITEM"
## A tag: `${`, its kind's word, `:`, an id, `}`.
const TAG_PATTERN: String = "\\$\\{([A-Z_]+):([a-z][a-z0-9_]*)\\}"
## Where any tag starts, well formed or not.
const TAG_START: String = "${"
## The kinds whose names open a codex page when the player selects them (#959): a faction's lexicon
## entry, a species' bestiary entry (#1173), a person's page (#1005), a realm's and a place's
## (#1175), and a unique item's (#1449).
const CODEX_KINDS: Array[String] = [FACTION, MONSTER, PERSON, REALM, PLACE, UNIQUE_ITEM]

## The tags read from the game's content, read the first time one is shown.
static var _shown: TextTags = null
## What reads the names `shown` shows, handed in once at start (#1612): the content slices come
## after this one, so `TextNames` (slices/text_names/) reads them, and game/ hands it in.
static var _reader: Callable = Callable()
## Finds the tags in a text, for `tags_in`.
static var _finder: RegEx = RegEx.create_from_string(TAG_PATTERN)

## Every name a tag can show, by its kind's word and its id.
var names: Dictionary[String, Dictionary] = {}
## Why the content couldn't be read, or "" when it could.
var problem: String = ""
var _pattern: RegEx = RegEx.create_from_string(TAG_PATTERN)


## `text` as the player reads it, every tag in it showing the current name it stands for. The
## content's names are read once, the first time: they don't change while the game runs.
static func shown(text: String) -> String:
	if not text.contains(TAG_START):
		return text
	if _shown == null:
		_shown = _read_names()
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


## Makes `shown` read its names with `reader`, which returns a TextTags, the next time a tag is
## shown (#1612).
static func read_names_with(reader: Callable) -> void:
	_reader = reader
	_shown = null


## The names `shown` shows, read with the reader handed in; without one, none, and why.
static func _read_names() -> TextTags:
	if not _reader.is_valid():
		var none: TextTags = TextTags.new()
		none.problem = "no reader of the names was handed in (TextTags.read_names_with)"
		return none
	var tags: TextTags = _reader.call()
	return tags


## `text` with every tag replaced by the name it stands for; a tag that stands for nothing stays as
## written, which the content flow never lets through. A name's own tags are resolved too
## (`nested`), one level deep.
func resolve(text: String, nested: bool = true) -> String:
	var resolved: String = ""
	var from: int = 0
	for found: RegExMatch in _pattern.search_all(text):
		var kind_names: Dictionary = names.get(found.get_string(1), {})
		var tag_name: String = kind_names.get(found.get_string(2), found.get_string())
		# A name may hold tags itself, like a faction's (#1447): resolved one level deep, so a name
		# naming itself can't loop.
		if nested:
			tag_name = resolve(tag_name, false)
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
