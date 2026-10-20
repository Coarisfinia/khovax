class_name RegionDocument
extends RefCounted
## A region or region piece as a Markdown file (#145), readable on its own and on GitHub: a title
## and prose explaining it, the tiles in a code block under `## Tiles`, and a `## Legend` list
## explaining every symbol. Tile (0, 0) is the middle tile of the middle row, so a grid has an odd
## number of rows and its middle row an odd number of tiles. Nothing refers to a tile by numbers:
## connectors, exits and named species are symbols in the grid, which the legend explains.
##
## Every tile is one wide emoji, as wide as two spaces in a monospace font, so the grid reads as a
## neat picture (#711): tiles sit side by side, and a space is half a tile, which offsets a row or
## leaves a gap (two spaces where a tile is missing). The legend explains every symbol, as a list
## item "- `X`: <meaning>"; a letter, digit or other narrow character is refused. Each meaning is
## one LegendMeaning reads, with the readers of what the slices place (PlacementReader), and the
## document builds its Region with them (#824).

const TILES: String = "## Tiles"
const LEGEND: String = "## Legend"
## Below this code point a character is narrow (letters, digits, punctuation), never a tile (#711).
const FIRST_WIDE: int = 0x2000
## The joiner and variation selectors that build an emoji out of several code points: a tile is one.
const JOINERS: Array[int] = [0x200d, 0xfe0e, 0xfe0f]


## The region a Markdown region document describes, with what the slices place read by `readers`
## (InstanceBlueprints hands every slice's over); its `problem` says what's wrong.
static func parse(text: String, readers: Array[PlacementReader] = []) -> Region:
	var rows: Array[String] = _grid(text)
	var narrow: String = _narrow(rows)
	if not narrow.is_empty():
		return _refused("a tile is one wide emoji, never `%s`" % narrow)
	for r: int in rows.size():
		rows[r] = _laid_out(rows[r])
	var origin: Vector2i = _origin(rows)
	if origin.y < 0:
		return _refused("the tiles need an odd number of rows, the middle one odd in tiles")
	var meanings: Dictionary[String, LegendMeaning] = _meanings(text, readers)
	var unexplained: String = _unexplained(rows, meanings)
	if not unexplained.is_empty():
		return _refused("the legend doesn't explain `%s`" % unexplained)
	var region: Region = Region.new()
	# Each drawn tile's meaning, in reading order: what stands on it is placed once all are laid.
	var drawn: Dictionary[Vector2i, LegendMeaning] = {}
	region.problem = _lay(region, rows, origin, meanings, drawn)
	if not region.problem.is_empty():
		return region
	region.problem = _starts(region, drawn)
	for tile: Vector2i in drawn:
		if region.problem.is_empty():
			region.problem = drawn[tile].place(region, tile)
	for reader: PlacementReader in readers:
		if region.problem.is_empty():
			region.problem = reader.problem_in(region)
	return region


## Lays the grid's `rows` onto `region`, each tile as its symbol's meaning says, and notes each in
## `drawn`; returns why it can't, or "". `origin` is where tile (0, 0) sits, as (column, row).
static func _lay(
	region: Region,
	rows: Array[String],
	origin: Vector2i,
	meanings: Dictionary[String, LegendMeaning],
	drawn: Dictionary[Vector2i, LegendMeaning],
) -> String:
	for row: int in rows.size():
		var r: int = row - origin.y
		for column: int in rows[row].length():
			var symbol: String = rows[row][column]
			# Doubled coordinates: column = 2q + r, counted from the origin's column.
			var doubled: int = column - origin.x - r
			if symbol != " " and posmod(doubled, 2) != 0:
				return "'%s' in row %d sits between two tiles" % [symbol, r]
			var tile: Vector2i = Vector2i(Fixed.div_floor(doubled, 2), r)
			if symbol != " ":
				drawn[tile] = meanings[symbol]
				var problem: String = meanings[symbol].lay(region, tile)
				if not problem.is_empty():
					return problem
		if region.terrain.size() > Region.MAX_TILES:
			return "the region has more than %d tiles" % Region.MAX_TILES
	return ""


## Sets `region`'s player starts from the tiles `drawn` as them, by slot; returns why it can't, or
## "": each player's start is drawn once, numbered 1, 2, 3, … without gaps.
static func _starts(region: Region, drawn: Dictionary[Vector2i, LegendMeaning]) -> String:
	var starts_by_slot: Dictionary[int, Vector2i] = {}
	for tile: Vector2i in drawn:
		var slot: int = drawn[tile].start
		if slot >= 0 and starts_by_slot.has(slot):
			return "player %d's start is marked twice" % (slot + 1)
		if slot >= 0:
			starts_by_slot[slot] = tile
	for slot: int in starts_by_slot.size():
		if not starts_by_slot.has(slot):
			return "the player starts aren't numbered 1, 2, 3, … without gaps"
		region.starts.append(starts_by_slot[slot])
	return ""


## The first symbol in `rows` whose meaning the legend doesn't give or LegendMeaning doesn't read,
## or "".
static func _unexplained(
	rows: Array[String],
	meanings: Dictionary[String, LegendMeaning],
) -> String:
	for row: String in rows:
		for symbol: String in row:
			if symbol != " " and meanings.get(symbol) == null:
				return symbol
	return ""


## The first narrow character in `rows`, a space aside, or a joiner, or "".
static func _narrow(rows: Array[String]) -> String:
	for row: String in rows:
		for symbol: String in row:
			var code: int = symbol.unicode_at(0)
			if symbol != " " and (code < FIRST_WIDE or JOINERS.has(code)):
				return symbol
	return ""


## Row `row` laid out by doubled column, one character per column: a space is half a tile, and each
## tile's emoji, two columns wide, takes its first column, with a space for its second.
static func _laid_out(row: String) -> String:
	var laid: String = ""
	for symbol: String in row:
		laid += symbol if symbol == " " else symbol + " "
	return laid


static func _refused(problem: String) -> Region:
	var region: Region = Region.new()
	region.problem = problem
	return region


## The rows of the code block under `## Tiles`.
static func _grid(text: String) -> Array[String]:
	var rows: Array[String] = []
	var section: String = _section(text, TILES)
	var inside: bool = false
	for line: String in section.split("\n"):
		var clean: String = line.trim_suffix("\r")
		if clean.begins_with("```"):
			if inside:
				break
			inside = true
		elif inside:
			rows.append(clean)
	return rows


## Every legend entry, by symbol: what LegendMeaning reads its meaning as, with `readers`, or null.
static func _meanings(
	text: String,
	readers: Array[PlacementReader],
) -> Dictionary[String, LegendMeaning]:
	var entries: Dictionary[String, LegendMeaning] = {}
	var pattern: RegEx = RegEx.create_from_string("^- `(.)`: (.+)$")
	for line: String in _section(text, LEGEND).split("\n"):
		var found: RegExMatch = pattern.search(line.strip_edges())
		if found != null:
			var meaning: String = found.get_string(2).strip_edges().trim_suffix(".")
			entries[found.get_string(1)] = LegendMeaning.read(meaning, readers)
	return entries


## The text under the heading `heading`, up to the next `## ` heading.
static func _section(text: String, heading: String) -> String:
	var start: int = text.find(heading + "\n")
	if start < 0:
		start = text.find(heading + "\r\n")
	if start < 0:
		return ""
	var body: String = text.substr(start + heading.length())
	var next: int = body.find("\n## ")
	return body if next < 0 else body.substr(0, next)


## Where tile (0, 0) sits in the grid, as (column, row): the middle tile of the middle row, or a
## negative row when there's no single middle.
static func _origin(rows: Array[String]) -> Vector2i:
	if rows.size() % 2 == 0:
		return Vector2i(0, -1)
	var middle: int = Fixed.div_floor(rows.size(), 2)
	var columns: Array[int] = []
	for column: int in rows[middle].length():
		if rows[middle][column] != " ":
			columns.append(column)
	if columns.size() % 2 == 0:
		return Vector2i(0, -1)
	return Vector2i(columns[Fixed.div_floor(columns.size(), 2)], middle)
