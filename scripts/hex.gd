class_name Hex
extends RefCounted
## Hex grid math. Tiles are addressed by integer axial coordinates (q, r) as Vector2i, so the
## deterministic simulation can work on them without floats. Pointy-top hexes on the XZ ground
## plane.
## The tile-to-world conversion lives only here; it is for rendering, never for simulation logic.

## World distance from a tile's center to its corners.
const SIZE: float = 1.0
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
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


## The center of a tile on the ground plane (y = 0).
static func to_world(tile: Vector2i) -> Vector3:
	var x: float = SIZE * sqrt(3.0) * (tile.x + tile.y / 2.0)
	var z: float = SIZE * 1.5 * tile.y
	return Vector3(x, 0.0, z)
