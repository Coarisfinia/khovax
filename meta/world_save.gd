class_name WorldSave
extends RefCounted
## The world's file (#119): the persistent world, saved next to the profile and apart from it, so
## loading the game puts every player back exactly where they were. Kept like every save
## (SaveStore, #179: an envelope with a checksum, older generations, written atomically). What's
## in it is World.to_data as JSON; reading it back turns JSON's numbers into whole numbers first,
## so the simulation only ever sees integers.

const PATH: String = "user://world.json"


## The world saved at `path`; null when there's none, or an empty world whose `problem` says why
## the save is refused (no intact generation, not a world, another format or rules version).
static func load_from(path: String = PATH) -> World:
	if not SaveStore.exists(path):
		return null
	var saved: SaveRead = SaveStore.read_save(path)
	if not saved.problem.is_empty():
		return World.refused(saved.problem)
	return parse(saved.text)


## Saves `world` at `path`; returns why it couldn't, or "".
static func save(world: World, path: String = PATH) -> String:
	return SaveStore.write_save(path, to_text(world))


static func to_text(world: World) -> String:
	return JSON.stringify(world.to_data())


## The world in `text`, or an empty one whose `problem` says why it's refused.
static func parse(text: String) -> World:
	# A JSON object reports a parse error through its result instead of logging it.
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary or not has_whole_numbers(parsed):
		return World.refused("not a world save, or it holds a number that isn't whole")
	var data: Dictionary = whole_numbers(parsed)
	return World.from_data(data)


## Whether every number in `value`, however deep in lists and tables, is whole and at most
## DataReader.MOST from zero, so `whole_numbers` turns it into an integer exactly.
static func has_whole_numbers(value: Variant) -> bool:
	if value is float:
		var number: float = value
		return number == floorf(number) and absf(number) <= DataReader.MOST
	if value is Array:
		var items: Array = value
		return items.all(has_whole_numbers)
	if value is Dictionary:
		var table: Dictionary = value
		return table.values().all(has_whole_numbers)
	return true


## `value` with every number in it an integer: JSON reads every number as a float. Only for a
## value `has_whole_numbers` holds for.
static func whole_numbers(value: Variant) -> Variant:
	if value is float:
		var whole: int = type_convert(value, TYPE_INT)
		return whole
	if value is Array:
		var items: Array = value
		return items.map(whole_numbers)
	if value is Dictionary:
		var table: Dictionary = value
		var converted: Dictionary = {}
		for key: Variant in table:
			converted[key] = whole_numbers(table[key])
		return converted
	return value
