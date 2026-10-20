class_name ChestPlacements
extends PlacementReader
## Reads the treasure chests (#124) and the loot on the ground (#203) a region's legend places
## (#824), for ChestFeature.

## The kinds the region keeps them under (Region.placements).
const CHEST: String = "chest"
const LOOT: String = "loot"
## Their legend meanings, by kind.
const MEANINGS: Dictionary[String, String] = {
	"a treasure chest": CHEST,
	"loot on the ground": LOOT,
}


func kind_of(meaning: String) -> String:
	return MEANINGS.get(meaning, "")
