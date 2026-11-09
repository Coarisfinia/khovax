class_name HexLayout
extends RefCounted
## Where hex tiles are drawn: the only conversion between tiles and the world, both ways. For
## presentation only; the
## simulation never sees these floats. Pointy-top hexes on the XZ ground plane, north up the
## screen (towards -z).

## World distance from a tile's center to its corners.
const SIZE: float = 1.0


## The center of a tile on the ground plane (y = 0).
static func to_world(tile: Vector2i) -> Vector3:
	var x: float = SIZE * sqrt(3.0) * (tile.x + tile.y / 2.0)
	var z: float = SIZE * 1.5 * tile.y
	return Vector3(x, 0.0, z)


## The tile whose hex holds `world`, a point on the ground plane (y ignored): to_world's inverse,
## for a tap or click on the board (#1508).
static func to_tile(world: Vector3) -> Vector2i:
	var r: float = world.z / (SIZE * 1.5)
	var q: float = world.x / (SIZE * sqrt(3.0)) - r / 2.0
	# Rounded in cube coordinates: the one off most from its rounding is made up from the others.
	var s: float = -q - r
	var round_q: float = roundf(q)
	var round_r: float = roundf(r)
	var round_s: float = roundf(s)
	var off_q: float = absf(round_q - q)
	var off_r: float = absf(round_r - r)
	if off_q > off_r and off_q > absf(round_s - s):
		round_q = -round_r - round_s
	elif off_r > absf(round_s - s):
		round_r = -round_q - round_s
	return Vector2i(roundi(round_q), roundi(round_r))
