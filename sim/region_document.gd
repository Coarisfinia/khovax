class_name RegionDocument
extends RefCounted
## A region or region piece as a Markdown file (#145), readable on its own and on GitHub: a title
## and prose explaining it, the tiles in a code block under `## Tiles`, and a `## Legend` list
## explaining every symbol. Tile (0, 0) is the middle tile of the middle row, so a grid has an odd
## number of rows and its middle row an odd number of tiles. Nothing refers to a tile by numbers:
## connectors, exits and named species are symbols in the grid, which the legend explains.
##
## Region.parse's symbols need no legend entry (`.` ground, `~` water, `^` rock, `1`-`4` players'
## starts, `m` a wild monster, `c` a treasure chest), though one may describe them. Any other
## symbol is ground (a wild monster's spot for a named species) and its legend entry says what it
## is, as a list item "- `X`: <meaning>", the meaning being one of:
## - `joins another piece to the <side>`: a connector (#57)
## - `exit to the <side>, to <blueprint>`: an exit to another instance (#140)
## - `a wild monster, always <species id>`: a wild monster of a named species (#133)
## - `<what it is>; <when> <action>`: a tile trigger (#183), e.g. `a lookout; stepping here reveals
##   within 8`, with TileTrigger's whens and actions in words: `stepping here`, `reveals within <n>`
## - `<tile blueprint id>`: a tile of that kind (#116), e.g. `forest`; any single character can
##   stand for it, an emoji too. `<tile blueprint id>, turned <n>` turns its decoration by n sixths
##   of a turn, counter-clockwise (#231), so two symbols can stand for the same kind turned apart
## where <side> is one of SIDES. The document is read into Region.parse's compact form.

const TILES: String = "## Tiles"
const LEGEND: String = "## Legend"
## The sides of a tile, in Hex.DIRECTIONS' order.
const SIDES: Array[String] = ["east", "northeast", "northwest", "west", "southwest", "southeast"]
const BUILT_IN: String = ".~^1234mc"
## What a tile kind's legend meaning says before its decoration's turn.
const TURNED: String = ", turned "


## The region a Markdown region document describes; its `problem` says what's wrong.
static func parse(text: String) -> Region:
	var rows: Array[String] = _grid(text)
	var origin: Vector2i = _origin(rows)
	if origin.y < 0:
		return _refused("the tiles need an odd number of rows, the middle one odd in tiles")
	var legend: Dictionary[String, String] = _legend(text)
	var unexplained: String = _unexplained(rows, legend)
	if not unexplained.is_empty():
		return _refused("the legend doesn't explain `%s`" % unexplained)
	var lines: Array[String] = []
	var compact: Array[String] = ["origin %d %d" % [origin.x, origin.y]]
	for r: int in rows.size():
		compact.append(_compact_row(rows[r], r - origin.y, origin.x, legend, lines))
	compact.append_array(lines)
	return Region.parse("\n".join(compact))


## Row `rows[r]` with its legend symbols turned into what Region.parse reads there (ground, or a
## wild monster's spot), adding each symbol's compact line to `lines`. `r` counts from the origin's
## row, and `origin_column` is the origin's column.
static func _compact_row(
	row: String,
	r: int,
	origin_column: int,
	legend: Dictionary[String, String],
	lines: Array[String],
) -> String:
	var compact: String = row
	for column: int in row.length():
		var symbol: String = row[column]
		if symbol != " " and not BUILT_IN.contains(symbol):
			var tile: Vector2i = Vector2i(Fixed.div_floor(column - origin_column - r, 2), r)
			var line: String = _line(legend[symbol], tile)
			lines.append(line)
			compact[column] = "m" if line.begins_with(Region.SPECIES) else "."
	return compact


## The first symbol in `rows` that isn't built in and that the legend doesn't explain, or "".
static func _unexplained(rows: Array[String], legend: Dictionary[String, String]) -> String:
	for row: String in rows:
		for column: int in row.length():
			var symbol: String = row[column]
			var custom: bool = symbol != " " and not BUILT_IN.contains(symbol)
			var meaning: String = legend.get(symbol, "")
			if custom and _line(meaning, Vector2i.ZERO).is_empty():
				return symbol
	return ""


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


## Every legend entry, by symbol: its meaning.
static func _legend(text: String) -> Dictionary[String, String]:
	var entries: Dictionary[String, String] = {}
	var pattern: RegEx = RegEx.create_from_string("^- `(.)`: (.+)$")
	for line: String in _section(text, LEGEND).split("\n"):
		var found: RegExMatch = pattern.search(line.strip_edges())
		if found != null:
			entries[found.get_string(1)] = found.get_string(2).strip_edges().trim_suffix(".")
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


## The compact trigger line a legend trigger's clause (`stepping here reveals within 8`) stands for
## on `where`, or "" when it isn't one TileTrigger knows.
static func _trigger_line(clause: String, where: String) -> String:
	var whens: Dictionary[String, String] = { "stepping here ": TileTrigger.STEP }
	var actions: Dictionary[String, String] = { "reveals within ": TileTrigger.REVEAL }
	for phrase: String in whens:
		var rest: String = clause.trim_prefix(phrase)
		for action: String in actions:
			var amount: String = rest.trim_prefix(action)
			if clause.begins_with(phrase) and rest.begins_with(action) and amount.is_valid_int():
				return "%s%s %s %s %s" % [
					Region.TRIGGER,
					where,
					whens[phrase],
					actions[action],
					amount,
				]
	return ""


## The compact tile line a tile kind's legend meaning (`stump`, or `stump, turned 3`) stands for on
## `where`, or "" when it names no tile blueprint.
static func _tile_line(meaning: String, where: String) -> String:
	var kind: String = meaning.get_slice(TURNED, 0)
	var turn: String = meaning.get_slice(TURNED, 1)
	if TileKinds.number_of(kind) < 0:
		return ""
	if not meaning.contains(TURNED):
		return "%s%s %s" % [Region.TILE, where, kind]
	return "%s%s %s %s" % [Region.TILE, where, kind, turn] if turn.is_valid_int() else ""


## The compact line a legend meaning stands for on `tile`, or "" for a meaning not understood.
static func _line(meaning: String, tile: Vector2i) -> String:
	var where: String = "%d %d" % [tile.x, tile.y]
	if not _tile_line(meaning, where).is_empty():
		return _tile_line(meaning, where)
	var words: PackedStringArray = meaning.replace(",", "").split(" ", false)
	var side: int = -1
	for word: String in words:
		side = SIDES.find(word) if side < 0 else side
	if meaning.begins_with("joins another piece to the ") and side >= 0:
		return "%s%s %d" % [Region.CONNECTOR, where, side]
	if meaning.begins_with("exit to the ") and side >= 0 and words.size() >= 6:
		return "%s%s %d %s" % [Region.EXIT, where, side, words[-1]]
	if meaning.begins_with("a wild monster, always ") and words.size() >= 5:
		return "%s%s %s" % [Region.SPECIES, where, words[-1]]
	# A trigger names what it is before the "; ", and its when and action after.
	if meaning.contains("; ") and not meaning.get_slice("; ", 0).strip_edges().is_empty():
		return _trigger_line(meaning.get_slice("; ", 1), where)
	return ""
