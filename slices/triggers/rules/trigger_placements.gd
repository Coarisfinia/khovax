class_name TriggerPlacements
extends PlacementReader
## Reads the tile triggers a region's legend places (#183, #824), each a TileTrigger, for
## TriggerFeature. When what a trigger's tile is names a tile kind, the tile is that kind too
## (#349), e.g. `forest; stepping here reaches the place grove`; otherwise it's ground.

## The kind the region keeps its triggers under (Region.placements).
const KIND: String = "trigger"


func kind_of(meaning: String) -> String:
	return KIND if TileTrigger.read(meaning) != null else ""


func tile_of(meaning: String) -> String:
	var what: String = TileTrigger.what_it_is(meaning)
	return what if TileKinds.has(what.get_slice(", ", 0)) else ""
