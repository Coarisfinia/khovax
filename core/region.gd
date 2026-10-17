class_name Region
extends RefCounted
## An instance's region (#36): which tiles exist, each one's kind (a tile blueprint, numbered by
## TileKinds, #116), and where the players start. Rules ask the region, never the distance from
## the origin, so a region can have any shape. Regions are hand-made Markdown files (regions/*.md,
## read by RegionDocument into the compact form RegionFormat reads, #145), or arranged from
## hand-made region pieces (regions/<blueprint>/) by RegionArranger (#57). This class holds the
## region's data and its geometry (turning, placing, fitting, reachability, hashing).

## The built-in kinds' numbers, as the tiles slice's data/tiles/ gives them; rock blocks sight
## (FogFeature).
const GROUND: int = 0
const WATER: int = 1
const BLOCKED: int = 2
## The most tiles a region may have: generators and region files stay within it.
const MAX_TILES: int = 4096

## Every tile's kind, its number in TileKinds, by tile.
var terrain: Dictionary[Vector2i, int] = {}
## How far a tile's decoration is turned, in sixths of a turn counter-clockwise like Hex.turn, for
## the tiles whose piece turns it by hand (#231); it turns with the region. A look, not a rule:
## not hashed, and only the views read it.
var decoration_turns: Dictionary[Vector2i, int] = {}
## How tall a tile stands, set by hand in its region piece (#232), in hundredths of a tile's radius,
## for the check that a crown above it leaves it room; every other tile is as tall as its tallest
## object, measured from the models. Not a rule, so not hashed.
var height_overrides: Dictionary[Vector2i, int] = {}
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
## Where loot lies on the ground when the instance loads (#203), in the region file's reading order:
## found by stepping onto it, like a chest without one. Not hashed here: the chest feature takes
## them over and hashes the ones still lying.
var loot_spots: Array[Vector2i] = []
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
## The region piece each tile was arranged from (#350), by the piece's file name in its blueprint's
## folder, which entering it raises (EnteringFeature); empty for a region from one file. Not hashed:
## it comes from the blueprint's files.
var piece_of: Dictionary[Vector2i, String] = {}
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
	region.loot_spots.assign(
		loot_spots.map(func(tile: Vector2i) -> Vector2i: return Hex.turn(tile, turns)),
	)
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
	for tile: Vector2i in height_overrides:
		region.height_overrides[Hex.turn(tile, turns)] = height_overrides[tile]
	for tile: Vector2i in walkable_overrides:
		region.walkable_overrides[Hex.turn(tile, turns)] = walkable_overrides[tile]
	for tile: Vector2i in piece_of:
		region.piece_of[Hex.turn(tile, turns)] = piece_of[tile]
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


## Adds `piece`, moved by `offset`, with its wild monsters, chests, connectors, exits, triggers and
## which piece each tile came from. The players' starts stay this region's own. Callers check `fits`
## first.
func place(piece: Region, offset: Vector2i) -> void:
	for tile: Vector2i in piece.sorted_tiles():
		terrain[tile + offset] = piece.terrain[tile]
	for spot: Vector2i in piece.wild_monsters:
		wild_monsters.append(spot + offset)
	for spot: Vector2i in piece.named_species:
		named_species[spot + offset] = piece.named_species[spot]
	for tile: Vector2i in piece.decoration_turns:
		decoration_turns[tile + offset] = piece.decoration_turns[tile]
	for tile: Vector2i in piece.height_overrides:
		height_overrides[tile + offset] = piece.height_overrides[tile]
	for tile: Vector2i in piece.walkable_overrides:
		walkable_overrides[tile + offset] = piece.walkable_overrides[tile]
	for spot: Vector2i in piece.chests:
		chests.append(spot + offset)
	for spot: Vector2i in piece.loot_spots:
		loot_spots.append(spot + offset)
	for connector: Vector3i in piece.connectors:
		connectors.append(connector + Vector3i(offset.x, offset.y, 0))
	for exit: Vector3i in piece.exits:
		exits.append(exit + Vector3i(offset.x, offset.y, 0))
	exit_blueprints.append_array(piece.exit_blueprints)
	for trigger: TileTrigger in piece.triggers:
		triggers.append(trigger.moved(offset))
	for tile: Vector2i in piece.piece_of:
		piece_of[tile + offset] = piece.piece_of[tile]


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


static func _turned_connector(connector: Vector3i, turns: int) -> Vector3i:
	var tile: Vector2i = Hex.turn(Vector2i(connector.x, connector.y), turns)
	return Vector3i(tile.x, tile.y, posmod(connector.z + turns, Hex.DIRECTIONS.size()))
