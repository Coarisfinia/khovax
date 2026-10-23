class_name ForageWay
extends RefCounted
## Where a wild monster goes for its food or water (#1203): the nearest tile within a reach where
## it feeds, of the ground it may stand on (a ring could enclose it there and nothing stands
## there, the ground WildMonsterFeature lets it step onto, WildGround). WildMonsterFeature.chase
## then finds its way there round whatever stands between (WildWay).

## How many tiles away a wild monster looks for grass or water. A placeholder to tune (#960).
const REACH: int = 10


## The tile nearest to `from` within REACH where a monster doing `activity` (Schedule.GRAZE or
## Schedule.DRINK) feeds (`feeds_at`) and may stand (walkable, in neither `blocked` nor `stuck`),
## the first in Hex.disc's order of the equally near: `from` itself when it feeds there already,
## or when no such tile is within reach.
static func target(
	region: Region,
	stuck: Dictionary[Vector2i, bool],
	blocked: Dictionary[Vector2i, bool],
	from: Vector2i,
	activity: int,
) -> Vector2i:
	if feeds_at(region, from, activity):
		return from
	# Ring by ring from `from`, so the first that fits is the nearest.
	for tile: Vector2i in Hex.disc(REACH, from):
		if blocked.has(tile) or stuck.has(tile) or not region.is_walkable(tile):
			continue
		if feeds_at(region, tile, activity):
			return tile
	return from


## Whether a monster doing `activity` feeds on `tile` of `region`: a grazing one on grass, a
## drinking one beside water (TileKinds); one doing anything else feeds nowhere.
static func feeds_at(region: Region, tile: Vector2i, activity: int) -> bool:
	if not region.has_tile(tile):
		return false
	if activity == Schedule.GRAZE:
		return TileKinds.is_grazable(region.terrain[tile])
	if activity != Schedule.DRINK:
		return false
	for direction: Vector2i in Hex.DIRECTIONS:
		var side: Vector2i = tile + direction
		if region.has_tile(side) and TileKinds.is_drinkable(region.terrain[side]):
			return true
	return false
