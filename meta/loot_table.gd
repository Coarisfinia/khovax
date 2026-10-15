class_name LootTable
extends RefCounted
## What a roll can give (#90), read from content data (data/loot_tables/, #72). Each entry is an
## item in an amount from `min` to `max`, or the blank, with a chance in thousandths; the chances
## add up to Fixed.ONE (100 %). A species table (#86) always holds one blank, which rolls on the
## instance's table instead, so a blank is never nothing (owner, #90). An instance table holds
## none. Rolls draw from the Rng they're given, so the same stream rolls the same loot.

const SPECIES: String = "species"
const INSTANCE: String = "instance"
const KINDS: Array[String] = [SPECIES, INSTANCE]
## A loot table file's fields, as its schema (data/schemas/loot_tables.schema.json) allows them.
const FIELDS: Array[String] = ["id", "kind", "entries"]
const ITEM_FIELDS: Array[String] = ["item", "chance", "min", "max"]
const BLANK_FIELDS: Array[String] = ["blank", "chance"]

var id: String = ""
var kind: String = ""
## Each entry's item id, or "" for the blank.
var items: Array[String] = []
## Each entry's chance, in thousandths.
var chances: Array[int] = []
## Each entry's smallest and largest amount (both 0 for the blank).
var mins: Array[int] = []
var maxes: Array[int] = []
## Why the table couldn't be read, or "" when it could.
var problem: String = ""


## A table read from a loot table file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> LootTable:
	var table: LootTable = LootTable.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		table.problem = "not a JSON object"
		return table
	var data: Dictionary = json.data
	table.problem = Content.unknown_field(data, FIELDS)
	table.id = Content.text_of(data.get("id"))
	table.kind = Content.text_of(data.get("kind"))
	if table.problem.is_empty() and (table.id != file_id or not Content.is_id(table.id)):
		table.problem = "its id must match the file name and be lowercase words with underscores"
	if table.problem.is_empty() and not KINDS.has(table.kind):
		table.problem = "its kind is species or instance"
	var raw: Variant = data.get("entries")
	var entries: Array = raw if raw is Array else []
	if table.problem.is_empty():
		table.problem = table._read_entries(entries)
	return table


## Rolls one entry: its item and amount, as {item: amount}. A blank rolls on `instance_table`.
func roll(rng: Rng, instance_table: LootTable) -> Dictionary[String, int]:
	var picked: int = rng.pick_weighted(chances)
	if items[picked].is_empty():
		return instance_table.roll(rng, null)
	return { items[picked]: rng.between(mins[picked], maxes[picked]) }


func _read_entries(entries: Array) -> String:
	var blanks: int = 0
	var total: int = 0
	for entry: Variant in entries:
		var fields: Dictionary = entry if entry is Dictionary else { }
		var blank: bool = fields.get("blank") is bool and fields["blank"]
		var unknown: String = Content.unknown_field(fields, BLANK_FIELDS if blank else ITEM_FIELDS)
		if not unknown.is_empty():
			return unknown
		var chance: int = Content.amount(fields.get("chance"))
		var low: int = 0 if blank else Content.amount(fields.get("min"))
		var high: int = 0 if blank else Content.amount(fields.get("max"))
		var item: String = "" if blank else Content.text_of(fields.get("item"))
		if chance < 1 or (not blank and (not Content.is_id(item) or low < 1 or high < low)):
			return "entry %d needs a chance, and an item id with 1 <= min <= max" % items.size()
		blanks += 1 if blank else 0
		total += chance
		items.append(item)
		chances.append(chance)
		mins.append(low)
		maxes.append(high)
	if total != Fixed.ONE:
		return "the chances add up to %d thousandths, not %d" % [total, Fixed.ONE]
	if blanks != (1 if kind == SPECIES else 0):
		return "a species table has exactly one blank, an instance table none"
	return ""
