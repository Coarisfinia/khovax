class_name LegendMeaning
extends RefCounted
## What one symbol of a region document's legend stands for (#145), read from its meaning, and how
## it builds that onto the tiles it's drawn on: RegionDocument reads the document and builds its
## Region with these (#824). A meaning is one of:
## - `ground`, `water` or `rock`, `where player <n> starts` (on ground) or `a wild monster, of a
##   species rolled from the instance blueprint's list` (on ground)
## - what a slice places on ground, as its PlacementReader reads it (#824): a person to talk to
##   (NpcSpot), a treasure chest or loot on the ground (ChestPlacements), a tile trigger
##   (TileTrigger) or a wild monster of a named species (WildSpot); a reader may also name the tile
##   kind it stands on, which is read like a tile kind's meaning (below)
## - `joins another piece to the <side>`: a connector (#57)
## - `exit to the <side>, to <blueprint>`: an exit to another instance (#140)
## - `a wild monster hiding in <tile blueprint id>`: a wild monster, of a species rolled from the
##   instance blueprint's list, on a tile of that kind, which must hide (#202), e.g. `a wild monster
##   hiding in shrubs`
## - `<tile blueprint id>`: a tile of that kind (#116), e.g. `forest`. Clauses after the kind, each
##   after a ", ", change that tile: `turned <n>` turns its decoration by n sixths of a turn,
##   counter-clockwise (#231), so two symbols can stand for the same kind turned apart, and
##   `walkable` or `not walkable` overrides its kind's trait for this tile (#201), e.g. `forest, not
##   walkable`, and `height <n>` sets how tall it stands for crowns above it (#232), in hundredths
##   of a tile's radius, where its models' measured height doesn't fit, e.g. `shrubs, height 40`
## where <side> is one of SIDES. Every symbol but water and rock is ground unless it names a kind.

## The built-in terrains' meanings.
const TERRAINS: Dictionary[String, String] = {
	"ground": Region.GROUND,
	"water": Region.WATER,
	"rock": Region.BLOCKED,
}
## A player's start's meaning, with the player's number (1 to GameState.MAX_PLAYERS).
const START: String = "where player %d starts"
## A wild monster's meaning whose species is rolled from its blueprint's list (WildMonsterFeature,
## #19).
const ROLLED: String = "a wild monster, of a species rolled from the instance blueprint's list"
const CONNECTOR: String = "joins another piece to the "
## An exit's meaning, before its side and, after TO, its blueprint.
const EXIT: String = "exit to the "
const TO: String = ", to "
## A legend meaning placing a wild monster in a tile that hides it (#202), before the tile's kind.
const HIDING: String = "a wild monster hiding in "
## The sides of a tile, in Hex.DIRECTIONS' order.
const SIDES: Array[String] = ["east", "northeast", "northwest", "west", "southwest", "southeast"]
## What a tile kind's legend meaning says, after the kind, to turn its decoration (#231), to
## override its walkable trait (#201) or to set its height (#232), each clause after a ", ".
const TURNED: String = "turned "
const WALKABLE: String = "walkable"
const NOT_WALKABLE: String = "not walkable"
const HEIGHT: String = "height "

## The tile's terrain, before a kind it names.
var terrain: String = Region.GROUND
## The player slot starting here, or -1.
var start: int = -1
var wild_monster: bool = false
## The kind of thing a slice places here (#824, PlacementReader), or "", and the meaning it reads.
var placement: String = ""
var meaning_said: String = ""
## The tile kind (its id in TileKinds) it names, or "", with each turn, walkable override and height
## its clauses say, refused when one is said twice or is out of range.
var kind: String = ""
var turns: Array[int] = []
var walkable_overrides: Array[bool] = []
var heights: Array[int] = []
## The side a connector or exit opens to, or -1, and the blueprint an exit leads to.
var connector_side: int = -1
var exit_side: int = -1
var exit_blueprint: String = ""


## What `meaning` stands for, or null when it isn't understood; `readers` read what the slices
## place.
static func read(meaning: String, readers: Array[PlacementReader]) -> LegendMeaning:
	var read_one: LegendMeaning = LegendMeaning.new()
	var understood: bool = (read_one._read_placed(meaning)
			or read_one._read_slices(meaning, readers)
			or read_one._read_kind(meaning))
	return read_one if understood else null


## Builds what lies on `tile` itself: its terrain, its kind with its clauses, and a wild monster
## on it. Returns why it can't, or "".
func lay(region: Region, tile: Vector2i) -> String:
	region.terrain[tile] = terrain
	if wild_monster:
		region.wild_monsters.append(tile)
	if kind.is_empty():
		return ""
	region.terrain[tile] = kind
	if turns.size() > 1 or walkable_overrides.size() > 1 or heights.size() > 1:
		return "tile %s says its turn or its walkable trait twice" % tile
	for turn: int in turns:
		if turn < 0 or turn >= Hex.DIRECTIONS.size():
			return "tile %s's turn %d isn't 0 to 5" % [tile, turn]
		if turn != 0:
			region.looks.decoration_turns[tile] = turn
	for walkable: bool in walkable_overrides:
		region.walkable_overrides[tile] = walkable
	for height: int in heights:
		if height < 0 or height > PieceLooks.MAX_HEIGHT:
			return "tile %s's height %d isn't 0 to %d" % [tile, height, PieceLooks.MAX_HEIGHT]
		region.looks.height_overrides[tile] = height
	return ""


## Places what stands on `tile` or leads off it, once every tile is laid: a connector or exit,
## which open from ground to the edge, or what a slice places.
## Returns why it can't, or "".
func place(region: Region, tile: Vector2i) -> String:
	var side: int = maxi(connector_side, exit_side)
	if side >= 0:
		var what: String = "connector" if connector_side >= 0 else "exit"
		if not region.is_walkable(tile) or region.has_tile(tile + Hex.DIRECTIONS[side]):
			return "%s %s doesn't open from ground to the edge on side %d" % [what, tile, side]
		if connector_side >= 0:
			region.connectors.append(Vector3i(tile.x, tile.y, side))
		else:
			region.exits.append(Vector3i(tile.x, tile.y, side))
			region.exit_blueprints.append(exit_blueprint)
	return _place_on_ground(region, tile)


## Places what a slice places on `tile`, which must be ground. Returns why it can't, or "".
func _place_on_ground(region: Region, tile: Vector2i) -> String:
	if placement.is_empty():
		return ""
	if not region.is_walkable(tile):
		return "%s on %s isn't on ground" % [placement, tile]
	region.add_placement(placement, tile, meaning_said)
	return ""


## Reads a meaning built in, or one placing something on ground: a connector, an exit or a wild
## monster hiding in a tile kind. Returns whether it could.
func _read_placed(meaning: String) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		start = slot if meaning == START % (slot + 1) else start
	wild_monster = meaning == ROLLED
	terrain = TERRAINS.get(meaning, Region.GROUND)
	if start >= 0 or wild_monster or TERRAINS.has(meaning):
		return true
	if meaning.begins_with(CONNECTOR):
		connector_side = SIDES.find(meaning.trim_prefix(CONNECTOR))
		return connector_side >= 0
	if meaning.begins_with(EXIT):
		var exit: PackedStringArray = meaning.trim_prefix(EXIT).split(TO)
		if exit.size() != 2 or not exit[1].is_valid_ascii_identifier():
			return false
		exit_side = SIDES.find(exit[0])
		exit_blueprint = exit[1]
		return exit_side >= 0
	var hides_in: String = meaning.trim_prefix(HIDING)
	if meaning.begins_with(HIDING) and TileKinds.hides(hides_in):
		wild_monster = true
		kind = hides_in
		return true
	return false


## Reads a meaning one of `readers` knows, placing something of a slice's on ground (#824), on the
## tile kind the reader says it stands on, if any; returns whether one did.
func _read_slices(meaning: String, readers: Array[PlacementReader]) -> bool:
	for reader: PlacementReader in readers:
		placement = reader.kind_of(meaning)
		if not placement.is_empty():
			meaning_said = meaning
			wild_monster = reader.places_wild_monster()
			var stands_on: String = reader.tile_of(meaning)
			return stands_on.is_empty() or _read_kind(stands_on)
	return false


## Reads a tile kind's meaning (`stump`, or `stump, turned 3, not walkable`); returns whether it
## could, and leaves the kind unset when it couldn't.
func _read_kind(meaning: String) -> bool:
	var clauses: PackedStringArray = meaning.split(", ")
	var said_turns: Array[int] = []
	var said_overrides: Array[bool] = []
	var said_heights: Array[int] = []
	for clause: String in clauses.slice(1):
		var turn: String = clause.trim_prefix(TURNED)
		var height: String = clause.trim_prefix(HEIGHT)
		if clause.begins_with(TURNED) and turn.is_valid_int():
			said_turns.append(turn.to_int())
		elif clause.begins_with(HEIGHT) and height.is_valid_int():
			said_heights.append(height.to_int())
		elif clause == WALKABLE or clause == NOT_WALKABLE:
			said_overrides.append(clause == WALKABLE)
		else:
			return false
	if not TileKinds.has(clauses[0]):
		return false
	kind = clauses[0]
	turns = said_turns
	walkable_overrides = said_overrides
	heights = said_heights
	return true
