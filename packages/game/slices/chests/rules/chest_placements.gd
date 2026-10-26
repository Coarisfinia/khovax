class_name ChestPlacements
extends PlacementReader
## Reads the treasure chests (#124) and the loot on the ground (#203) a region's legend places
## (#824), for ChestFeature: what it is, then where it stands ("a treasure chest on the ground",
## "loot on mana_moss", #1260), so a chest or loot fits the tiles around it.

## The kinds the region keeps them under (Region.placements).
const CHEST: String = "chest"
const LOOT: String = "loot"
## Their legend names, by kind, each followed by where it stands.
const NAMES: Dictionary[String, String] = {
	"a treasure chest": CHEST,
	"loot": LOOT,
}
## Between its name and where it stands: on the ground, or on a tile kind.
const ON: String = " on "
const GROUND: String = "the ground"


func kinds() -> Array[String]:
	return [CHEST, LOOT]


func feature() -> String:
	return ChestFeature.ID


func kind_of(meaning: String) -> String:
	var parts: PackedStringArray = meaning.split(ON, true, 1)
	return NAMES.get(parts[0], "") if parts.size() == 2 else ""


func tile_of(meaning: String) -> String:
	var stands_on: String = meaning.split(ON, true, 1)[1]
	return "" if stands_on == GROUND else stands_on
