class_name SurveyExitArrow
extends RefCounted
## Where the Survey draws an exit's arrow (#790): an exit is several tiles wide (#689), and it gets
## one arrow, in its middle, pointing out across its side. Neighbouring exit tiles that lead out of
## the same side to the same blueprint are one exit. Its arrow sits on the middle one of its tiles,
## or between the two middle ones when it is an even number wide.

## Where the arrow's middle lies on the ground, in world units on the XZ plane, north up.
var at: Vector2 = Vector2.ZERO
## The side the exit leads out of, an index into Hex.DIRECTIONS.
var side: int = 0


## One arrow per exit among `exits`, each exit tile (q, r, side) like Region.exits with the
## blueprint it leads to, in the order of each exit's first tile.
static func of(exits: Dictionary[Vector3i, String]) -> Array[SurveyExitArrow]:
	var arrows: Array[SurveyExitArrow] = []
	var grouped: Dictionary[Vector3i, bool] = {}
	for exit: Vector3i in exits:
		if not grouped.has(exit):
			arrows.append(_middle_of(_group(exits, exit, grouped), exit.z))
	return arrows


## The tiles of the exit `first` belongs to, each marked in `grouped`: those reached from it tile by
## tile through neighbours on its side, to its blueprint.
static func _group(
		exits: Dictionary[Vector3i, String],
		first: Vector3i,
		grouped: Dictionary[Vector3i, bool],
) -> Array[Vector2i]:
	grouped[first] = true
	var group: Array[Vector2i] = [Vector2i(first.x, first.y)]
	var next: int = 0
	while next < group.size():
		var tile: Vector2i = group[next]
		next += 1
		for exit: Vector3i in exits:
			var there: Vector2i = Vector2i(exit.x, exit.y)
			var same: bool = exit.z == first.z and exits[exit] == exits[first]
			if not grouped.has(exit) and same and Hex.distance(tile, there) == 1:
				grouped[exit] = true
				group.append(there)
	return group


## The arrow of the exit on `tiles`, out of the side `out_of`: on its middle tile along its edge,
## or between the two middle ones.
static func _middle_of(tiles: Array[Vector2i], out_of: int) -> SurveyExitArrow:
	var along: Vector2 = SurveyView.ground_of(Hex.DIRECTIONS[out_of]).orthogonal()
	var grounds: Array[Vector2] = []
	for tile: Vector2i in tiles:
		grounds.append(SurveyView.ground_of(tile))
	grounds.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.dot(along) < b.dot(along))
	var half: int = floori(grounds.size() / 2.0)
	var arrow: SurveyExitArrow = SurveyExitArrow.new()
	arrow.side = out_of
	arrow.at = grounds[half]
	if grounds.size() % 2 == 0:
		arrow.at = (grounds[half - 1] + grounds[half]) / 2.0
	return arrow
