class_name ForageWay
extends RefCounted
## Where a wild monster goes for its food or water (#1203): the tile where it feeds that it reaches
## in the fewest steps over the ground it may step onto (WildWay.nearest), not the nearest as the
## crow flies, so food behind a wall it can't soon walk round doesn't stall it (#1291).
## WildMonsterFeature.chase then walks it there, a step at a time. It looks as far as a wild monster
## looks ahead for its way (WildWay.REACH, #1274), so one reach tunes both.


## The tile where a monster at `from` doing `activity` (Schedule.GRAZE or Schedule.DRINK) feeds
## (`feeds_at`) that it reaches first within WildWay.REACH steps, over walkable ground in neither
## `blocked` nor `stuck` (WildWay): `from` itself when it feeds there already, or when no such
## tile is within reach.
static func target(
	region: Region,
	stuck: Dictionary[Vector2i, bool],
	blocked: Dictionary[Vector2i, bool],
	from: Vector2i,
	activity: int,
) -> Vector2i:
	if feeds_at(region, from, activity):
		return from
	var way: WildWay = WildWay.new(region, stuck, blocked)
	return way.nearest(from, func(tile: Vector2i) -> bool: return feeds_at(region, tile, activity))


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
