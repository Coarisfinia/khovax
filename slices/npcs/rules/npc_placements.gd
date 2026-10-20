class_name NpcPlacements
extends PlacementReader
## Reads the people a region's legend places (#557, #824), each an NpcSpot, for NpcFeature.

## The kind the region keeps its people under (Region.placements).
const KIND: String = "npc"


func kinds() -> Array[String]:
	return [KIND]


func feature() -> String:
	return NpcFeature.ID


func kind_of(meaning: String) -> String:
	return KIND if NpcSpot.read(meaning) != null else ""
