class_name SurveyExitArrow
extends RefCounted
## Where the Survey draws an exit's arrow (#790): an exit is several tiles wide (#689), and it gets
## one arrow, in its middle, pointing out across its side. Neighbouring exit tiles that lead out of
## the same side to the same blueprint are one exit. Its arrow sits on the middle one of its tiles,
## or between the two middle ones when it is an even number wide. Where an exit and the exit that
## leads back through it face each other across a seam (#799), only the one pointing away from the
## player shows, so outward: walking into the other instance flips which one it is.

## Where the arrow's middle lies on the ground, in world units on the XZ plane, north up.
var at: Vector2 = Vector2.ZERO
## The side the exit leads out of, an index into Hex.DIRECTIONS.
var side: int = 0


## One arrow per exit among `exits`, each exit tile (q, r, side) like Region.exits with the
## blueprint it leads to, in the order of each exit's first tile, seen by a player at `from`, a
## ground point in world units: an exit tile facing one that points away from them shows none.
static func of(exits: Dictionary[Vector3i, String], from: Vector2) -> Array[SurveyExitArrow]:
	var shown: Dictionary[Vector3i, String] = {}
	for exit: Vector3i in exits:
		if not _gives_way(exits, exit, from):
			shown[exit] = exits[exit]
	var arrows: Array[SurveyExitArrow] = []
	var grouped: Dictionary[Vector3i, bool] = {}
	for exit: Vector3i in shown:
		if not grouped.has(exit):
			arrows.append(_middle_of(_group(shown, exit, grouped), exit.z))
	return arrows


## Whether `exit` faces the exit tile right across its side, leading back through it, while pointing
## towards `from`: then that one points away and shows instead. On a tie, both show.
static func _gives_way(
		exits: Dictionary[Vector3i, String],
		exit: Vector3i,
		from: Vector2,
) -> bool:
	var tile: Vector2i = Vector2i(exit.x, exit.y)
	var across: Vector2i = tile + Hex.DIRECTIONS[exit.z]
	var back: int = posmod(exit.z + 3, Hex.DIRECTIONS.size())
	if not exits.has(Vector3i(across.x, across.y, back)):
		return false
	var seam: Vector2 = (SurveyView.ground_of(tile) + SurveyView.ground_of(across)) / 2.0
	return SurveyView.ground_of(Hex.DIRECTIONS[exit.z]).dot(seam - from) < 0.0


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
