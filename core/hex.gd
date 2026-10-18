class_name Hex
extends RefCounted
## Hex grid math for the simulation. Tiles are integer axial coordinates (q, r) as Vector2i,
## pointy-top. Integers only: where tiles are drawn lives in HexLayout (the board's look), and
## turning analog input into a direction lives in HexInput (game).

## How finely Hex.line divides each step, so points along a line stay whole numbers.
const LINE_SCALE: int = 1_000_000
## Entry i points i * 60 degrees counter-clockwise from screen-right: E, NE, NW, W, SW, SE.
## North is up the screen.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


static func distance(a: Vector2i, b: Vector2i) -> int:
	# The largest of the three cube-coordinate differences: the same as half their sum, without a
	# division.
	var d: Vector2i = a - b
	return maxi(maxi(absi(d.x), absi(d.y)), absi(d.x + d.y))


## Every tile within `radius` steps of `center`, center first, then ring by ring.
static func disc(radius: int, center: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [center]
	for ring_radius: int in range(1, radius + 1):
		tiles.append_array(ring(ring_radius, center))
	return tiles


## The tiles exactly `radius` steps from `center`.
static func ring(radius: int, center: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var tile: Vector2i = center + DIRECTIONS[4] * radius
	for side: int in 6:
		for _step: int in radius:
			tiles.append(tile)
			tile += DIRECTIONS[side]
	return tiles


## `tile` turned `turns` times by 60 degrees counter-clockwise around the origin, the way
## DIRECTIONS goes round: DIRECTIONS[i] turns into DIRECTIONS[i + turns].
static func turn(tile: Vector2i, turns: int) -> Vector2i:
	var turned: Vector2i = tile
	for _turn: int in posmod(turns, 6):
		# In cube coordinates one turn is (x, y, z) -> (-y, -z, -x), with y = -q - r and z = r.
		turned = Vector2i(turned.x + turned.y, -turned.x)
	return turned


## The tiles on the straight line from `a` to `b`, both included, in order: the hex cells the line
## between their centers passes through. Integers only: each point along the line is scaled by
## LINE_SCALE instead of being a fraction, and nudged by a tiny fixed amount so a line running
## exactly between two tiles always picks the same one.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var steps: int = distance(a, b)
	var tiles: Array[Vector2i] = [a]
	for i: int in range(1, steps + 1):
		tiles.append(_point_on_line(a, b, i, steps))
	return tiles


## The tile at step `i` of `steps` from `a` towards `b`, in cube coordinates rounded to the nearest
## tile, with the coordinate that rounded furthest set from the other two.
static func _point_on_line(a: Vector2i, b: Vector2i, i: int, steps: int) -> Vector2i:
	var scale: int = steps * LINE_SCALE
	var nudge: Vector3i = Vector3i(1, 1, -2)
	var from: Vector3i = Vector3i(a.x, -a.x - a.y, a.y) * scale
	var toward: Vector3i = Vector3i(b.x - a.x, a.x + a.y - b.x - b.y, b.y - a.y) * (i * LINE_SCALE)
	var point: Vector3i = from + toward + nudge
	var rounded: Vector3i = Vector3i(
		Fixed.div_floor(2 * point.x + scale, 2 * scale),
		Fixed.div_floor(2 * point.y + scale, 2 * scale),
		Fixed.div_floor(2 * point.z + scale, 2 * scale),
	)
	var off: Vector3i = (rounded * scale - point).abs()
	if off.x > off.y and off.x > off.z:
		rounded.x = -rounded.y - rounded.z
	elif off.y > off.z:
		rounded.y = -rounded.x - rounded.z
	else:
		rounded.z = -rounded.x - rounded.y
	return Vector2i(rounded.x, rounded.z)
