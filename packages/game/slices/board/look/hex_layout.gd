class_name HexLayout
extends RefCounted
## Where hex tiles are drawn: the only tile-to-world conversion. For presentation only; the
## simulation never sees these floats. Pointy-top hexes on the XZ ground plane, north up the
## screen (towards -z).

## World distance from a tile's center to its corners.
const SIZE: float = 1.0


## The center of a tile on the ground plane (y = 0).
static func to_world(tile: Vector2i) -> Vector3:
	var x: float = SIZE * sqrt(3.0) * (tile.x + tile.y / 2.0)
	var z: float = SIZE * 1.5 * tile.y
	return Vector3(x, 0.0, z)
