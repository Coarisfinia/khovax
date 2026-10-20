class_name EmojiGrid
extends RefCounted
## A picture drawn in emoji in a Markdown file, readable on its own and on GitHub (#145, #865): a
## grid of hex tiles in a code block under `## Tiles`, and a `## Legend` list explaining every
## symbol. Region files read through it (RegionDocument), each file bringing only its own legend
## meanings; the grid itself means nothing here.
##
## Every tile is one wide emoji, as wide as two spaces in a monospace font, so the grid reads as a
## neat picture (#711): tiles sit side by side, and a space is half a tile, which offsets a row or
## leaves a gap (two spaces where a tile is missing). A letter, digit or other narrow character is
## refused. Tile (0, 0) is the middle tile of the middle row, so a grid has an odd number of rows
## and its middle row an odd number of tiles. The legend explains each symbol as a list item
## "- `X`: <meaning>".

const TILES: String = "## Tiles"
const LEGEND: String = "## Legend"
## Below this code point a character is narrow (letters, digits, punctuation), never a tile (#711).
const FIRST_WIDE: int = 0x2000
## The joiner and variation selectors that build an emoji out of several code points: a tile is one.
const JOINERS: Array[int] = [0x200d, 0xfe0e, 0xfe0f]

## Each drawn tile's symbol, in reading order.
var symbols: Dictionary[Vector2i, String] = {}
## Each legend entry's meaning, by symbol, without its closing full stop.
var legend: Dictionary[String, String] = {}
## Why the grid can't be read, or "".
var problem: String = ""


## The grid drawn under `## Tiles` in the Markdown `text`, with its legend; its `problem` says
## what's wrong.
static func read(text: String) -> EmojiGrid:
	var grid: EmojiGrid = EmojiGrid.new()
	var rows: Array[String] = _rows(_section(text, TILES))
	var narrow: String = _narrow(rows)
	if not narrow.is_empty():
		grid.problem = "a tile is one wide emoji, never `%s`" % narrow
		return grid
	for r: int in rows.size():
		rows[r] = _laid_out(rows[r])
	var origin: Vector2i = _origin(rows)
	if origin.y < 0:
		grid.problem = "the tiles need an odd number of rows, the middle one odd in tiles"
		return grid
	grid.legend = _legend(text)
	grid.problem = grid._place(rows, origin)
	return grid


## The first drawn symbol, in reading order, that `known` has no meaning for (none, or null), or
## "".
func unexplained(known: Dictionary) -> String:
	for tile: Vector2i in symbols:
		if known.get(symbols[tile]) == null:
			return symbols[tile]
	return ""


## Notes each symbol of the laid-out `rows` on its tile; returns why it can't, or "". `origin` is
## where tile (0, 0) sits, as (column, row).
func _place(rows: Array[String], origin: Vector2i) -> String:
	for row: int in rows.size():
		var r: int = row - origin.y
		for column: int in rows[row].length():
			var symbol: String = rows[row][column]
			# Doubled coordinates: column = 2q + r, counted from the origin's column.
			var doubled: int = column - origin.x - r
			if symbol != " " and posmod(doubled, 2) != 0:
				return "'%s' in row %d sits between two tiles" % [symbol, r]
			if symbol != " ":
				symbols[Vector2i(Fixed.div_floor(doubled, 2), r)] = symbol
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


## The rows of the first code block in `section`.
static func _rows(section: String) -> Array[String]:
	var rows: Array[String] = []
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


## Every legend entry's meaning, by symbol.
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
