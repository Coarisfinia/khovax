class_name LootTableFile
extends RefCounted
## Reads a loot table (LootTable, #90) from its content file (the loot slice's data/loot_tables/,
## #72, #412): checks its
## fields, its id against the file name, and that its chances add up to 100 %, and hands the rules
## the table's plain data.

## A loot table file's fields, as its schemas (slices/loot/data/loot_tables.schema.json and
## harvest_tables.schema.json beside it) allow them.
const FIELDS: Array[String] = ["id", "kind", "entries"]
const ITEM_FIELDS: Array[String] = ["item", "chance", "min", "max"]
const BLANK_FIELDS: Array[String] = ["blank", "chance"]


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
	if table.problem.is_empty() and not LootTable.KINDS.has(table.kind):
		table.problem = "its kind is one of %s" % [LootTable.KINDS]
	var raw: Variant = data.get("entries")
	var entries: Array = raw if raw is Array else []
	if table.problem.is_empty():
		table.problem = _read_entries(table, entries)
	return table


## Reads `entries` into `table`; returns what's wrong with them, or "".
static func _read_entries(table: LootTable, entries: Array) -> String:
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
			var index: int = table.items.size()
			return "entry %d needs a chance, and an item id with 1 <= min <= max" % index
		blanks += 1 if blank else 0
		total += chance
		table.items.append(item)
		table.chances.append(chance)
		table.mins.append(low)
		table.maxes.append(high)
	if total != Fixed.ONE:
		return "the chances add up to %d thousandths, not %d" % [total, Fixed.ONE]
	if blanks != (1 if table.kind in [LootTable.SPECIES, LootTable.HARVEST] else 0):
		return "a species or harvest table has exactly one blank, an instance or chest table none"
	return ""
