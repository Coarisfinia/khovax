class_name Region
extends RefCounted
## An instance's region (#36): which tiles exist, each one's kind (a tile blueprint, numbered by
## TileKinds, #116), and where the players start. Rules ask the region, never the distance from
## the origin, so a region can have any shape. Regions are hand-made Markdown files (regions/*.md,
## read by RegionDocument into the
## compact form `parse` reads, #145).

## The built-in kinds' numbers, as data/tiles/ gives them; rock blocks sight (FogFeature).
const GROUND: int = 0
const WATER: int = 1
const BLOCKED: int = 2
## The most tiles a region may have: generators and region files stay within it.
const MAX_TILES: int = 4096
## The characters of a region file, by terrain; a digit 1 to 4 is ground where that player starts.
const SYMBOLS: Dictionary[String, int] = { ".": GROUND, "~": WATER, "^": BLOCKED }
## Ground where a wild monster stands when the instance loads (WildMonsterFeature, #19).
const WILD_MONSTER: String = "m"
## Ground where a treasure chest stands, placed by hand (ChestFeature, #124).
const CHEST: String = "c"
## The start of a region piece's connector line.
const CONNECTOR: String = "connector "
## The start of a region piece's exit line (#140).
const EXIT: String = "exit "
## The start of a line naming a wild monster spot's species (#133).
const SPECIES: String = "species "
## The start of a tile trigger's line (#181, #183).
const TRIGGER: String = "trigger "
## The start of a line placing a tile blueprint on a tile (#116).
const TILE: String = "tile "
## What a tile line says to override its kind's walkable trait for that one tile (#201).
const WALKABLE: String = "walkable"
const NOT_WALKABLE: String = "not_walkable"

## Every tile's kind, its number in TileKinds, by tile.
var terrain: Dictionary[Vector2i, int] = {}
## How far a tile's decoration is turned, in sixths of a turn counter-clockwise like Hex.turn, for
## the tiles whose piece turns it by hand (#231); it turns with the region. A look, not a rule:
## not hashed, and only the views read it.
var decoration_turns: Dictionary[Vector2i, int] = {}
## Placed tiles whose piece overrides their kind's walkable trait (#201): whether walkers can stand
## on each. A rule, so it's hashed with the tiles.
var walkable_overrides: Dictionary[Vector2i, bool] = {}
## Where the players start, by slot.
var starts: Array[Vector2i] = []
## Where wild monsters stand when the instance loads, in the region file's reading order.
var wild_monsters: Array[Vector2i] = []
## The species a region piece names for some of its wild monster spots, by spot (#133); every other
## spot rolls one from its blueprint's list. Not hashed here: the wild monster feature hashes each
## wild monster's species.
var named_species: Dictionary[Vector2i, String] = {}
## Where treasure chests stand when the instance loads, in the region file's reading order. Not
## hashed here: the chest feature takes them over and hashes the ones still closed.
var chests: Array[Vector2i] = []
## A region piece's connectors (#57), its entry and exit points: (q, r) is a ground tile on the
## piece's edge and z the side (an index into Hex.DIRECTIONS) it opens to. Only pieces have them:
## arranging uses them up, so a region in a state has none and they aren't hashed.
var connectors: Array[Vector3i] = []
## Ways out into another instance (#120, #140): like a connector, (q, r) is a ground tile on the
## edge and z the side it leads out of, and `exit_blueprints` holds the blueprint each leads to.
## Unlike connectors they stay after arranging. Not hashed: they come from the blueprint's files and
## never change during a session.
var exits: Array[Vector3i] = []
var exit_blueprints: Array[String] = []
## Tile triggers (#183), each written in its piece's legend, in the region file's reading order:
## when something happens on a tile, an action runs (TriggerFeature). Not hashed: they come from the
## blueprint's files; the trigger feature hashes the ones that fired.
var triggers: Array[TileTrigger] = []
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
## water, `^` blocked, a digit 1 to 4 a player's start on ground, `m` a wild monster on ground, `c`
## a treasure chest on ground, and a space no tile. A region piece adds a line `connector <q> <r>
## <side>` for each connector, `exit <q> <r> <side> <blueprint>` for each exit, `species <q> <r>
## <species id>` for a wild monster spot whose species it names, and `trigger <q> <r> <when>
## <action> <amount>` for each tile trigger. A line `tile <q> <r> <tile blueprint id>` makes a
## tile of the grid that kind, before the other lines are read.
static func parse(text: String) -> Region:
	var region: Region = Region.new()
	var rows: Array[String] = []
	var connector_lines: Array[String] = []
	var tile_lines: Array[String] = []
	for line: String in text.split("\n"):
		var content: String = line.strip_edges()
		var keyed: bool = (content.begins_with(EXIT) or content.begins_with(SPECIES)
				or content.begins_with(TRIGGER))
		if content.begins_with(TILE):
			tile_lines.append(content)
		elif content.begins_with(CONNECTOR) or keyed:
			connector_lines.append(content)
		elif not content.begins_with("#") and not content.is_empty():
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
	for line: String in tile_lines + connector_lines:
		region.problem = region._parse_keyed(line)
		if not region.problem.is_empty():
			return region
	return region


func has_tile(tile: Vector2i) -> bool:
	return terrain.has(tile)


## Whether a walker can stand on the tile: on the region, and of a walkable kind.
func is_walkable(tile: Vector2i) -> bool:
	if walkable_overrides.has(tile):
		return terrain.has(tile) and walkable_overrides[tile]
	return terrain.has(tile) and TileKinds.is_walkable(terrain[tile])


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


## This region turned `turns` times by 60 degrees around the origin, with everything on it.
func turned(turns: int) -> Region:
	var region: Region = Region.new()
	for tile: Vector2i in sorted_tiles():
		region.terrain[Hex.turn(tile, turns)] = terrain[tile]
	region.starts.assign(starts.map(func(tile: Vector2i) -> Vector2i: return Hex.turn(tile, turns)))
	region.wild_monsters.assign(
		wild_monsters.map(func(tile: Vector2i) -> Vector2i: return Hex.turn(tile, turns)),
	)
	region.chests.assign(chests.map(func(tile: Vector2i) -> Vector2i: return Hex.turn(tile, turns)))
	region.connectors.assign(connectors.map(_turned_connector.bind(turns)))
	region.exits.assign(exits.map(_turned_connector.bind(turns)))
	region.exit_blueprints = exit_blueprints.duplicate()
	for trigger: TileTrigger in triggers:
		region.triggers.append(trigger.moved(Vector2i.ZERO, turns))
	for spot: Vector2i in named_species:
		region.named_species[Hex.turn(spot, turns)] = named_species[spot]
	for tile: Vector2i in decoration_turns:
		var turn: int = posmod(decoration_turns[tile] + turns, Hex.DIRECTIONS.size())
		region.decoration_turns[Hex.turn(tile, turns)] = turn
	for tile: Vector2i in walkable_overrides:
		region.walkable_overrides[Hex.turn(tile, turns)] = walkable_overrides[tile]
	return region


## Whether `piece`, moved by `offset`, would lie on tiles this region doesn't have yet, leaving the
## tile outside every exit free, so an exit always leads out of the region.
func fits(piece: Region, offset: Vector2i) -> bool:
	var kept_free: Array[Vector2i] = outside_exits()
	for tile: Vector2i in piece.terrain:
		if terrain.has(tile + offset) or kept_free.has(tile + offset):
			return false
	for outside: Vector2i in piece.outside_exits():
		if terrain.has(outside + offset):
			return false
	return true


## The tile just outside each exit, where it leads out of the region.
func outside_exits() -> Array[Vector2i]:
	var outside: Array[Vector2i] = []
	for exit: Vector3i in exits:
		outside.append(Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z])
	return outside


## Adds `piece`, moved by `offset`, with its wild monsters, chests, connectors, exits and triggers.
## The
## players' starts stay this region's own. Callers check `fits` first.
func place(piece: Region, offset: Vector2i) -> void:
	for tile: Vector2i in piece.sorted_tiles():
		terrain[tile + offset] = piece.terrain[tile]
	for spot: Vector2i in piece.wild_monsters:
		wild_monsters.append(spot + offset)
	for spot: Vector2i in piece.named_species:
		named_species[spot + offset] = piece.named_species[spot]
	for tile: Vector2i in piece.decoration_turns:
		decoration_turns[tile + offset] = piece.decoration_turns[tile]
	for tile: Vector2i in piece.walkable_overrides:
		walkable_overrides[tile + offset] = piece.walkable_overrides[tile]
	for spot: Vector2i in piece.chests:
		chests.append(spot + offset)
	for connector: Vector3i in piece.connectors:
		connectors.append(connector + Vector3i(offset.x, offset.y, 0))
	for exit: Vector3i in piece.exits:
		exits.append(exit + Vector3i(offset.x, offset.y, 0))
	exit_blueprints.append_array(piece.exit_blueprints)
	for trigger: TileTrigger in piece.triggers:
		triggers.append(trigger.moved(offset))


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
	var overridden: Array[Vector2i] = []
	overridden.assign(walkable_overrides.keys())
	overridden.sort()
	values.append(overridden.size())
	for tile: Vector2i in overridden:
		values.append_array([tile.x, tile.y, 1 if walkable_overrides[tile] else 0])
	return values


## Reads one `connector <q> <r> <side>` or `exit <q> <r> <side> <blueprint>` line; returns why it
## can't, or "". Both sit on a ground tile and open to a side where the piece has no tile.
func _parse_connector(line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	var exit: bool = line.begins_with(EXIT)
	var numbers: bool = parts.size() == (5 if exit else 4)
	for part: String in parts.slice(1, 4):
		numbers = numbers and part.is_valid_int()
	if not numbers:
		if exit:
			return "an exit line reads \"exit <q> <r> <side> <blueprint>\": " + line
		return "a connector line reads \"connector <q> <r> <side>\": " + line
	var tile: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	var side: int = parts[3].to_int()
	if side < 0 or side >= Hex.DIRECTIONS.size():
		return "%s side %d isn't 0 to 5" % [parts[0], side]
	if not is_walkable(tile) or has_tile(tile + Hex.DIRECTIONS[side]):
		return "%s %s doesn't open from ground to the edge on side %d" % [parts[0], tile, side]
	if exit:
		exits.append(Vector3i(tile.x, tile.y, side))
		exit_blueprints.append(parts[4])
	else:
		connectors.append(Vector3i(tile.x, tile.y, side))
	return ""


## Reads one keyed line: a tile's kind, a connector, an exit, a named species or a trigger.
## Returns why it can't, or "".
func _parse_keyed(line: String) -> String:
	if line.begins_with(TILE):
		return _parse_tile(line)
	if line.begins_with(SPECIES):
		return _parse_species(line)
	if line.begins_with(TRIGGER):
		return _parse_trigger(line)
	return _parse_connector(line)


## Reads one `trigger <q> <r> <when> <action> <amount>` line; returns why it can't, or "". A
## trigger stands on ground, with a when and an action TileTrigger knows and an amount of at least
## 1.
func _parse_trigger(line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	var numbers: bool = parts.size() == 6
	for i: int in [1, 2, 5]:
		numbers = numbers and parts.size() > i and parts[i].is_valid_int()
	if not numbers:
		return "a trigger line reads \"trigger <q> <r> <when> <action> <amount>\": " + line
	var tile: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	if not TileTrigger.WHENS.has(parts[3]) or not TileTrigger.ACTIONS.has(parts[4]):
		return "trigger %s: no such when or action: %s %s" % [tile, parts[3], parts[4]]
	if not is_walkable(tile) or parts[5].to_int() < 1:
		return "trigger %s isn't on ground or acts on nothing" % tile
	triggers.append(TileTrigger.new(tile, parts[3], parts[4], parts[5].to_int()))
	return ""


## Reads one `tile <q> <r> <tile blueprint id> [<turn>] [walkable | not_walkable]` line; returns
## why it can't, or "". It gives a tile of the grid its kind, its decoration a turn of 0 to 5
## sixths if it names one (#231), and overrides its kind's walkable trait for this tile if it says
## so (#201).
func _parse_tile(line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	if parts.size() < 4 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return "a tile line reads \"tile <q> <r> <tile blueprint id> [<turn>] [walkable]\": " + line
	var tile: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	var kind: int = TileKinds.number_of(parts[3])
	if not has_tile(tile) or kind < 0:
		return "tile %s isn't on the region, or %s isn't a tile blueprint" % [tile, parts[3]]
	terrain[tile] = kind
	for extra: String in parts.slice(4):
		var wrong: String = _parse_tile_extra(tile, extra)
		if not wrong.is_empty():
			return wrong
	return ""


## Reads what a tile line says after the tile's kind: its decoration's turn, or an override of its
## walkable trait. Returns why it can't, or "".
func _parse_tile_extra(tile: Vector2i, extra: String) -> String:
	if extra.is_valid_int():
		var turn: int = extra.to_int()
		if turn < 0 or turn >= Hex.DIRECTIONS.size():
			return "tile %s's turn %d isn't 0 to 5" % [tile, turn]
		if turn != 0:
			decoration_turns[tile] = turn
	elif extra == WALKABLE or extra == NOT_WALKABLE:
		walkable_overrides[tile] = extra == WALKABLE
	else:
		return "tile %s: %s is neither a turn nor %s or %s" % [tile, extra, WALKABLE, NOT_WALKABLE]
	return ""


## Reads one `species <q> <r> <species id>` line; returns why it can't, or "". It names the species
## of a wild monster spot, once.
func _parse_species(line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	var numbers: bool = parts.size() == 4 and parts[1].is_valid_int() and parts[2].is_valid_int()
	if not numbers:
		return "a species line reads \"species <q> <r> <species id>\": " + line
	var spot: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	if not wild_monsters.has(spot) or named_species.has(spot):
		return "species %s names no wild monster spot, or one named before" % spot
	named_species[spot] = parts[3]
	return ""


static func _turned_connector(connector: Vector3i, turns: int) -> Vector3i:
	var tile: Vector2i = Hex.turn(Vector2i(connector.x, connector.y), turns)
	return Vector3i(tile.x, tile.y, posmod(connector.z + turns, Hex.DIRECTIONS.size()))


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
		var known: bool = SYMBOLS.has(symbol) or symbol in [WILD_MONSTER, CHEST]
		if not known and (slot < 0 or slot >= GameState.MAX_PLAYERS):
			return "'%s' in row %d isn't a region symbol" % [symbol, r]
		var tile: Vector2i = Vector2i(Fixed.div_floor(doubled, 2), r)
		terrain[tile] = SYMBOLS.get(symbol, GROUND)
		if symbol == WILD_MONSTER:
			wild_monsters.append(tile)
		if symbol == CHEST:
			chests.append(tile)
		if slot >= 0 and starts_by_slot.has(slot):
			return "player %d's start is marked twice" % (slot + 1)
		if slot >= 0:
			starts_by_slot[slot] = tile
	if terrain.size() > MAX_TILES:
		return "the region has more than %d tiles" % MAX_TILES
	return ""
