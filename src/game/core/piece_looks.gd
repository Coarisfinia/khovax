class_name PieceLooks
extends RefCounted
## How a region's tiles look where their piece sets it by hand, beyond their kind: looks, not rules,
## so not hashed, and only the views and the content checks read them. Region keeps them apart from
## its rules' data, and turns and places them with the region.

## The tallest a tile may be set by hand, so a typo can't make one tile block every crown.
const MAX_HEIGHT: int = 1000

## How far a tile's decoration is turned, in sixths of a turn counter-clockwise like Hex.turn, for
## the tiles whose piece turns it by hand (#231); it turns with the region.
var decoration_turns: Dictionary[Vector2i, int] = {}
## How tall a tile stands, set by hand in its region piece (#232), in hundredths of a tile's radius,
## for the check that a crown above it leaves it room; every other tile is as tall as its tallest
## object, measured from the models.
var height_overrides: Dictionary[Vector2i, int] = {}
## The floor (#2498) under a tile of another kind, for the tiles of a piece that has one (#2587):
## its hex shows the floor's color under the tile's decoration, so a boulder on flagstone doesn't
## stand on a patch of grass.
var floors: Dictionary[Vector2i, String] = {}


## These looks turned `turns` times by 60 degrees around the origin, with their region.
func turned(turns: int) -> PieceLooks:
	var looks: PieceLooks = PieceLooks.new()
	for tile: Vector2i in decoration_turns:
		var turn: int = posmod(decoration_turns[tile] + turns, Hex.DIRECTIONS.size())
		looks.decoration_turns[Hex.turn(tile, turns)] = turn
	for tile: Vector2i in height_overrides:
		looks.height_overrides[Hex.turn(tile, turns)] = height_overrides[tile]
	for tile: Vector2i in floors:
		looks.floors[Hex.turn(tile, turns)] = floors[tile]
	return looks


## Adds a piece's `looks`, moved by `offset`, as Region.place adds the piece.
func place(looks: PieceLooks, offset: Vector2i) -> void:
	for tile: Vector2i in looks.decoration_turns:
		decoration_turns[tile + offset] = looks.decoration_turns[tile]
	for tile: Vector2i in looks.height_overrides:
		height_overrides[tile + offset] = looks.height_overrides[tile]
	for tile: Vector2i in looks.floors:
		floors[tile + offset] = looks.floors[tile]
