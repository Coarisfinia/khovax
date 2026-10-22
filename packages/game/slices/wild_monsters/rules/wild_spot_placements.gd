class_name WildSpotPlacements
extends PlacementReader
## Reads the named wild monsters a region's legend places (#133, #824), each a WildSpot, for
## WildMonsterFeature. Each is a wild monster's spot too, which the core keeps
## (Region.wild_monsters), and stands on the tile kind it names, or on ground.

## The kind the region keeps its named wild monsters under (Region.placements).
const KIND: String = "wild_spot"


func kinds() -> Array[String]:
	return [KIND]


func feature() -> String:
	return WildMonsterFeature.ID


func kind_of(meaning: String) -> String:
	return KIND if WildSpot.read(meaning) != null else ""


func tile_of(meaning: String) -> String:
	var spot: WildSpot = WildSpot.read(meaning)
	return spot.stands_on if spot != null else ""


func places_wild_monster() -> bool:
	return true


## A quest target is one monster (#625): marked once.
func problem_in(region: Region) -> String:
	var targets: Array[String] = []
	var placed: Dictionary[Vector2i, String] = region.placed(KIND)
	for tile: Vector2i in placed:
		var target: String = WildSpot.read(placed[tile]).target
		if targets.has(target):
			return "the quest target %s is one monster, marked once" % target
		if not target.is_empty():
			targets.append(target)
	return ""
