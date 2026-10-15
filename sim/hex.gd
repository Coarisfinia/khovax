class_name Hex
extends RefCounted
## Hex grid math for the simulation. Tiles are integer axial coordinates (q, r) as Vector2i,
## pointy-top. Integers only: where tiles are drawn lives in HexLayout (view), and turning analog
## input into a direction lives in HexInput (input).

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
