class_name ContentTerms
extends RefCounted
## Every id and name in the game's content (#909), each with the thing it belongs to, for the
## content flow: no two things may share one, whatever their kinds, compared in lower case (a
## thing's own id and name may match: a species' id is its name, #763), and each thing keeps to its
## kind's name rule. Not a flow itself: the runner runs only the `test_*.gd` files.

## A species' name: exactly one invented word (#717).
const ONE_WORD: String = Species.NAME_PATTERN
## The name rule of each kind of thing (#909), a pattern its name must match, its id in words
## (`mountain_pass` is Mountain Pass) for a thing with no name of its own. Each kind gets its own
## rules once they're signed off on #909; until then a kind's rule is "", which checks nothing.
## Kinds left out (tiles, items, loot tables, quests, dialogs) are vocabulary and stay descriptive.
const NAME_RULES: Dictionary[String, String] = {
	"species": ONE_WORD,
	"realm": "",
	"instance": "",
	"region": "",
	"piece": "", # a place inside its instance, named after it ("the pond of <instance>", #909)
	"place": "",
	"person": "",
	"faction": "",
	"ability": "",
	"gear": "",
}
## Terms two things share today, each with the issue that gives one of them another (#909). It
## only shrinks: a term that no longer clashes must be dropped from it.
const KNOWN_DUPLICATES: Dictionary[String, int] = {
	"forest": 909, # a tile kind and an instance, which gives it up when it's renamed
	"glade": 909, # an instance and its loot table, which keeps it when the instance is renamed
}

## Each term, in lower case, with every thing using it ("<kind> <id>").
var owners: Dictionary[String, PackedStringArray] = {}
## Each thing whose kind has a name rule ("<kind> <id>"), with why its name breaks it or "".
var broken: Dictionary[String, String] = {}


## Notes the thing of `kind` with `id` and its `name` ("" for none): its terms, and its name against
## its kind's rule.
func add(kind: String, id: String, name: String = "") -> void:
	var thing: String = "%s %s" % [kind, id]
	for term: String in [id.to_lower(), name.to_lower()]:
		if term.is_empty():
			continue
		var using: PackedStringArray = owners.get(term, PackedStringArray())
		if not using.has(thing):
			var _added: bool = using.append(thing)
			owners[term] = using
	var rule: String = NAME_RULES.get(kind, "")
	if not rule.is_empty():
		broken["%s %s" % [kind, id]] = _rule_problem(rule, id, name)


## Why the terms don't hold together, or "": a term two things share unless `duplicates` lists it
## (and then only those two), a listed term that no longer clashes, or a thing breaking its kind's
## name rule.
func problem(duplicates: Dictionary[String, int] = KNOWN_DUPLICATES) -> String:
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
		if not broken[thing].is_empty():
			return "%s: %s" % [thing, broken[thing]]
	return ""


## Every id and name the content holds, each with the thing it belongs to.
static func collected() -> ContentTerms:
	var terms: ContentTerms = ContentTerms.new()
	for tile: String in TileContent.load_tiles().tiles:
		terms.add("tile", tile)
	for species: Species in SpeciesContent.load_species().species.values():
		terms.add("species", species.id, species.name)
	for ability: Ability in AbilityContent.load_abilities().abilities.values():
		terms.add("ability", ability.id, ability.name)
	var gear: GearContent = GearContent.load_gear()
	for item: GearItem in gear.items.values():
		terms.add("gear", item.id, item.name)
	for faction: Faction in FactionContent.load_factions().factions.values():
		terms.add("faction", faction.id, faction.name)
	for quest: QuestDefinition in QuestContent.load_quests().quests.values():
		terms.add("quest", quest.id, quest.name)
	for realm: Realm in Realms.all():
		terms.add("realm", realm.id)
	_add_loot(terms, gear)
	_add_instances(terms, DialogContent.load_dialogs().dialogs)
	return terms


## Why a thing with this `id` and `name` breaks `rule`, or "": its name (its id in words when it has
## none) must match, and its id must be its name in lower case, words joined by `_` (#763).
static func _rule_problem(rule: String, id: String, name: String) -> String:
	var shown: String = name if not name.is_empty() else id.capitalize()
	if RegEx.create_from_string(rule).search(shown) == null:
		return "%s isn't a name its kind allows (#909)" % shown
	if id != shown.to_lower().replace(" ", "_"):
		return "its id must be its name in lower case (#763)"
	return ""


## The loot tables but a species' own, whose id is its species' (LootContent), and the items they
## drop: an item that's a piece of gear is that gear.
static func _add_loot(terms: ContentTerms, gear: GearContent) -> void:
	var species_kinds: Array[String] = [LootTable.SPECIES, LootTable.HARVEST]
	for directory: String in [LootContent.DIR, LootContent.HARVEST_DIR]:
		for table: LootTable in LootContent.load_loot_tables(directory).loot_tables.values():
			if not species_kinds.has(table.kind):
				terms.add("loot table", table.id)
			for item: String in table.items:
				if not item.is_empty():
					terms.add("gear" if gear.items.has(item) else "item", item)


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
				terms.add("region", chosen_by[1])
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
