class_name Blueprint
extends RefCounted
## An instance blueprint's content data (#823), read from the blueprints slice's data/ (#72, #412):
## the rules its instances have (its rule set's, #941, with the ones it adds or drops), whether the
## seed turns its region pieces, its loot tables, the
## species its wild monsters roll from and the variants the world's flags choose. InstanceBlueprints
## builds instances from it.

## Its schema, which says the fields a blueprint file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/blueprints/data/blueprints.schema.json"

var id: String = ""
## Its rule set's id (RuleSet, #941).
var rules: String = ""
## The ids of the rules its instances have (FeatureFactories): its rule set's in the order written,
## less the ones it drops, then the ones it adds; they step in FeatureFactories' order. What its
## region holds brings the rest (RegionFeatures, #879).
var features: Array[String] = []
## Whether the seed turns its region pieces (#57, #127).
var turned: bool = false
## Its instance loot table's id, what a blank and the loot on its ground give, or "".
var loot_table: String = ""
## Its chest loot table's id, what its chests hold (#694), or "" for no chests.
var chest_table: String = ""
## The species its unnamed wild monster spots roll from (#133): species id to weight, in the order
## written, which is the order they're rolled in.
var wild_species: Dictionary[String, int] = {}
## Its variants (#529, #541), in the order written: each a world flag and the region it chooses,
## "" for the blueprint's own; the first whose flag the world has set chooses.
var variants: Array[PackedStringArray] = []
## Why the blueprint couldn't be read, or "" when it could.
var problem: String = ""


## A blueprint read from a blueprint file's text, named `file_id`, its rules from one of
## `rule_sets` (by id); its `problem` says what's wrong.
static func parse(
	file_id: String,
	text: String,
	rule_sets: Dictionary[String, RuleSet],
) -> Blueprint:
	var read: Blueprint = Blueprint.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		read.problem = "not a JSON object"
		return read
	var data: Dictionary = json.data
	read.id = Content.text_of(data.get("id"))
	read.loot_table = Content.text_of(data.get("loot_table"))
	read.chest_table = Content.text_of(data.get("chest_table"))
	read.rules = Content.text_of(data.get("rules"))
	read.problem = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if read.problem.is_empty():
		read.problem = read._check(file_id, data)
	if read.problem.is_empty():
		read.problem = read._read_rules(data, rule_sets)
	return read


## Why the fields in `data` are wrong, or "", and its turn, species and variants read when
## they aren't.
func _check(file_id: String, data: Dictionary) -> String:
	if id != file_id or not Content.is_id(id):
		return "its id must match the file name and be lowercase words with underscores"
	var raw_turned: Variant = data.get("turned", false)
	if not raw_turned is bool:
		return "turned must be true or false"
	turned = raw_turned
	for table: String in ["loot_table", "chest_table"]:
		if data.has(table) and not Content.is_id(Content.text_of(data[table])):
			return "its %s must be a loot table's id" % table
	if not chest_table.is_empty() and loot_table.is_empty():
		return "a blueprint with a chest table needs a loot table, for the loot on its ground"
	if not _read_species(data.get("wild_species")):
		return "its wild_species must give one or more species ids a whole weight of 1 or more"
	if not _read_variants(data.get("variants", [])):
		return "its variants must each be a flag and a region id, or \"\" for its own"
	return ""


## Why its rules in `data` are wrong, or "": its rule set must be one of `rule_sets`, each rule it
## drops one the set has, each it adds one the set lacks (RuleSet.read_rules), and at least one
## must be left. Reads them into `features` when they aren't.
func _read_rules(data: Dictionary, rule_sets: Dictionary[String, RuleSet]) -> String:
	if not rule_sets.has(rules):
		return "its rules must be a rule set's id, %s isn't" % rules
	var in_set: Array[String] = rule_sets[rules].features
	var drops: Array[String] = []
	var adds: Array[String] = []
	var dropped: bool = RuleSet.read_rules(data.get("drop_rules", []), drops)
	if not dropped or drops.any(func(rule: String) -> bool: return not in_set.has(rule)):
		return "its drop_rules must each be a rule its rule set has, once"
	var added: bool = RuleSet.read_rules(data.get("add_rules", []), adds)
	if not added or adds.any(func(rule: String) -> bool: return in_set.has(rule)):
		return "its add_rules must each be a rule's feature id its rule set lacks, once"
	features.assign(in_set.filter(func(kept: String) -> bool: return not drops.has(kept)))
	features.append_array(adds)
	if features.is_empty():
		return "its rules must leave at least one rule"
	return ""


## Whether `raw` gives one or more species ids a weight; reads them into `wild_species`.
func _read_species(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var entries: Dictionary = raw
	# JSON reads an object into a Dictionary in the order it's written, which a Dictionary keeps,
	# the same on every platform. Content.amount takes only whole weights, 1 to Fixed.MAX_AMOUNT.
	for species_id: Variant in entries:
		var weight: int = Content.amount(entries[species_id])
		if not Content.is_id(str(species_id)) or weight == 0:
			return false
		wild_species[str(species_id)] = weight
	return not wild_species.is_empty()


## Whether `raw` lists variants, each a flag and a region; reads them into `variants`.
func _read_variants(raw: Variant) -> bool:
	if not raw is Array:
		return false
	var fields: Array[String] = SchemaFields.at(SCHEMA, "/properties/variants/items")
	var entries: Array = raw
	for entry: Variant in entries:
		if not entry is Dictionary:
			return false
		var variant: Dictionary = entry
		var flag: String = Content.text_of(variant.get("flag"))
		var raw_region: Variant = variant.get("region")
		var region: String = Content.text_of(raw_region)
		if (
			not Content.unknown_field(variant, fields).is_empty()
			or flag.strip_edges().is_empty()
			or not raw_region is String
			or not (region.is_empty() or Content.is_id(region))
		):
			return false
		variants.append(PackedStringArray([flag, region]))
	return true
