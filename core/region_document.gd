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
## item "- `X`: <meaning>"; a letter, digit or other narrow character is refused. A meaning in
## BUILT_IN is one of RegionFormat.parse's own (ground, water, rock, a player's start, a wild
## monster of a rolled species, a treasure chest). Any other symbol is ground (a wild monster's spot
## for a named species), and its meaning is one of:
## - `joins another piece to the <side>`: a connector (#57)
## - `exit to the <side>, to <blueprint>`: an exit to another instance (#140)
## - `a wild monster, always <species id>`: a wild monster of a named species (#133); with
##   `, wounded` after it, it starts at a low share of its HP (#389); with
##   `, emitting <event name>` next, it emits that event when it faints (#541, EventEmitted); with
##   `, the quest target <id>` next, it's the one monster a quest's step asks for by that id
##   (#625, like a place's); with `, on <tile blueprint id>` last, it stands on a tile of that kind
##   rather than on ground (#452),
##   e.g. `a wild monster, always moss_toad, wounded, on sand` or
##   `a wild monster, always moss_toad, the quest target old_toad`
## - `a wild monster hiding in <tile blueprint id>`: a wild monster, of a species rolled from the
##   instance blueprint's list, on a tile of that kind, which must hide (#202), e.g. `a wild monster
##   hiding in shrubs`
## - `loot on the ground`: loot the first player to step here finds, every player in the instance
##   getting their own roll, like a chest's (#203)
## - `<what it is>; <when> <action>`: a tile trigger (#183), e.g. `a lookout; stepping here reveals
##   within 8`, with TileTrigger's whens and actions in words: `stepping here`,
##   `reveals within <n>`, `reaches the place <place id>` (#339: every tile of a place has it, e.g.
##   `the beach; stepping here reaches the place beach`). When what it is is a tile kind's meaning
##   (below), the tile is that kind too (#349), e.g. `forest; stepping here reaches the place grove`
## - `<tile blueprint id>`: a tile of that kind (#116), e.g. `forest`; any single character can
##   stand for it, an emoji too. Clauses after the kind, each after a ", ", change that tile:
##   `turned <n>` turns its decoration by n sixths of a turn, counter-clockwise (#231), so two
##   symbols can stand for the same kind turned apart, and `walkable` or `not walkable` overrides
##   its kind's trait for this tile (#201), e.g. `forest, not walkable`, and `height <n>` sets how
##   tall it stands for crowns above it (#232), in hundredths of a tile's radius, where its
##   models' measured height doesn't fit, e.g. `shrubs, height 40`
## where <side> is one of SIDES. The document is read into RegionFormat.parse's compact form.

const TILES: String = "## Tiles"
const LEGEND: String = "## Legend"
## A legend meaning placing loot on the ground (#203).
const LOOT_ON_THE_GROUND: String = "loot on the ground"
## A legend meaning placing a wild monster in a tile that hides it (#202), before the tile's kind.
const HIDING: String = "a wild monster hiding in "
## What ends a named wild monster's legend meaning when it stands on a tile kind (#452).
const ON: String = ", on "
## What a named wild monster's legend meaning says before the event it emits when it faints (#541).
const EMITTING: String = ", emitting "
## What a named wild monster's legend meaning says before the quest target it is (#625).
const TARGETED: String = ", the quest target "
## The clauses a named wild monster's legend meaning may have after its species and wounding, each
## with the word its species line carries it in.
const NAMED_CLAUSES: Dictionary[String, String] = {
	EMITTING: RegionFormat.EMITS,
	TARGETED: RegionFormat.TARGET,
}
## How a named wild monster's legend meaning begins.
const NAMED: String = "a wild monster, always "
## The sides of a tile, in Hex.DIRECTIONS' order.
const SIDES: Array[String] = ["east", "northeast", "northwest", "west", "southwest", "southeast"]
## The legend meanings that stand for RegionFormat.parse's own symbols, each with its symbol there.
const BUILT_IN: Dictionary[String, String] = {
	"ground": ".",
	"water": "~",
	"rock": "^",
	"where player 1 starts": "1",
	"where player 2 starts": "2",
	"where player 3 starts": "3",
	"where player 4 starts": "4",
	"a wild monster, of a species rolled from the instance blueprint's list": "m",
	"a treasure chest": "c",
}
## Below this code point a character is narrow (letters, digits, punctuation), never a tile (#711).
const FIRST_WIDE: int = 0x2000
## The joiner and variation selectors that build an emoji out of several code points: a tile is one.
const JOINERS: Array[int] = [0x200d, 0xfe0e, 0xfe0f]
## What a tile kind's legend meaning says, after the kind, to turn its decoration (#231) or to
## override its walkable trait (#201), each clause after a ", ".
const TURNED: String = "turned "
const WALKABLE: String = "walkable"
const NOT_WALKABLE: String = "not walkable"
const HEIGHT: String = "height "


## The region a Markdown region document describes; its `problem` says what's wrong.
static func parse(text: String) -> Region:
	var rows: Array[String] = _grid(text)
	var narrow: String = _narrow(rows)
	if not narrow.is_empty():
		return _refused("a tile is one wide emoji, never `%s`" % narrow)
	for r: int in rows.size():
		rows[r] = _laid_out(rows[r])
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
	return RegionFormat.parse("\n".join(compact))


## Row `rows[r]` with its legend symbols turned into what RegionFormat.parse reads there (ground, or
## a
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
		if BUILT_IN.has(legend.get(symbol, "")):
			compact[column] = BUILT_IN[legend[symbol]]
		elif symbol != " ":
			var tile: Vector2i = Vector2i(Fixed.div_floor(column - origin_column - r, 2), r)
			var line: String = _line(legend[symbol], tile)
			lines.append(line)
			var monster: bool = line.begins_with(RegionFormat.SPECIES)
			compact[column] = "m" if monster or legend[symbol].begins_with(HIDING) else "."
	return compact


## The first symbol in `rows` that isn't built in and that the legend doesn't explain, or "".
static func _unexplained(rows: Array[String], legend: Dictionary[String, String]) -> String:
	for row: String in rows:
		for column: int in row.length():
			var symbol: String = row[column]
			var meaning: String = legend.get(symbol, "")
			var explained: bool = (BUILT_IN.has(meaning)
					or not _line(meaning, Vector2i.ZERO).is_empty())
			if symbol != " " and not explained:
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
	var actions: Dictionary[String, String] = {
		"reveals within ": TileTrigger.REVEAL,
		"reaches the place ": TileTrigger.REACH,
	}
	for phrase: String in whens:
		var rest: String = clause.trim_prefix(phrase)
		for action: String in actions:
			var amount: String = rest.trim_prefix(action)
			var reach: bool = actions[action] == TileTrigger.REACH
			var known: bool = TileTrigger.is_place_id(amount) if reach else amount.is_valid_int()
			if clause.begins_with(phrase) and rest.begins_with(action) and known:
				return "%s%s %s %s %s" % [
					RegionFormat.TRIGGER,
					where,
					whens[phrase],
					actions[action],
					amount,
				]
	return ""


## The compact tile line a tile kind's legend meaning (`stump`, or `stump, turned 3, not walkable`)
## stands for on `where`, or "" when it names no tile blueprint or a clause isn't understood.
static func _tile_line(meaning: String, where: String) -> String:
	var clauses: PackedStringArray = meaning.split(", ")
	if TileKinds.number_of(clauses[0]) < 0:
		return ""
	var line: String = "%s%s %s" % [RegionFormat.TILE, where, clauses[0]]
	for clause: String in clauses.slice(1):
		var turn: String = clause.trim_prefix(TURNED)
		if clause.begins_with(TURNED) and turn.is_valid_int():
			line += " " + turn
		elif clause.begins_with(HEIGHT) and clause.trim_prefix(HEIGHT).is_valid_int():
			line += " " + RegionFormat.HEIGHT + clause.trim_prefix(HEIGHT)
		elif clause == WALKABLE or clause == NOT_WALKABLE:
			var override: String = RegionFormat.NOT_WALKABLE
			if clause == WALKABLE:
				override = RegionFormat.WALKABLE
			line += " " + override
		else:
			return ""
	return line


## The compact lines a legend meaning stands for on `tile`, or "" for a meaning not understood. A
## named wild monster standing on a tile kind (#452) is its species line, then the tile's; one
## emitting an event (#541) or a quest's target (#625) has it at the end of its species line.
static func _line(meaning: String, tile: Vector2i) -> String:
	for clause: String in NAMED_CLAUSES:
		if meaning.begins_with(NAMED) and meaning.contains(clause):
			var after: String = meaning.get_slice(clause, 1)
			var named: String = after.get_slice(", ", 0)
			var rest: String = meaning.get_slice(clause, 0) + after.trim_prefix(named)
			var lines: PackedStringArray = _line(rest, tile).split("\n")
			var species_line: bool = lines[0].begins_with(RegionFormat.SPECIES)
			if not species_line or not named.is_valid_ascii_identifier():
				return ""
			lines[0] += " " + NAMED_CLAUSES[clause] + named
			return "\n".join(lines)
	if not meaning.begins_with(NAMED) or not meaning.contains(ON):
		return _meaning_line(meaning, tile)
	var monster: String = _meaning_line(meaning.get_slice(ON, 0), tile)
	var kind: String = _tile_line(meaning.get_slice(ON, 1), "%d %d" % [tile.x, tile.y])
	if monster.is_empty() or kind.is_empty():
		return ""
	return monster + "\n" + kind


## The compact line any other legend meaning stands for on `tile`, or "" when not understood.
static func _meaning_line(meaning: String, tile: Vector2i) -> String:
	var where: String = "%d %d" % [tile.x, tile.y]
	# What lies on the tile: a tile kind, or loot on the ground.
	var placed: String = _tile_line(meaning, where)
	if meaning == LOOT_ON_THE_GROUND:
		placed = RegionFormat.LOOT + where
	var hides_in: String = meaning.trim_prefix(HIDING)
	if meaning.begins_with(HIDING) and TileKinds.hides(TileKinds.number_of(hides_in)):
		placed = "%s%s %s" % [RegionFormat.TILE, where, hides_in]
	if not placed.is_empty():
		return placed
	var words: PackedStringArray = meaning.replace(",", "").split(" ", false)
	var side: int = -1
	for word: String in words:
		side = SIDES.find(word) if side < 0 else side
	if meaning.begins_with("joins another piece to the ") and side >= 0:
		return "%s%s %d" % [RegionFormat.CONNECTOR, where, side]
	if meaning.begins_with("exit to the ") and side >= 0 and words.size() >= 6:
		return "%s%s %d %s" % [RegionFormat.EXIT, where, side, words[-1]]
	if meaning.begins_with("a wild monster, always ") and words.size() >= 5:
		# `a wild monster, always <species>, wounded`: it starts at a low share of its HP (#389).
		if words[-1] == RegionFormat.WOUNDED and words.size() >= 6:
			return "%s%s %s %s" % [RegionFormat.SPECIES, where, words[-2], RegionFormat.WOUNDED]
		return "%s%s %s" % [RegionFormat.SPECIES, where, words[-1]]
	# A trigger names what it is before the "; ", and its when and action after.
	if meaning.contains("; ") and not meaning.get_slice("; ", 0).strip_edges().is_empty():
		return _trigger_lines(meaning, where)
	return ""


## The compact lines a legend trigger (`a lookout; stepping here reveals within 8`) stands for on
## `where`, or "" when its clause isn't one TileTrigger knows: its trigger line, after a tile line
## when what it is names a tile kind (#349, `forest; stepping here reaches the place grove`).
static func _trigger_lines(meaning: String, where: String) -> String:
	var trigger: String = _trigger_line(meaning.get_slice("; ", 1), where)
	var kind: String = _tile_line(meaning.get_slice("; ", 0), where)
	if trigger.is_empty() or kind.is_empty():
		return trigger
	return kind + "\n" + trigger
