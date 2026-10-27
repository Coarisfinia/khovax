class_name ControlPointPlacements
extends PlacementReader
## Reads the control points (#580, #643) a region's legend places, for ControlPointFeature: only the
## region pieces of instances made for control point battles (conquests, #548, and defense
## missions, #579) mark them, each with the side holding it when the battle starts ("a control
## point, held by the attackers"). Ordinary instances have none, so they have no battle.

## The kind the region keeps them under (Region.placements).
const KIND: String = "control_point"
## A control point's legend meaning before the side holding it.
const HELD_BY: String = "a control point, held by "
## Who holds a control point at the start, by the words naming them.
const SIDES: Dictionary[String, int] = {
	"the attackers": ControlPointFeature.ATTACKERS,
	"the defenders": ControlPointFeature.DEFENDERS,
	"nobody": ControlPointFeature.NOBODY,
}
## A side no legend names.
const UNKNOWN: int = -2


func kinds() -> Array[String]:
	return [KIND]


func feature() -> String:
	return ControlPointFeature.ID


func kind_of(meaning: String) -> String:
	return KIND if side_of(meaning) != UNKNOWN else ""


## The side holding the control point `meaning` places at the start, or UNKNOWN when it places none.
static func side_of(meaning: String) -> int:
	if not meaning.begins_with(HELD_BY):
		return UNKNOWN
	return SIDES.get(meaning.trim_prefix(HELD_BY), UNKNOWN)
