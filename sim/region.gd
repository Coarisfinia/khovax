class_name Region
extends RefCounted
## An instance's region (#36): which tiles exist, each one's terrain as a small integer, and where
## the players start. Rules ask the region, never the distance from the origin, so a region can have
## any shape. Regions are hand-made text files (regions/*.region, read with `parse`).

const GROUND: int = 0
const WATER: int = 1
const BLOCKED: int = 2
## The most tiles a region may have: generators and region files stay within it.
const MAX_TILES: int = 4096
## The characters of a region file, by terrain; a digit 1 to 4 is ground where that player starts.
const SYMBOLS: Dictionary[String, int] = { ".": GROUND, "~": WATER, "^": BLOCKED }
## Ground where a wild monster stands when the run begins (WildMonsterFeature, #19).
const WILD_MONSTER: String = "m"

## Every tile's terrain, by tile.
var terrain: Dictionary[Vector2i, int] = {}
## Where the players start, by slot.
var starts: Array[Vector2i] = []
## Where wild monsters stand when the run begins, in the region file's reading order.
var wild_monsters: Array[Vector2i] = []
## Why the region file couldn't be read, or "" when it could.
var problem: String = ""


## A disc of ground tiles of `radius` rings around the origin, with the players starting at its
## middle and around it.
static func disc(radius: int) -> Region:
	var region: Region = Region.new()
	for tile: Vector2i in Hex.disc(radius):
		region.terrain[tile] = GROUND
	region.starts = region.reachable(Vector2i.ZERO).slice(0, GameState.MAX_PLAYERS)
	return region


## A region read from a region file's text. Lines starting with `#` are comments. The first other
## line is `origin <column> <row>`: the character there is tile (0, 0). Every further line is one
## row r of the region, from the origin row's r = 0 down; a tile sits on every second column
## (doubled coordinates), so each row is offset by half a tile, as on screen. `.` is ground, `~`
## water, `^` blocked, a digit 1 to 4 a player's start on ground, `m` a wild monster on ground, and
## a space no tile.
static func parse(text: String) -> Region:
	var region: Region = Region.new()
	var rows: Array[String] = []
	for line: String in text.split("\n"):
		if not line.strip_edges().begins_with("#") and not line.strip_edges().is_empty():
			rows.append(line.trim_suffix("\r"))
	var header: PackedStringArray = PackedStringArray()
	if not rows.is_empty():
		header = rows[0].split(" ")
	var numbers: bool = header.size() == 3 and header[1].is_valid_int() and header[2].is_valid_int()
	if not numbers or header[0] != "origin":
		region.problem = "a region file starts with \"origin <column> <row>\""
		return region
	var starts_by_slot: Dictionary[int, Vector2i] = {}
	for i: int in range(1, rows.size()):
		region.problem = region._parse_row(
			rows[i],
			i - 1 - header[2].to_int(),
			header[1].to_int(),
			starts_by_slot,
		)
		if not region.problem.is_empty():
			return region
	for slot: int in starts_by_slot.size():
		if not starts_by_slot.has(slot):
			region.problem = "the player starts aren't numbered 1, 2, 3, … without gaps"
			return region
		region.starts.append(starts_by_slot[slot])
	return region


func has_tile(tile: Vector2i) -> bool:
	return terrain.has(tile)


## Whether a walker can stand on the tile: ground, and on the region.
func is_walkable(tile: Vector2i) -> bool:
	return terrain.get(tile, BLOCKED) == GROUND


func size() -> int:
	return terrain.size()


## The region's tiles, sorted, so their order never depends on how the region was built.
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


## Every value of the region, for the state hash, in a fixed order.
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
	values.append(wild_monsters.size())
	for spot: Vector2i in wild_monsters:
		values.append(spot.x)
		values.append(spot.y)
	return values


## Reads one row of a region file into the region; returns why it can't, or "".
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
		var known: bool = SYMBOLS.has(symbol) or symbol == WILD_MONSTER
		if not known and (slot < 0 or slot >= GameState.MAX_PLAYERS):
			return "'%s' in row %d isn't a region symbol" % [symbol, r]
		var tile: Vector2i = Vector2i(Fixed.div_floor(doubled, 2), r)
		terrain[tile] = SYMBOLS.get(symbol, GROUND)
		if symbol == WILD_MONSTER:
			wild_monsters.append(tile)
		if slot >= 0 and starts_by_slot.has(slot):
			return "player %d's start is marked twice" % (slot + 1)
		if slot >= 0:
			starts_by_slot[slot] = tile
	if terrain.size() > MAX_TILES:
		return "the region has more than %d tiles" % MAX_TILES
	return ""
