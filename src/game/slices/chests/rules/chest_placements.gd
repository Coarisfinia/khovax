class_name ChestPlacements
extends PlacementReader
## Reads the treasure chests (#124) and the loot on the ground (#203) a region's legend places
## (#824), for ChestFeature: what it is, then where it stands ("a treasure chest on the ground",
## "loot on mana_moss", #1260), so a chest or loot fits the tiles around it. A chest may name the
## one
## item it holds instead of rolling on the instance's chest table ("a treasure chest holding
## vis_omera on the ground", #1592): a unique item found in the world (#1553).

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
## Between a chest's name and the id of the one item it holds.
const HOLDING: String = " holding "


func kinds() -> Array[String]:
	return [CHEST, LOOT]


func feature() -> String:
	return ChestFeature.ID


func kind_of(meaning: String) -> String:
	var parts: PackedStringArray = meaning.split(ON, true, 1)
	if parts.size() != 2:
		return ""
	var named: PackedStringArray = parts[0].split(HOLDING, true, 1)
	if named.size() == 2 and (NAMES.get(named[0], "") != CHEST or not Ids.is_id(named[1])):
		return ""
	return NAMES.get(named[0], "")


func tile_of(meaning: String) -> String:
	var stands_on: String = meaning.split(ON, true, 1)[1]
	return "" if stands_on == GROUND else stands_on


## The id of the one item the chest a legend `meaning` places holds, or "" for one that rolls on the
## instance's chest table.
static func held(meaning: String) -> String:
	var named: PackedStringArray = meaning.split(ON, true, 1)[0].split(HOLDING, true, 1)
	return named[1] if named.size() == 2 else ""
