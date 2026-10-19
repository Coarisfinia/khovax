class_name GearItem
extends RefCounted
## A piece of gear (#690), read from content data (the gear slice's data/, #72, #412): a
## player-facing name, the slot it goes into (GearSlots.SLOTS) and its rarity (#291). It has no
## effect yet: each slot's comes with its own issue.

## A gear file's fields, as its schema (slices/gear/data/gear.schema.json) allows them.
const FIELDS: Array[String] = ["id", "name", "slot", "rarity"]
## The rarities (#291), lowest to highest, then bound for uniques and artifacts.
const RARITIES: Array[String] = ["loose", "knotted", "warded", "sealed", "unbroken", "bound"]

var id: String = ""
## The player-facing name.
var name: String = ""
## The slot it goes into, one of GearSlots.SLOTS.
var slot: String = ""
## Its rarity, one of RARITIES.
var rarity: String = ""
## Why the gear couldn't be read, or "" when it could.
var problem: String = ""


## A piece of gear read from a gear file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> GearItem:
	var item: GearItem = GearItem.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		item.problem = "not a JSON object"
		return item
	var data: Dictionary = json.data
	item.id = Content.text_of(data.get("id"))
	item.name = Content.text_of(data.get("name"))
	item.slot = Content.text_of(data.get("slot"))
	item.rarity = Content.text_of(data.get("rarity"))
	item.problem = Content.unknown_field(data, FIELDS)
	if item.problem.is_empty():
		item.problem = item._check(file_id)
	return item


## The gear's name and rarity, in words.
func described() -> String:
	return "%s (%s)" % [name, rarity.capitalize()]


## Why the read fields are wrong, or "".
func _check(file_id: String) -> String:
	if id != file_id or not Content.is_id(id):
		return "its id must match the file name and be lowercase words with underscores"
	if name.strip_edges().is_empty():
		return "it needs a name"
	if not GearSlots.SLOTS.has(slot):
		return "its slot must be one of %s" % [GearSlots.SLOTS]
	if not RARITIES.has(rarity):
		return "its rarity must be one of %s" % [RARITIES]
	return ""
