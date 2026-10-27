class_name ControlPointFeature
extends Feature
## Control point battles (#580, #643): an instance made for one has control points its region
## pieces mark (ControlPointPlacements), each held by a side or by nobody. A side holds its points
## together, so in co-op every player of a side holds them alike (#74). A side holding no control
## point loses the battle: a BattleLost event, once. The attackers start with one (#580), which
## the region pieces mark; how a point changes hands, a ring and a totem like a domination, is
## #644.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "control_points"
## The sides of a battle, and a point nobody holds.
const NOBODY: int = -1
const ATTACKERS: int = 0
const DEFENDERS: int = 1
const BATTLE_SIDES: Array[int] = [ATTACKERS, DEFENDERS]

## Every control point, in the region's tile order.
var points: Array[Vector2i] = []
## The side holding each control point, in the order of `points`.
var holders: Array[int] = []
## The side that lost the battle, or NOBODY while it goes on.
var loser: int = NOBODY


func id() -> String:
	return ID


func start(state: GameState) -> void:
	var placed: Dictionary[Vector2i, String] = state.region.placed(ControlPointPlacements.KIND)
	points.assign(placed.keys())
	points.sort()
	holders.clear()
	for point: Vector2i in points:
		holders.append(ControlPointPlacements.side_of(placed[point]))


## Ends the battle once a side holds no control point: that side lost.
func step(state: GameState, _commands: Array[Command]) -> void:
	if loser != NOBODY:
		return
	for side: int in BATTLE_SIDES:
		if not holders.has(side):
			loser = side
			break
	if loser != NOBODY:
		state.events.append(BattleLost.new(loser))


func hash_values() -> Array[int]:
	var values: Array[int] = [points.size()]
	for index: int in points.size():
		values.append_array([points[index].x, points[index].y, holders[index]])
	values.append(loser)
	return values


## Who holds each point, in the order of `points`, and who lost; the points follow from the region.
func save_values() -> Dictionary:
	return { "holders": holders.duplicate(), "loser": loser }


func load_values(_state: GameState, values: DataReader) -> void:
	var held: Array[int] = values.wholes("holders", NOBODY, DEFENDERS)
	if held.size() != points.size():
		values.fail("the saved control points aren't the region's")
		return
	var lost: int = values.whole("loser", NOBODY, DEFENDERS)
	if values.failed():
		return
	holders = held
	loser = lost
