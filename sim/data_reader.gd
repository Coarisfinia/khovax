class_name DataReader
extends RefCounted
## Reads saved simulation data (#119): a Dictionary of whole numbers, strings, arrays and nested
## Dictionaries, as World.to_data writes it. Every read checks the value's type and range and gives
## a safe default when it doesn't hold, noting the first problem, so a world built from bad data is
## refused whole (World.from_data) rather than half-read or crashing. A reader of a nested value
## reports to the reader it came from, so the outermost one holds the first problem of them all.

## The largest whole number a save holds: JSON numbers are doubles, exact up to 2^53.
const MOST: int = 9_007_199_254_740_992

## What is read.
var data: Dictionary = {}
## The first problem met, or "" while every read held.
var problem: String = ""
## The reader this one was read from, which gets its problems; null for the outermost.
var _parent: DataReader = null


## A reader of `value`, which must be a Dictionary; `parent` gets its problems.
func _init(value: Variant, parent: DataReader = null) -> void:
	_parent = parent
	if value is Dictionary:
		data = value
	else:
		fail("a saved entry isn't a table of values")


## Notes `why`, unless an earlier problem was noted.
func fail(why: String) -> void:
	if _parent != null:
		_parent.fail(why)
	elif problem.is_empty():
		problem = why


## Whether any read so far, of this reader or any other of the same save, failed.
func failed() -> bool:
	return not problem.is_empty() if _parent == null else _parent.failed()


## The whole number under `key`, from `low` to `high`; `low` when it isn't one.
func whole(key: String, low: int, high: int) -> int:
	var value: Variant = data.get(key)
	if not value is int or value < low or value > high:
		fail("%s isn't a whole number from %d to %d" % [key, low, high])
		return low
	return value


## The whole numbers under `key`, each from `low` to `high`; empty when they aren't.
func wholes(key: String, low: int, high: int) -> Array[int]:
	var result: Array[int] = []
	var value: Variant = data.get(key)
	if not value is Array:
		fail("%s isn't a list" % key)
		return result
	var items: Array = value
	for item: Variant in items:
		if not item is int or item < low or item > high:
			fail("%s holds something other than whole numbers from %d to %d" % [key, low, high])
			result.clear()
			return result
		result.append(item)
	return result


## The text under `key`; "" when it isn't text.
func text(key: String) -> String:
	var value: Variant = data.get(key)
	if not value is String:
		fail("%s isn't text" % key)
		return ""
	return value


## A reader of the table under `key`.
func read(key: String) -> DataReader:
	return DataReader.new(data.get(key), self)


## A reader of every table in the list under `key`; empty when it isn't a list.
func entries(key: String) -> Array[DataReader]:
	var result: Array[DataReader] = []
	var value: Variant = data.get(key)
	if not value is Array:
		fail("%s isn't a list" % key)
		return result
	var items: Array = value
	for item: Variant in items:
		result.append(_child(item))
	return result


## The tiles under `key`, saved as q and r after one another, each a tile of `region`; empty
## when they aren't.
func tiles(key: String, region: Region) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var numbers: Array[int] = wholes(key, -MOST, MOST)
	if numbers.size() % 2 != 0:
		fail("%s holds half a tile" % key)
		return result
	for i: int in range(0, numbers.size(), 2):
		var tile: Vector2i = Vector2i(numbers[i], numbers[i + 1])
		if not region.has_tile(tile):
			fail("%s holds %s, which isn't a tile of the region" % [key, tile])
			result.clear()
			return result
		result.append(tile)
	return result


## `tiles` flattened into q and r after one another, as `tiles` reads them.
static func flat(tile_list: Array[Vector2i]) -> Array[int]:
	var numbers: Array[int] = []
	for tile: Vector2i in tile_list:
		numbers.append(tile.x)
		numbers.append(tile.y)
	return numbers


func _child(value: Variant) -> DataReader:
	return DataReader.new(value, self)
