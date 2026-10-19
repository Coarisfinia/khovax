# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (JSON's numbers arrive as floats, #589)
class_name JsonNumbers
extends RefCounted
## Turns JSON's numbers into whole numbers (#589): Godot's JSON parser reads every number as a
## float, so every reader of content and saves takes its integers from here, and this is the one
## place that touches a float. A whole number up to 2^52 converts exactly on every platform, so the
## result is deterministic; a fraction or an out-of-range number is refused instead of rounded.


## `value` as an integer when it's a whole JSON number from `low` to `high`, or `otherwise`.
static func whole(value: Variant, low: int, high: int, otherwise: int) -> int:
	if not (value is int or value is float):
		return otherwise
	var number: float = value
	if number != floorf(number) or number < low or number > high:
		return otherwise
	var converted: int = type_convert(value, TYPE_INT)
	return converted


## Whether every number in `value`, however deep in lists and tables, is whole and at most
## DataReader.MOST from zero, so `wholes` turns it into an integer exactly.
static func all_whole(value: Variant) -> bool:
	if value is float:
		var number: float = value
		return number == floorf(number) and absf(number) <= DataReader.MOST
	if value is Array:
		var items: Array = value
		return items.all(all_whole)
	if value is Dictionary:
		var table: Dictionary = value
		return table.values().all(all_whole)
	return true


## `value` with every number in it an integer. Only for a value `all_whole` holds for.
static func wholes(value: Variant) -> Variant:
	if value is float:
		var converted: int = type_convert(value, TYPE_INT)
		return converted
	if value is Array:
		var items: Array = value
		return items.map(wholes)
	if value is Dictionary:
		var table: Dictionary = value
		var made: Dictionary = {}
		for key: Variant in table:
			made[key] = wholes(table[key])
		return made
	return value
