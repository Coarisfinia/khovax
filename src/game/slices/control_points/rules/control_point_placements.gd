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
	"the attackers": ControlPointSides.ATTACKERS,
	"the defenders": ControlPointSides.DEFENDERS,
	"nobody": ControlPointSides.NOBODY,
}
## A side no legend names.
const UNKNOWN: int = -2


func kinds() -> Array[String]:
	return [KIND]


func feature() -> String:
	return ControlPointFeature.ID


func kind_of(meaning: String) -> String:
	return KIND if side_of(meaning) != UNKNOWN else ""


## A control point is taken by closing a ring around it (#644), and no ring encloses a tile on the
## edge (RingShape.outside floods in from there), so one marked there could never be taken (#1495).
## Asked of each region piece, whose edge may later join a neighbour: a point stays off it anyway.
func problem_in(region: Region) -> String:
	for tile: Vector2i in region.placed(KIND):
		if RingShape.on_edge(region, tile):
			return "the control point on %s is on the region's edge: no ring encloses it" % tile
	return ""


## The side holding the control point `meaning` places at the start, or UNKNOWN when it places none.
static func side_of(meaning: String) -> int:
	if not meaning.begins_with(HELD_BY):
		return UNKNOWN
	return SIDES.get(meaning.trim_prefix(HELD_BY), UNKNOWN)
