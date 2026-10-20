class_name ContentTerms
extends RefCounted
## Every id and name in the game's content (#909), each with the thing it belongs to, for the
## content flow: no two things may share one, whatever their kinds, compared in lower case (a
## thing's own id and name may match: a species' id is its name, #763), and each thing keeps to its
## kind's name rule. Not a flow itself: the runner runs only the `test_*.gd` files.

## The landform words a place's name ends in (#909): clearing, wood, stronghold, camp, pass, ring,
## still water, height, fen.
const LANDFORMS: Array[String] = [
	"Hoal",
	"Wudhen",
	"Stolm",
	"Tewk",
	"Varn",
	"Orl",
	"Sael",
	"Ghest",
	"Mordh",
]
## The oath words a faction's name starts with (#909): guild, order, host, circle, league.
const OATHS: Array[String] = ["Amvrel", "Odun", "Vara", "Ithe", "Sorn"]
## The runes a unique item's name starts with (#909): edge, ward, forge, heirloom, bone, light.
const RUNES: Array[String] = ["Kel", "Vis", "Dar", "Ol", "Osk", "Sel"]
## The sounds a species' first type colours its name with (#909): it has at least one of them.
const TYPE_SOUNDS: Dictionary[String, String] = {
	"growth": "mblw",
	"nature": "mblw",
	"breeze": "fsht",
	"tempest": "fsht",
	"might": "gdrk",
	"titan": "gdrk",
	"mana": "vny",
	"arcane": "vny",
	"shadow": "xqu",
	"abyss": "xqu",
}
## The rarity of unique and bound items (#291), whose names are rune-speech (#909).
const UNIQUE_RARITY: String = "bound"
## The beast-calls' letters, z, x, q, y and a doubled consonant: only species and abilities have
## them, and a corrupted place, which takes them on purpose (#909).
const BEAST_LETTERS: String = "[zxqy]|([b-df-hj-np-tv-z])\\1"
## The land-speech's sounds: only realms and places have them (#909).
const LAND_SOUNDS: String = "dh|gh|hr|wh"
## The name rule of each kind of thing, from the six tongues the owner adopted on #909: its name
## (its
## id in words for a thing with no name of its own) keeps its kind's rule and no other kind's marks
## (a hyphen, an apostrophe, vo or na, a last word in -ai, a word in -vaun, a lexicon word), and its
## id is its name in lower case, spaces, hyphens and apostrophes made `_`, after its species' id
## for an ability. Trade Speech (gear, pieces, places) is plain words, so letters aren't held
## against it. Kinds left out (tiles, items, loot tables, quests, dialogs) are vocabulary.
const NAME_RULES: Dictionary[String, String] = {
	"species": "one beast-call of 6 to 11 letters and at least 3 vowels, echoing itself (a vowel "
	+ "recurring or a consonant doubled), ending in a vowel, r, s, x, k or n, with a sound of its "
	+ "first type's",
	"special": "a beast-call of two parts joined by a hyphen, the second in lower case, with the "
	+ "same consonants and other vowels, sharing two consonants with its species",
	"passive": "a beast-call of two parts joined by a hyphen, the second in lower case, differing "
	+ "only in their first consonant, sharing two consonants with its species",
	"realm": "one land-speech word of 2 or 3 syllables ending in -vaun",
	"instance": "a land-speech name of 1 to 3 syllables, then a landform word",
	"region": "its instance's name corrupted: y for the first vowel, the landform's last consonant "
	+ "doubled",
	"piece": "plain lower-case words, of its instance",
	"place": "plain lower-case words",
	"faction": "an oath word, then a name ending in -ai",
	"person": "a hearth-speech name of 2 syllables ending in a vowel, l, n, s or r, then vo and a "
	+ "kin name or na and an oath word",
	"unique": "a rune, an apostrophe, then a lower-case name of 2 or 3 syllables",
	"gear": "1 to 3 plain words in sentence case",
}
## Things whose names break their kind's rule today, each with the issue renaming it (#909). It only
## shrinks: a thing that keeps its rule must be dropped from it.
const NAME_EXCEPTIONS: Dictionary[String, int] = {
	"special ombulumo_belly_flop": 973,
	"passive ombulumo_soft_moss": 973,
	"passive ombulumo_damp_hide": 973,
	"special tikazzir_gale_dive": 973,
	"passive tikazzir_tailwind": 973,
	"passive tikazzir_light_bones": 973,
	"realm heartland": 974,
	"instance arena": 975,
	"instance basic": 975,
	"instance castle": 975,
	"instance forest": 975,
	"instance glade": 975,
	"instance load": 975,
	"instance mountain_pass": 975,
	"instance outpost": 975,
	"region glade_corrupted": 975,
	"faction cartographers_guild": 976,
	"person guild_scout": 977,
}
## Terms two things share today, each with the issue that gives one of them another (#909). It
## only shrinks: a term that no longer clashes must be dropped from it.
const KNOWN_DUPLICATES: Dictionary[String, int] = {
	"forest": 975, # a tile kind and an instance, which gives it up when it's renamed
	"glade": 975, # an instance and its loot table, which keeps it when the instance is renamed
}

## Each term, in lower case, with every thing using it ("<kind> <id>").
var owners: Dictionary[String, PackedStringArray] = {}
## Each thing whose kind has a name rule ("<kind> <id>"), with why its name breaks it or "".
var broken: Dictionary[String, String] = {}


## Notes the thing of `kind` with `id` and its `name` ("" for none): its terms, and its name against
## its kind's rule. `related` is what that rule reads besides: a species' first type, an ability's
## species' id, a region's instance's id.
func add(kind: String, id: String, name: String = "", related: String = "") -> void:
	var thing: String = "%s %s" % [kind, id]
	for term: String in [id.to_lower(), name.to_lower()]:
		if term.is_empty():
			continue
		var using: PackedStringArray = owners.get(term, PackedStringArray())
		if not using.has(thing):
			var _added: bool = using.append(thing)
			owners[term] = using
	if NAME_RULES.has(kind):
		var why: String = _rule_problem(kind, id, name, related)
		broken[thing] = "" if why.is_empty() else why + " (#909)"


## Why the terms don't hold together, or "": a term two things share unless `duplicates` lists it
## (and then only those two), a listed term that no longer clashes, a thing breaking its kind's
## name rule unless `exceptions` lists it, or a listed thing that keeps its rule now.
func problem(
		duplicates: Dictionary[String, int] = KNOWN_DUPLICATES,
		exceptions: Dictionary[String, int] = NAME_EXCEPTIONS,
) -> String:
	var terms: Array[String] = []
	terms.assign(owners.keys())
	terms.sort()
	for term: String in terms:
		var using: PackedStringArray = owners[term]
		if using.size() > (2 if duplicates.has(term) else 1):
			return "%s names %s: give each another (#909)" % [term, " and ".join(using)]
	for term: String in duplicates:
		var using: PackedStringArray = owners.get(term, PackedStringArray())
		if using.size() < 2:
			return "KNOWN_DUPLICATES' %s no longer clashes: drop it" % term
	var things: Array[String] = []
	things.assign(broken.keys())
	things.sort()
	for thing: String in things:
		if not broken[thing].is_empty() and not exceptions.has(thing):
			return "%s: %s" % [thing, broken[thing]]
	for thing: String in exceptions:
		if broken.get(thing, "").is_empty():
			return "NAME_EXCEPTIONS' %s keeps its kind's rule or is gone: drop it" % thing
	return ""


## Every id and name the content holds, each with the thing it belongs to.
static func collected() -> ContentTerms:
	var terms: ContentTerms = ContentTerms.new()
	for tile: String in TileContent.load_tiles().tiles:
		terms.add("tile", tile)
	var species_of: Dictionary[String, String] = {}
	for species: Species in SpeciesContent.load_species().species.values():
		terms.add("species", species.id, species.name, species.types[0])
		for ability: String in [species.special, species.player_passive, species.self_passive]:
			species_of[ability] = species.id
	for ability: Ability in AbilityContent.load_abilities().abilities.values():
		var kind: String = "special" if ability.kind == Ability.SPECIAL else "passive"
		terms.add(kind, ability.id, ability.name, species_of.get(ability.id, ""))
	var gear: GearContent = GearContent.load_gear()
	for item: GearItem in gear.items.values():
		terms.add("unique" if item.rarity == UNIQUE_RARITY else "gear", item.id, item.name)
	for faction: Faction in FactionContent.load_factions().factions.values():
		terms.add("faction", faction.id, faction.name)
	for quest: QuestDefinition in QuestContent.load_quests().quests.values():
		terms.add("quest", quest.id, quest.name)
	for realm: Realm in Realms.all():
		terms.add("realm", realm.id)
	_add_loot(terms, gear)
	_add_instances(terms, DialogContent.load_dialogs().dialogs)
	return terms


## Why a thing of `kind` with this `id`, `name` and `related` (see `add`) breaks its kind's rule, or
## "".
static func _rule_problem(kind: String, id: String, name: String, related: String) -> String:
	var shown: String = name if not name.is_empty() else _words_of(kind, id)
	var refused: String = "%s isn't a name its kind allows: %s" % [shown, NAME_RULES[kind]]
	if not _keeps_shape(kind, shown, related):
		return refused
	var marks: String = _marks_problem(kind, shown)
	if not marks.is_empty():
		return "%s has %s, which only another kind's names have" % [shown, marks]
	if name.is_empty():
		return ""
	var own_id: String = RegEx.create_from_string("[ '-]").sub(name.to_lower(), "_", true)
	if kind == "special" or kind == "passive":
		own_id = "%s_%s" % [related, own_id]
	if id != own_id:
		return "its id must be %s, its name in lower case (#763)" % own_id
	return ""


## The name a thing of `kind` with no name of its own has: its id in words, those of a piece before
## its instance's.
static func _words_of(kind: String, id: String) -> String:
	match kind:
		"piece":
			return id.get_slice(" of ", 0).replace("_", " ")
		"place":
			return id.replace("_", " ")
	return id.capitalize()


## Whether `shown` keeps the shape of `kind`'s rule (NAME_RULES).
static func _keeps_shape(kind: String, shown: String, related: String) -> bool:
	var lower: String = shown.to_lower()
	match kind:
		"species":
			return (
				_matches("^[A-Z][a-z]{4,9}[aeioursxkn]$", shown)
				and _vowels(lower) >= 3
				and _matches("([aeiou]).*\\1|([^aeiou])\\2", lower)
				and _shares(lower, TYPE_SOUNDS.get(related, ""), 1)
			)
		"special", "passive":
			return _keeps_call_shape(kind == "special", shown, related)
		"realm":
			return _matches("^[A-Z][a-z]*vaun$", shown) and _syllables(lower) in [2, 3]
		"instance":
			return (
				_matches("^[A-Z][a-z]* (%s)$" % "|".join(LANDFORMS), shown)
				and _syllables(lower.get_slice(" ", 0)) in [1, 2, 3]
			)
		"region":
			return shown == _corrupted(related.capitalize())
		"piece", "place":
			return _matches("^[a-z]+( [a-z]+)*$", shown)
		"faction":
			return _matches("^(%s) [A-Z][a-z]*ai$" % "|".join(OATHS), shown)
		"person":
			return (
				_matches(
					"^[A-Z][a-z]*[aeiouylnsr] (vo [A-Z][a-z]+|na (%s))$" % "|".join(OATHS),
					shown,
				)
				and _syllables(lower.get_slice(" ", 0)) == 2
			)
		"unique":
			return (
				_matches("^(%s)'[a-z]+$" % "|".join(RUNES), shown)
				and _syllables(lower.get_slice("'", 1)) in [2, 3]
			)
		"gear":
			return _matches("^[A-Z][a-z]*( [a-z]+){0,2}$", shown)
	return true


## Whether an ability's name, `shown`, keeps the shape of its kind's rule: a special's
## two parts have the same consonants and other vowels, a passive's differ only in their first
## consonant, and either shares two consonants with its species' id, `related`.
static func _keeps_call_shape(special: bool, shown: String, related: String) -> bool:
	var lower: String = shown.to_lower()
	if not _matches("^[A-Z][a-z]+-[a-z]+$", shown) or not _shares(lower, related, 2):
		return false
	var first: String = lower.get_slice("-", 0)
	var second: String = lower.get_slice("-", 1)
	if special:
		return first != second and _consonants_of(first) == _consonants_of(second)
	return (
		first.length() == second.length()
		and first[0] != second[0]
		and _matches("^[^aeiou]{2}$", first[0] + second[0])
		and first.substr(1) == second.substr(1)
	)


## The letter or sound in lower-case `lower` that only another kind's names have (#909), or "":
## Trade Speech is plain words, so its letters aren't held against it.
static func _letters_problem(kind: String, lower: String) -> String:
	if kind in ["gear", "piece", "place", "region"]:
		return ""
	if not (kind in ["species", "special", "passive"]) and _matches(BEAST_LETTERS, lower):
		return "a beast-call's letter"
	if not (kind in ["realm", "instance"]) and _matches(LAND_SOUNDS, lower):
		return "a land-speech sound"
	return ""


## The mark in `shown` that only another kind's names have (#909), or "".
static func _marks_problem(kind: String, shown: String) -> String:
	var letters: String = _letters_problem(kind, shown.to_lower())
	if not letters.is_empty():
		return letters
	if shown.contains("-") and not (kind in ["special", "passive"]):
		return "a hyphen"
	if shown.contains("'") and kind != "unique":
		return "an apostrophe"
	var words: PackedStringArray = shown.replace("-", " ").replace("'", " ").split(" ")
	for word: String in words:
		if word.to_lower() in ["vo", "na"] and kind != "person":
			return "vo or na"
		if word.to_lower().ends_with("vaun") and kind != "realm":
			return "a word in -vaun"
		var owner: String = _lexicon_kind(word)
		if not owner.is_empty() and owner != kind and not (owner == "faction" and kind == "person"):
			return "the %s word %s" % [owner, word]
	if words[words.size() - 1].to_lower().ends_with("ai") and kind != "faction":
		return "a last word in -ai"
	return ""


## The kind whose lexicon holds `word`, in any case, or "".
static func _lexicon_kind(word: String) -> String:
	var lexicons: Dictionary[String, Array] = {
		"instance": LANDFORMS,
		"faction": OATHS,
		"unique": RUNES,
	}
	for kind: String in lexicons:
		for entry: String in lexicons[kind]:
			if entry.to_lower() == word.to_lower():
				return kind
	return ""


## `name`, an instance's, corrupted (#909): y for the first vowel of its given name, and its
## landform word's last consonant doubled.
static func _corrupted(name: String) -> String:
	var given: String = name.get_slice(" ", 0)
	var landform: String = name.get_slice(" ", 1)
	var vowel: RegExMatch = RegEx.create_from_string("[AEIOUaeiou]").search(given)
	var last: RegExMatch = RegEx.create_from_string("[^aeiou](?=[aeiou]*$)").search(landform)
	if vowel == null or last == null:
		return ""
	var y: String = "Y" if vowel.get_string() == vowel.get_string().to_upper() else "y"
	given = given.substr(0, vowel.get_start()) + y + given.substr(vowel.get_end())
	return "%s %s" % [given, landform.insert(last.get_end(), last.get_string())]


static func _matches(pattern: String, text: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null


## How many syllables a lower-case word of the land's tongues has: its runs of vowels.
static func _syllables(word: String) -> int:
	return RegEx.create_from_string("[aeiouy]+").search_all(word).size()


## How many vowels a lower-case beast-call has: its syllables are open, so vowels side by side are
## two ("Degaea"). A y before a vowel is a consonant.
static func _vowels(word: String) -> int:
	return RegEx.create_from_string("[aeiou]|y(?![aeiou])").search_all(word).size()


## `word` with its vowels blanked, so only its consonants and their places show.
static func _consonants_of(word: String) -> String:
	return RegEx.create_from_string("[aeiou]").sub(word, "_", true)


## Whether lower-case `text` has at least `least` of the different consonants in `sounds`.
static func _shares(text: String, sounds: String, least: int) -> bool:
	var shared: Dictionary[String, bool] = {}
	for letter: String in sounds.to_lower():
		if not "aeiou-_ ".contains(letter) and text.contains(letter):
			shared[letter] = true
	return shared.size() >= least


## The loot tables but a species' own, whose id is its species' (LootContent), and the items they
## drop but gear, which is noted already.
static func _add_loot(terms: ContentTerms, gear: GearContent) -> void:
	var species_kinds: Array[String] = [LootTable.SPECIES, LootTable.HARVEST]
	for directory: String in [LootContent.DIR, LootContent.HARVEST_DIR]:
		for table: LootTable in LootContent.load_loot_tables(directory).loot_tables.values():
			if not species_kinds.has(table.kind):
				terms.add("loot table", table.id)
			for item: String in table.items:
				if not item.is_empty() and not gear.items.has(item):
					terms.add("item", item)


## The instances, the regions their variants load, their region pieces but the start piece every
## instance has (a piece is a place inside its instance and takes its name from it, the pond of an
## instance, so two instances may each have a pond, #909), the places their legends name, and the
## people standing there by the speakers of
## the dialogs they open; a dialog nobody opens keeps its speaker.
static func _add_instances(terms: ContentTerms, dialogs: Dictionary[String, Dialog]) -> void:
	var start_piece: String = InstanceBlueprints.START_PIECE.get_basename()
	var spoken: Dictionary[String, bool] = {}
	for instance_name: String in InstanceBlueprints.names():
		terms.add("instance", instance_name)
		var region_names: Array[String] = [""]
		for chosen_by: PackedStringArray in InstanceBlueprints.blueprint(instance_name).variants:
			if not chosen_by[1].is_empty():
				terms.add("region", chosen_by[1], "", instance_name)
				region_names.append(chosen_by[1])
		for region_name: String in region_names:
			var region: Region = InstanceBlueprints.region_of(instance_name, 0, region_name)
			for piece: String in region.piece_of.values():
				if piece != start_piece:
					terms.add("piece", "%s of %s" % [piece, instance_name])
			for trigger: TileTrigger in TileTrigger.all_in(region):
				if trigger.action == TileTrigger.REACH:
					terms.add("place", trigger.place)
			for meaning: String in region.placed(NpcPlacements.KIND).values():
				var person: NpcSpot = NpcSpot.read(meaning)
				var said: Dialog = dialogs.get(person.dialog)
				spoken[person.dialog] = true
				terms.add("person", person.id, said.speaker if said != null else "")
	for dialog: Dialog in dialogs.values():
		terms.add("dialog", dialog.id, "" if spoken.has(dialog.id) else dialog.speaker)
