class_name HexMap
extends RefCounted
## An instance's map (#36): which tiles exist, each one's terrain as a small integer, and where the
## players start. Rules ask the map, never the distance from the origin, so a map can have any
## shape. Hand-made maps are text files (maps/*.map, read with `parse`); generated ones come from
## MapGenerator, from the instance's seed.

const GROUND: int = 0
const WATER: int = 1
const BLOCKED: int = 2
## The most tiles a map may have: generators and map files stay within it.
const MAX_TILES: int = 4096
## The characters of a map file, by terrain; a digit 1 to 4 is ground where that player starts.
const SYMBOLS: Dictionary[String, int] = { ".": GROUND, "~": WATER, "^": BLOCKED }

## Every tile's terrain, by tile.
var terrain: Dictionary[Vector2i, int] = {}
## Where the players start, by slot.
var starts: Array[Vector2i] = []
## Why the map file couldn't be read, or "" when it could.
var problem: String = ""


## A disc of ground tiles of `radius` rings around the origin, with the players starting at its
## middle and around it.
static func disc(radius: int) -> HexMap:
	var map: HexMap = HexMap.new()
	for tile: Vector2i in Hex.disc(radius):
		map.terrain[tile] = GROUND
	map.starts = map.reachable(Vector2i.ZERO).slice(0, GameState.MAX_PLAYERS)
	return map


## A map read from a map file's text. Lines starting with `#` are comments. The first other line
## is `origin <column> <row>`: the character there is tile (0, 0). Every further line is one row r
## of the map, from the origin row's r = 0 down; a tile sits on every second column (doubled
## coordinates), so each row is offset by half a tile, as on screen. `.` is ground, `~` water,
## `^` blocked, a digit 1 to 4 a player's start on ground, and a space no tile.
static func parse(text: String) -> HexMap:
	var map: HexMap = HexMap.new()
	var rows: Array[String] = []
	for line: String in text.split("\n"):
		if not line.strip_edges().begins_with("#") and not line.strip_edges().is_empty():
			rows.append(line.trim_suffix("\r"))
	var header: PackedStringArray = PackedStringArray()
	if not rows.is_empty():
		header = rows[0].split(" ")
	var numbers: bool = header.size() == 3 and header[1].is_valid_int() and header[2].is_valid_int()
	if not numbers or header[0] != "origin":
		map.problem = "a map file starts with \"origin <column> <row>\""
		return map
	var starts_by_slot: Dictionary[int, Vector2i] = {}
	for i: int in range(1, rows.size()):
		map.problem = map._parse_row(
			rows[i],
			i - 1 - header[2].to_int(),
			header[1].to_int(),
			starts_by_slot,
		)
		if not map.problem.is_empty():
			return map
	for slot: int in starts_by_slot.size():
		if not starts_by_slot.has(slot):
			map.problem = "the player starts aren't numbered 1, 2, 3, … without gaps"
			return map
		map.starts.append(starts_by_slot[slot])
	return map


func has_tile(tile: Vector2i) -> bool:
	return terrain.has(tile)


## Whether a walker can stand on the tile: ground, and on the map.
func is_walkable(tile: Vector2i) -> bool:
	return terrain.get(tile, BLOCKED) == GROUND


func size() -> int:
	return terrain.size()


## The map's tiles, sorted, so their order never depends on how the map was built.
func sorted_tiles() -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	sorted.assign(terrain.keys())
	sorted.sort()
	return sorted


## Every walkable tile a walker can reach from `start`, nearest first, in a fixed order.
func reachable(start: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if not is_walkable(start):
		return found
	var seen: Dictionary[Vector2i, bool] = { start: true }
	found.append(start)
	var next: int = 0
	while next < found.size():
		for direction: Vector2i in Hex.DIRECTIONS:
			var neighbor: Vector2i = found[next] + direction
			if not seen.has(neighbor) and is_walkable(neighbor):
				seen[neighbor] = true
				found.append(neighbor)
		next += 1
	return found


## Every value of the map, for the state hash, in a fixed order.
func hash_values() -> Array[int]:
	var values: Array[int] = [terrain.size()]
	for tile: Vector2i in sorted_tiles():
		values.append(tile.x)
		values.append(tile.y)
		values.append(terrain[tile])
	values.append(starts.size())
	for start: Vector2i in starts:
		values.append(start.x)
		values.append(start.y)
	return values


## Reads one row of a map file into the map; returns why it can't, or "".
func _parse_row(
	row: String,
	r: int,
	origin_column: int,
	starts_by_slot: Dictionary[int, Vector2i],
) -> String:
	for column: int in row.length():
		var symbol: String = row[column]
		if symbol == " ":
			continue
		# Doubled coordinates: column = 2q + r, counted from the origin's column.
		var doubled: int = column - origin_column - r
		var slot: int = symbol.to_int() - 1 if symbol.is_valid_int() else -1
		if posmod(doubled, 2) != 0:
			return "'%s' in row %d sits between two tiles" % [symbol, r]
		if not SYMBOLS.has(symbol) and (slot < 0 or slot >= GameState.MAX_PLAYERS):
			return "'%s' in row %d isn't a map symbol" % [symbol, r]
		var tile: Vector2i = Vector2i(Fixed.div_floor(doubled, 2), r)
		terrain[tile] = SYMBOLS.get(symbol, GROUND)
		if slot >= 0 and starts_by_slot.has(slot):
			return "player %d's start is marked twice" % (slot + 1)
		if slot >= 0:
			starts_by_slot[slot] = tile
	if terrain.size() > MAX_TILES:
		return "the map has more than %d tiles" % MAX_TILES
	return ""
