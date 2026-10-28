class_name GearItem
extends RefCounted
## A piece of gear (#690), read from content data (the gear slice's data/, #72, #412): a
## player-facing name, the slot it goes into (GearSlots.SLOTS), its rarity (#291) and, for spikes
## in the trap slot, their damage (SpikesFeature, #692), and, for gear in the ward slot, whether it
## keeps the player's carried monsters' passives on while they aren't out (#617,
## CompanionPassives). The other slots' effects come with their own issues.

## Its schema, which says the fields a gear file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/gear/data/gear.schema.json"
## The slot whose gear, spikes, has damage (#692).
const TRAP: String = "trap"
## The slot whose gear may keep the passives on (#617).
const WARD: String = "ward"
## The rarity of uniques and artifacts (#291): only such gear keeps the passives on (#617).
const UNIQUE: String = "bound"
## The rarities (#291), lowest to highest, then bound for uniques and artifacts.
const RARITIES: Array[String] = ["loose", "knotted", "warded", "sealed", "unbroken", "bound"]

var id: String = ""
## The player-facing name. It may hold text tags (#733), so whatever shows it shows it through
## TextTags.shown (#752).
var name: String = ""
## The slot it goes into, one of GearSlots.SLOTS.
var slot: String = ""
## Its rarity, one of RARITIES.
var rarity: String = ""
## The damage spikes deal each time they hurt a wild monster pushing on the ring (#692), a whole
## amount; 0 for gear of another slot.
var damage: int = 0
## Whether, in the ward slot, it keeps the passives of every monster the player carries on, out or
## not (#617, GearRequests tells the world); false for most gear.
var keeps_passives: bool = false
## Why the gear couldn't be read, or "" when it could.
var problem: String = ""


## A piece of gear read from a gear file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> GearItem:
	var item: GearItem = GearItem.new()
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		item.problem = Content.NOT_AN_OBJECT
		return item
	var data: Dictionary = parsed
	item.id = Content.text_of(data.get("id"))
	item.name = Content.text_of(data.get("name"))
	item.slot = Content.text_of(data.get("slot"))
	item.rarity = Content.text_of(data.get("rarity"))
	item.damage = Content.amount(data.get("damage"))
	item.keeps_passives = data.get("keeps_passives") == true
	if data.has("damage") and item.damage == 0:
		item.problem = "its damage must be a whole number from 1 to %d" % Fixed.MAX_AMOUNT
		return item
	item.problem = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if item.problem.is_empty():
		item.problem = item._check(file_id)
	return item


## The gear's name, its text tags showing the names they stand for (#752), and rarity, in words.
func described() -> String:
	return "%s (%s)" % [TextTags.shown(name), rarity.capitalize()]


## Why the read fields are wrong, or "".
func _check(file_id: String) -> String:
	var wrong_id: String = Content.id_problem(id, file_id)
	if not wrong_id.is_empty():
		return wrong_id
	if name.strip_edges().is_empty():
		return "it needs a name"
	if not GearSlots.SLOTS.has(slot):
		return "its slot must be one of %s" % [GearSlots.SLOTS]
	if not RARITIES.has(rarity):
		return "its rarity must be one of %s" % [RARITIES]
	if (damage > 0) != (slot == TRAP):
		return "spikes, in the trap slot, need damage, and no other gear has any"
	if keeps_passives and (slot != WARD or rarity != UNIQUE):
		return "only unique ward gear, of rarity %s, keeps the passives on" % UNIQUE
	return ""
